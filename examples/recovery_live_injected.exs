defmodule Tinkex.Examples.RecoveryLiveInjected do
  @moduledoc """
  Live recovery walkthrough with an injected corruption flag.

  What this does:
    * Creates a live training client and saves a checkpoint.
    * Wraps `Rest.get_training_run/2` to return `corrupted: true` on the next poll only.
    * Starts the recovery monitor + executor to restore from the latest checkpoint.
    * Saves a second checkpoint from the recovered client to prove the restart worked.

  Requirements: `TINKER_API_KEY`, optional `TINKER_BASE_URL` and `TINKER_BASE_MODEL`.
  """

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_base_model "meta-llama/Llama-3.1-8B"
  @await_timeout 90_000

  alias Tinkex.Error
  alias Tinkex.ServiceClient
  alias Tinkex.TrainingClient
  alias Tinkex.Recovery.{Executor, Monitor, Policy}
  alias Tinkex.Types.{LoraConfig, ParsedCheckpointTinkerPath, SaveWeightsResponse}

  defmodule InjectedRest do
    @moduledoc false
    alias Tinkex.API.Rest
    alias Tinkex.Types.TrainingRun

    @key {__MODULE__, :agent}

    def start_state(run_id) do
      agent = Agent.start_link(fn -> %{run_id: run_id, inject?: false} end)

      case agent do
        {:ok, pid} ->
          :persistent_term.put(@key, pid)
          {:ok, pid}

        other ->
          other
      end
    end

    def flag_corruption do
      case :persistent_term.get(@key, nil) do
        nil -> :ok
        agent -> Agent.update(agent, &Map.put(&1, :inject?, true))
      end
    end

    def stop do
      case :persistent_term.get(@key, nil) do
        nil ->
          :ok

        agent ->
          :persistent_term.erase(@key)
          Agent.stop(agent)
      end
    end

    def get_training_run(config, run_id) do
      case Rest.get_training_run(config, run_id) do
        {:ok, %TrainingRun{} = run} ->
          {:ok, maybe_inject(run)}

        other ->
          other
      end
    end

    defp maybe_inject(run) do
      case :persistent_term.get(@key, nil) do
        nil ->
          run

        agent ->
          injected? =
            Agent.get_and_update(agent, fn %{inject?: inject?} = state ->
              {inject?, %{state | inject?: false}}
            end)

          if injected?, do: %{run | corrupted: true}, else: run
      end
    end
  end

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_base_model)

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    parent = self()

    with {:ok, service} <- ServiceClient.start_link(config: config),
         {:ok, training} <-
           ServiceClient.create_lora_training_client(service, base_model,
             lora_config: %LoraConfig{rank: 8}
           ),
         {:ok, first_path} <- save_checkpoint(training, "recovery-live-1"),
         {:ok, run_id} <- run_id_from_path(first_path),
         {:ok, _agent} <- InjectedRest.start_state(run_id),
         :ok <- InjectedRest.flag_corruption(),
         policy <- build_policy(parent),
         {:ok, executor} <- Executor.start_link(max_concurrent: 1),
         {:ok, monitor} <-
           Monitor.start_link(
             policy: policy,
             executor: executor,
             rest_module: InjectedRest,
             rest_client_fun: fn _ -> {:ok, %{config: config}} end
           ),
         :ok <- Monitor.monitor_run(monitor, run_id, service, %{training_pid: training}),
         {:ok, recovered_pid, checkpoint} <- await_recovery(),
         {:ok, second_path} <- save_checkpoint(recovered_pid, "recovery-live-2") do
      IO.puts("Recovered from #{checkpoint.tinker_path}")
      IO.puts("Second checkpoint saved: #{second_path}")
      cleanup([monitor, executor, training, recovered_pid, service])
      InjectedRest.stop()
      :ok
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "[error] #{Error.format(error)}")
        if error.data, do: IO.puts(:stderr, inspect(error.data))
        InjectedRest.stop()
        System.halt(1)

      {:error, other} ->
        IO.puts(:stderr, "[error] #{inspect(other)}")
        InjectedRest.stop()
        System.halt(1)
    end
  end

  defp build_policy(parent) do
    Policy.new(
      enabled: true,
      checkpoint_strategy: :latest,
      poll_interval_ms: 1_000,
      backoff_ms: 2_000,
      max_backoff_ms: 10_000,
      max_attempts: 5,
      on_recovery: fn old_pid, new_pid, checkpoint ->
        send(parent, {:recovered, old_pid, new_pid, checkpoint})
        :ok
      end,
      on_failure: fn run_id, reason ->
        send(parent, {:recovery_failed, run_id, reason})
        :ok
      end
    )
  end

  defp save_checkpoint(training_pid, name) do
    case TrainingClient.save_state(training_pid, name) do
      {:ok, task} ->
        case Task.await(task, @await_timeout) do
          {:ok, %SaveWeightsResponse{path: path}} ->
            IO.puts("Saved checkpoint #{path}")
            {:ok, path}

          {:ok, %{"path" => path}} ->
            IO.puts("Saved checkpoint #{path}")
            {:ok, path}

          {:error, %Error{} = error} ->
            {:error, error}

          other ->
            {:error, {:unexpected_save_response, other}}
        end

      other ->
        other
    end
  end

  defp run_id_from_path(path) do
    case ParsedCheckpointTinkerPath.from_tinker_path(path) do
      {:ok, parsed} -> {:ok, parsed.training_run_id}
      other -> {:error, {:cannot_parse_run_id, path, other}}
    end
  end

  defp await_recovery(timeout_ms \\ 90_000) do
    receive do
      {:recovered, old_pid, new_pid, checkpoint} ->
        IO.puts(
          "Recovery callback: old=#{inspect(old_pid)} new=#{inspect(new_pid)} cp=#{checkpoint.tinker_path}"
        )

        {:ok, new_pid, checkpoint}

      {:recovery_failed, run_id, reason} ->
        {:error, {:recovery_failed, run_id, reason}}
    after
      timeout_ms ->
        {:error, :recovery_timeout}
    end
  end

  defp fetch_env!(key) do
    case System.get_env(key) do
      nil -> raise "Set #{key} to run this example"
      value -> value
    end
  end

  defp cleanup(pids) do
    Enum.each(pids, fn
      pid when is_pid(pid) -> Process.exit(pid, :normal)
      _ -> :ok
    end)
  end
end

Tinkex.Examples.RecoveryLiveInjected.run()
