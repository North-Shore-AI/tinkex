defmodule Tinkex.Recovery.Monitor do
  @moduledoc """
  Polls training runs for corruption flags and dispatches recovery work.

  This GenServer must be started explicitly and configured with a recovery
  policy (disabled by default), a REST module for polling, and an executor pid.

  Telemetry events:
    * `[:tinkex, :recovery, :detected]` - observed `corrupted: true` on a run
    * `[:tinkex, :recovery, :poll_error]` - REST poll failed (metadata includes `:error`)
  """

  use GenServer

  require Logger

  alias Tinkex.Config
  alias Tinkex.Recovery.{Executor, Policy}
  alias Tinkex.Types.TrainingRun

  @type option ::
          {:policy, Policy.t() | map() | nil}
          | {:config, Config.t()}
          | {:rest_module, module()}
          | {:rest_client_fun, (pid() -> {:ok, %{config: Config.t()}} | {:error, term()})}
          | {:service_client_module, module()}
          | {:executor, pid()}
          | {:send_after, (term(), non_neg_integer() -> reference())}

  @type state :: %{
          policy: Policy.t(),
          rest_module: module(),
          rest_client_fun: (pid() -> {:ok, %{config: Config.t()}} | {:error, term()}),
          service_module: module(),
          executor: pid() | nil,
          runs: %{
            optional(String.t()) => %{service_pid: pid(), config: Config.t(), metadata: map()}
          },
          poll_ref: reference() | nil,
          send_after: (term(), non_neg_integer() -> reference())
        }

  @doc """
  Start the monitor.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Begin monitoring a training run.

  `service_pid` is the `Tinkex.ServiceClient` pid used to create recovery clients.
  """
  @spec monitor_run(pid(), String.t(), pid(), map()) :: :ok | {:error, term()}
  def monitor_run(monitor, run_id, service_pid, metadata \\ %{}) do
    GenServer.call(monitor, {:monitor, run_id, service_pid, metadata})
  end

  @doc """
  Stop monitoring a training run.
  """
  @spec stop_monitoring(pid(), String.t()) :: :ok
  def stop_monitoring(monitor, run_id) do
    GenServer.call(monitor, {:stop_monitoring, run_id})
  end

  @impl true
  def init(opts) do
    policy = opts |> build_policy() |> Policy.new()
    rest_module = Keyword.get(opts, :rest_module, Tinkex.API.Rest)
    service_module = Keyword.get(opts, :service_client_module, Tinkex.ServiceClient)

    rest_client_fun =
      Keyword.get(opts, :rest_client_fun, fn pid ->
        default_rest_client_fun(pid, service_module)
      end)

    send_after =
      Keyword.get(opts, :send_after, fn msg, delay -> Process.send_after(self(), msg, delay) end)

    state = %{
      policy: policy,
      rest_module: rest_module,
      rest_client_fun: rest_client_fun,
      service_module: service_module,
      executor: Keyword.get(opts, :executor),
      runs: %{},
      poll_ref: nil,
      send_after: send_after
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:monitor, _run_id, _service_pid, _metadata},
        _from,
        %{policy: %{enabled: false}} = state
      ) do
    {:reply, {:error, :recovery_disabled}, state}
  end

  def handle_call({:monitor, _run_id, _service_pid, _metadata}, _from, %{executor: nil} = state) do
    {:reply, {:error, :no_executor}, state}
  end

  def handle_call({:monitor, run_id, service_pid, metadata}, _from, state) do
    case state.rest_client_fun.(service_pid) do
      {:ok, %{config: config}} ->
        entry = %{
          service_pid: service_pid,
          config: config,
          metadata: normalize_metadata(metadata)
        }

        runs = Map.put(state.runs, run_id, entry)

        new_state =
          state
          |> Map.put(:runs, runs)
          |> schedule_poll()

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stop_monitoring, run_id}, _from, state) do
    {:reply, :ok, %{state | runs: Map.delete(state.runs, run_id)}}
  end

  @impl true
  def handle_info(:poll, state) do
    state = %{state | poll_ref: nil}

    new_state =
      state
      |> do_poll()
      |> schedule_poll()

    {:noreply, new_state}
  end

  defp do_poll(%{policy: %{enabled: false}} = state), do: state
  defp do_poll(%{runs: runs} = state) when map_size(runs) == 0, do: state

  defp do_poll(state) do
    Enum.reduce(state.runs, state, fn {run_id, entry}, acc ->
      case state.rest_module.get_training_run(entry.config, run_id) do
        {:ok, %TrainingRun{} = run} ->
          handle_training_run(acc, run_id, run, entry)

        {:error, reason} ->
          Logger.debug("Recovery poll failed for #{run_id}: #{inspect(reason)}")
          telemetry(:poll_error, run_id, %{error: reason}, entry.metadata)
          acc
      end
    end)
  end

  defp handle_training_run(state, run_id, %TrainingRun{corrupted: true} = run, entry) do
    telemetry(:detected, run_id, %{checkpoint: run.last_checkpoint}, entry.metadata)
    dispatch_recovery(state, run_id, run, entry)
  end

  defp handle_training_run(state, _run_id, _run, _entry), do: state

  defp dispatch_recovery(%{executor: executor} = state, run_id, run, entry) do
    opts = [
      config: entry.config,
      metadata: entry.metadata,
      last_checkpoint: run.last_checkpoint,
      run: run
    ]

    case Executor.recover(executor, run_id, entry.service_pid, state.policy, opts) do
      :ok ->
        %{state | runs: Map.delete(state.runs, run_id)}

      {:error, reason} ->
        Logger.debug("Failed to enqueue recovery for #{run_id}: #{inspect(reason)}")
        state
    end
  end

  defp schedule_poll(%{policy: %{enabled: false}} = state), do: state

  defp schedule_poll(%{runs: runs} = state) when map_size(runs) == 0 do
    state
  end

  defp schedule_poll(%{poll_ref: nil} = state) do
    ref = state.send_after.(:poll, state.policy.poll_interval_ms)
    %{state | poll_ref: ref}
  end

  defp schedule_poll(state), do: state

  defp build_policy(opts) do
    cond do
      Keyword.has_key?(opts, :policy) ->
        opts[:policy]

      match?(%Config{recovery: _}, opts[:config]) ->
        opts[:config].recovery

      true ->
        nil
    end
  end

  defp default_rest_client_fun(service_pid, service_module) do
    with {:ok, rest_client} <- service_module.create_rest_client(service_pid) do
      {:ok, %{config: rest_client.config}}
    end
  end

  defp telemetry(event, run_id, metadata, extra) do
    meta =
      extra
      |> Map.merge(%{run_id: run_id})
      |> Map.merge(metadata)

    :telemetry.execute([:tinkex, :recovery, event], %{}, meta)
  end

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(map) when is_map(map), do: map
  defp normalize_metadata(_other), do: %{}
end
