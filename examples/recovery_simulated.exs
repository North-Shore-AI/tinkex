alias Tinkex.Recovery.{Executor, Monitor, Policy}
alias Tinkex.Types.Checkpoint

defmodule Examples.RecoveryState do
  @moduledoc false

  alias Tinkex.Types.{Checkpoint, TrainingRun}

  def start_link(run_id, [first | rest]) do
    Agent.start_link(fn ->
      %{
        run_id: run_id,
        corrupted: false,
        last_checkpoint: first,
        remaining: rest,
        completed: [first],
        clients: [],
        last_restore: nil
      }
    end)
  end

  def training_run(agent) do
    Agent.get(agent, fn state ->
      %TrainingRun{
        training_run_id: state.run_id,
        base_model: "demo-base",
        model_owner: "demo-user",
        is_lora: true,
        lora_rank: 8,
        corrupted: state.corrupted,
        last_request_time: DateTime.utc_now(),
        last_checkpoint: state.last_checkpoint,
        last_sampler_checkpoint: nil,
        user_metadata: %{}
      }
    end)
  end

  def mark_corrupted(agent) do
    Agent.update(agent, &%{&1 | corrupted: true})
  end

  def finish_recovery(agent, client_pid, checkpoint_path, mode) do
    Agent.get_and_update(agent, fn state ->
      expected = state.last_checkpoint.tinker_path

      if checkpoint_path != expected do
        IO.puts("Warning: recovery requested #{checkpoint_path}, expected #{expected}")
      end

      {next_cp, rest} = next_checkpoint(state)

      new_state = %{
        state
        | corrupted: false,
          last_checkpoint: next_cp,
          remaining: rest,
          completed: Enum.uniq([next_cp | state.completed]),
          clients: [client_pid | state.clients],
          last_restore: mode
      }

      {{next_cp, mode}, new_state}
    end)
  end

  def completed_paths(agent) do
    Agent.get(agent, fn state ->
      state.completed
      |> Enum.map(& &1.tinker_path)
      |> Enum.uniq()
      |> Enum.reverse()
    end)
  end

  def status(agent) do
    Agent.get(agent, fn state ->
      %{
        corrupted?: state.corrupted,
        last_checkpoint: state.last_checkpoint.tinker_path,
        completed: Enum.reverse(state.completed),
        clients: state.clients
      }
    end)
  end

  def stop(agent) do
    Agent.stop(agent, :normal, 500)
  end

  defp next_checkpoint(%{remaining: [cp | rest]}) do
    {cp, rest}
  end

  defp next_checkpoint(%{last_checkpoint: cp} = state) do
    {cp, state.remaining}
  end
end

defmodule Examples.RecoveryRestStub do
  @moduledoc false

  alias Examples.RecoveryState

  def get_training_run(%Tinkex.Config{user_metadata: %{state: agent}}, _run_id) do
    {:ok, RecoveryState.training_run(agent)}
  end

  def get_training_run(_config, _run_id), do: {:error, :missing_state}
end

defmodule Examples.RecoveryServiceStub do
  @moduledoc false

  alias Examples.RecoveryState

  def create_training_client_from_state_with_optimizer(agent, path, _opts) do
    create(agent, path, :with_optimizer)
  end

  def create_training_client_from_state(agent, path, _opts) do
    create(agent, path, :weights_only)
  end

  defp create(agent, path, mode) do
    {:ok, pid} = Task.start(fn -> :ok end)
    {_checkpoint, _mode} = RecoveryState.finish_recovery(agent, pid, path, mode)
    {:ok, pid}
  end
end

defmodule Examples.RecoverySimulated do
  @moduledoc """
  Offline, end-to-end recovery demo.

  Steps:
    1. Seed a checkpoint for a healthy run.
    2. Flip the run to `corrupted: true` to simulate a backend failure.
    3. `Monitor` detects corruption and hands off to `Executor`.
    4. Service stub "restores" the run and advances to the next checkpoint.
    5. The script confirms both checkpoints were recorded.
  """

  alias Examples.{RecoveryRestStub, RecoveryServiceStub, RecoveryState}

  def main do
    run_id = "demo-run-#{System.unique_integer([:positive])}"

    checkpoints = [
      checkpoint(run_id, "0001"),
      checkpoint(run_id, "0002")
    ]

    {:ok, state} = RecoveryState.start_link(run_id, checkpoints)

    policy =
      Policy.new(
        enabled: true,
        checkpoint_strategy: :latest,
        poll_interval_ms: 150,
        backoff_ms: 100,
        max_backoff_ms: 400,
        max_attempts: 3,
        restore_optimizer: true
      )

    config =
      Tinkex.Config.new(
        api_key: "demo-api-key",
        base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod",
        recovery: policy,
        user_metadata: %{state: state}
      )

    handler_id = attach_telemetry(self())

    {:ok, executor} =
      Executor.start_link(
        max_concurrent: 1,
        service_client_module: RecoveryServiceStub
      )

    {:ok, monitor} =
      Monitor.start_link(
        policy: config.recovery,
        executor: executor,
        rest_module: RecoveryRestStub,
        rest_client_fun: fn _ -> {:ok, %{config: config}} end
      )

    first = hd(checkpoints)
    IO.puts("1) Seeded checkpoint #{first.tinker_path}")

    :ok = RecoveryState.mark_corrupted(state)
    IO.puts("2) Simulated corruption flag on #{run_id}")

    :ok = Monitor.monitor_run(monitor, run_id, state, %{training_pid: :original})

    metadata = await_completion()

    IO.puts(
      "3) Recovery succeeded from #{metadata[:checkpoint].tinker_path} -> #{inspect(metadata[:client_pid])}"
    )

    completed_paths = RecoveryState.completed_paths(state)
    IO.puts("4) Checkpoints processed: #{Enum.join(completed_paths, ", ")}")

    IO.inspect(RecoveryState.status(state), label: "Final run status")

    cleanup(handler_id, monitor, executor, state)
  end

  defp checkpoint(run_id, suffix) do
    Checkpoint.from_map(%{
      checkpoint_id: "cp-#{suffix}",
      checkpoint_type: "weights",
      tinker_path: "tinker://#{run_id}/weights/#{suffix}",
      training_run_id: run_id,
      time: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp attach_telemetry(parent) do
    id = "recovery-demo-#{System.unique_integer([:positive])}"

    events = [
      [:tinkex, :recovery, :detected],
      [:tinkex, :recovery, :started],
      [:tinkex, :recovery, :checkpoint_selected],
      [:tinkex, :recovery, :client_created],
      [:tinkex, :recovery, :completed],
      [:tinkex, :recovery, :failed],
      [:tinkex, :recovery, :exhausted]
    ]

    :ok =
      :telemetry.attach_many(
        id,
        events,
        fn event, measurements, metadata, _ ->
          send(parent, {:recovery_telemetry, event, measurements, metadata})
        end,
        nil
      )

    id
  end

  defp await_completion(timeout_ms \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_until(deadline)
  end

  defp wait_until(deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:recovery_telemetry, [:tinkex, :recovery, :completed], _meas, meta} ->
        meta

      {:recovery_telemetry, [:tinkex, :recovery, :exhausted], _meas, meta} ->
        raise "Recovery exhausted: #{inspect(meta)}"

      _other ->
        wait_until(deadline)
    after
      remaining ->
        raise "Timed out waiting for recovery to complete"
    end
  end

  defp cleanup(handler_id, monitor, executor, state) do
    :telemetry.detach(handler_id)
    GenServer.stop(monitor)
    GenServer.stop(executor)
    RecoveryState.stop(state)
  end
end

Examples.RecoverySimulated.main()
