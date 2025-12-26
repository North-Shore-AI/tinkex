defmodule Tinkex.Recovery.Executor do
  @moduledoc """
  GenServer that performs recovery attempts for corrupted training runs.

  Users must start and drive this module explicitly (typically alongside
  `Tinkex.Recovery.Monitor`). Concurrency is capped (default: 1) to avoid
  unbounded restarts; adjust via `:max_concurrent` in `start_link/1`.

  Telemetry events:
    * `[:tinkex, :recovery, :started]` - attempt began (measurements: `%{attempt: n}`)
    * `[:tinkex, :recovery, :checkpoint_selected]` - checkpoint chosen
    * `[:tinkex, :recovery, :client_created]` - training client successfully created
    * `[:tinkex, :recovery, :completed]` - recovery finished successfully
    * `[:tinkex, :recovery, :failed]` - attempt failed (metadata includes `:error`)
    * `[:tinkex, :recovery, :exhausted]` - max attempts reached, no recovery
  """

  use GenServer

  alias Tinkex.Config
  alias Tinkex.Recovery.Policy
  alias Tinkex.Types.{Checkpoint, TrainingRun}

  @type option ::
          {:rest_module, module()}
          | {:service_client_module, module()}
          | {:max_concurrent, pos_integer()}
          | {:send_after, (term(), non_neg_integer() -> reference())}

  @typedoc false
  @type state :: %{
          rest_module: module(),
          service_module: module(),
          max_concurrent: pos_integer(),
          send_after: (term(), non_neg_integer() -> reference()),
          queue: :queue.queue(entry()),
          in_progress: %{optional(String.t()) => entry()},
          pending_retry: %{optional(String.t()) => reference()}
        }

  @typedoc false
  @type entry :: %{
          run_id: String.t(),
          service_pid: pid(),
          policy: Policy.t(),
          config: Config.t() | nil,
          metadata: map(),
          last_checkpoint: Checkpoint.t() | map() | String.t() | nil,
          run: TrainingRun.t() | nil,
          attempt: non_neg_integer(),
          last_error: term()
        }

  @doc """
  Start the executor.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Enqueue a recovery request.

  Options:
    * `:config` - `Tinkex.Config.t()` used for REST lookups when checkpoint is not provided
    * `:metadata` - map propagated to telemetry/callbacks (e.g., `%{training_pid: pid}`)
    * `:last_checkpoint` - `Tinkex.Types.Checkpoint.t()`/map/string path to skip refetch
    * `:run` - `Tinkex.Types.TrainingRun.t()` to reuse an already fetched run
  """
  @spec recover(pid(), String.t(), pid(), Policy.t() | map(), keyword()) ::
          :ok | {:error, term()}
  def recover(executor, run_id, service_pid, policy, opts \\ []) do
    GenServer.call(executor, {:recover, run_id, service_pid, policy, opts})
  end

  @impl true
  def init(opts) do
    rest_module = Keyword.get(opts, :rest_module, Tinkex.API.Rest)
    service_module = Keyword.get(opts, :service_client_module, Tinkex.ServiceClient)

    send_after =
      Keyword.get(opts, :send_after, fn msg, delay -> Process.send_after(self(), msg, delay) end)

    max_concurrent = opts |> Keyword.get(:max_concurrent, 1) |> max(1)

    state = %{
      rest_module: rest_module,
      service_module: service_module,
      max_concurrent: max_concurrent,
      send_after: send_after,
      queue: :queue.new(),
      in_progress: %{},
      pending_retry: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:recover, run_id, service_pid, policy_input, opts}, _from, state) do
    policy = Policy.new(policy_input)

    cond do
      not policy.enabled ->
        {:reply, {:error, :recovery_disabled}, state}

      known_run?(state, run_id) ->
        {:reply, {:error, :already_pending}, state}

      true ->
        entry =
          %{
            run_id: run_id,
            service_pid: service_pid,
            policy: policy,
            config: opts[:config],
            metadata: normalize_metadata(opts[:metadata]),
            last_checkpoint: normalize_checkpoint(opts[:last_checkpoint], run_id),
            run: opts[:run],
            attempt: 0,
            last_error: nil
          }

        queue = :queue.in(entry, state.queue)
        new_state = maybe_start_next(%{state | queue: queue})
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:retry, entry}, state) do
    state = %{state | pending_retry: Map.delete(state.pending_retry, entry.run_id)}

    if known_run?(state, entry.run_id) do
      {:noreply, state}
    else
      queue = :queue.in(entry, state.queue)
      {:noreply, maybe_start_next(%{state | queue: queue})}
    end
  end

  def handle_info({:recovery_result, run_id, attempt, result}, state) do
    case Map.pop(state.in_progress, run_id) do
      {nil, _in_progress} ->
        {:noreply, state}

      {entry, in_progress} ->
        entry = %{entry | attempt: attempt}
        state = %{state | in_progress: in_progress}

        case result do
          {:ok, client_pid, checkpoint} ->
            telemetry(:completed, entry, %{client_pid: client_pid, checkpoint: checkpoint})
            maybe_on_recovery(entry, client_pid, checkpoint)
            {:noreply, maybe_start_next(state)}

          {:error, reason} ->
            telemetry(:failed, entry, %{error: reason})
            handle_failure(entry, reason, state)
        end
    end
  end

  defp handle_failure(entry, reason, state) do
    if entry.attempt >= entry.policy.max_attempts do
      telemetry(:exhausted, entry, %{error: reason})
      maybe_on_failure(entry, reason)
      {:noreply, maybe_start_next(state)}
    else
      delay = backoff_delay(entry.policy, entry.attempt)
      ref = state.send_after.({:retry, entry}, delay)
      pending_retry = Map.put(state.pending_retry, entry.run_id, ref)
      {:noreply, maybe_start_next(%{state | pending_retry: pending_retry})}
    end
  end

  defp maybe_start_next(state) do
    if map_size(state.in_progress) >= state.max_concurrent do
      state
    else
      case :queue.out(state.queue) do
        {{:value, entry}, queue} ->
          start_attempt(entry, %{state | queue: queue})

        {:empty, _queue} ->
          state
      end
    end
  end

  defp start_attempt(entry, state) do
    attempt = entry.attempt + 1
    entry = %{entry | attempt: attempt}

    telemetry(:started, entry, %{})

    executor = self()

    _task =
      Task.start(fn ->
        result =
          try do
            perform_attempt(entry, state)
          rescue
            exception ->
              {:error, {:exception, exception, __STACKTRACE__}}
          catch
            kind, reason ->
              {:error, {kind, reason}}
          end

        send(executor, {:recovery_result, entry.run_id, entry.attempt, result})
      end)

    in_progress = Map.put(state.in_progress, entry.run_id, entry)
    maybe_start_next(%{state | in_progress: in_progress})
  end

  defp perform_attempt(entry, state) do
    with {:ok, checkpoint} <- select_checkpoint(entry, state),
         :ok <- telemetry(:checkpoint_selected, entry, %{checkpoint: checkpoint}),
         {:ok, client_pid} <- create_client(entry, checkpoint, state.service_module) do
      telemetry(:client_created, entry, %{client_pid: client_pid, checkpoint: checkpoint})
      {:ok, client_pid, checkpoint}
    end
  end

  defp select_checkpoint(%{policy: %{checkpoint_strategy: {:specific, path}}} = entry, _state) do
    {:ok, checkpoint_for(path, entry.run_id)}
  end

  defp select_checkpoint(%{policy: %{checkpoint_strategy: :best}} = _entry, _state) do
    {:error, :checkpoint_strategy_not_supported}
  end

  defp select_checkpoint(entry, state) do
    cond do
      entry.last_checkpoint ->
        {:ok, normalize_checkpoint(entry.last_checkpoint, entry.run_id)}

      match?(%TrainingRun{last_checkpoint: _}, entry.run) ->
        case entry.run do
          %TrainingRun{last_checkpoint: nil} ->
            {:error, :missing_checkpoint}

          %TrainingRun{training_run_id: run_id, last_checkpoint: cp} ->
            {:ok, normalize_checkpoint(cp, run_id || entry.run_id)}
        end

      entry.config ->
        fetch_latest_checkpoint(entry, state.rest_module)

      true ->
        {:error, :missing_checkpoint}
    end
  end

  defp fetch_latest_checkpoint(entry, rest_module) do
    case rest_module.get_training_run(entry.config, entry.run_id) do
      {:ok, %TrainingRun{training_run_id: run_id, last_checkpoint: cp}} when not is_nil(cp) ->
        {:ok, normalize_checkpoint(cp, run_id || entry.run_id)}

      {:ok, %TrainingRun{last_checkpoint: nil}} ->
        {:error, :missing_checkpoint}

      {:error, _} = error ->
        error

      other ->
        {:error, {:unexpected_training_run, other}}
    end
  end

  defp create_client(entry, %Checkpoint{tinker_path: path}, service_module) do
    fun =
      if entry.policy.restore_optimizer do
        &service_module.create_training_client_from_state_with_optimizer/3
      else
        &service_module.create_training_client_from_state/3
      end

    fun.(entry.service_pid, path, [])
  end

  defp checkpoint_for(path, run_id) do
    %Checkpoint{
      checkpoint_id: nil,
      checkpoint_type: nil,
      tinker_path: path,
      training_run_id: run_id,
      size_bytes: nil,
      public: false,
      time: nil
    }
  end

  defp normalize_checkpoint(nil, _run_id), do: nil
  defp normalize_checkpoint(%Checkpoint{} = cp, _run_id), do: cp

  defp normalize_checkpoint(%{} = map, run_id) do
    map
    |> Map.put_new(:training_run_id, run_id)
    |> Checkpoint.from_map()
  end

  defp normalize_checkpoint(path, run_id) when is_binary(path) do
    checkpoint_for(path, run_id)
  end

  defp normalize_checkpoint(other, run_id) do
    checkpoint_for(to_string(other), run_id)
  end

  defp telemetry(event, entry, metadata) do
    meta =
      entry.metadata
      |> Map.merge(%{
        run_id: entry.run_id,
        attempt: entry.attempt,
        strategy: entry.policy.checkpoint_strategy
      })
      |> Map.merge(metadata)

    measurements = %{attempt: entry.attempt}
    :telemetry.execute([:tinkex, :recovery, event], measurements, meta)
    :ok
  end

  defp maybe_on_recovery(%{policy: %{on_recovery: nil}}, _client_pid, _checkpoint), do: :ok

  defp maybe_on_recovery(entry, client_pid, checkpoint) do
    old_pid = entry.metadata[:training_pid] || entry.metadata[:old_pid]

    try do
      entry.policy.on_recovery.(old_pid, client_pid, checkpoint)
    catch
      _, _ -> :ok
    end
  end

  defp maybe_on_failure(%{policy: %{on_failure: nil}}, _reason), do: :ok

  defp maybe_on_failure(entry, reason) do
    entry.policy.on_failure.(entry.run_id, reason)
  catch
    _, _ -> :ok
  end

  defp backoff_delay(%Policy{} = policy, attempt) do
    exponent = max(attempt - 1, 0)
    delay = policy.backoff_ms * :math.pow(2, exponent)
    min(trunc(delay), policy.max_backoff_ms)
  end

  defp known_run?(state, run_id) do
    in_queue? =
      state.queue
      |> :queue.to_list()
      |> Enum.any?(fn
        %{run_id: id} -> id == run_id
        _ -> false
      end)

    Map.has_key?(state.in_progress, run_id) || in_queue? ||
      Map.has_key?(state.pending_retry, run_id)
  end

  defp normalize_metadata(nil), do: %{}
  defp normalize_metadata(map) when is_map(map), do: map
  defp normalize_metadata(_other), do: %{}
end
