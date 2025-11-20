defmodule Tinkex.Future do
  @moduledoc """
  Client-side future abstraction responsible for polling server-side futures.

  All public APIs return `Task.t({:ok, result} | {:error, reason})` so callers
  can decide whether to block (`Task.await/2`) or compose asynchronous work.

  ## Queue state telemetry

  The polling loop emits `[:tinkex, :queue, :state_change]` events whenever the
  queue state transitions (e.g., `:active` -> `:paused_rate_limit`). Telemetry
  metadata always includes `%{queue_state: atom}` so observers can react:

      :telemetry.attach(
        "tinkex-queue-state-logger",
        [:tinkex, :queue, :state_change],
        fn _event, _measurements, %{queue_state: state}, _config ->
          Logger.info("Queue state changed: \#{state}")
        end,
        nil
      )

  Future phases will introduce a `Tinkex.QueueStateObserver` behaviour so
  clients like `TrainingClient` and `SamplingClient` can implement
  `c:on_queue_state_change/1` and receive these transitions directly. The
  `Tinkex.Future` module itself does **not** implement that behaviour—it only
  emits telemetry.
  """

  alias Tinkex.Config
  alias Tinkex.Error
  alias Tinkex.Types.QueueState

  @queue_state_event [:tinkex, :queue, :state_change]
  @type poll_result :: {:ok, term()} | {:error, Error.t() | term()}
  @type poll_task :: Task.t()

  defmodule State do
    @moduledoc false
    @enforce_keys [:request_id]
    defstruct request_id: nil,
              prev_queue_state: nil,
              config: nil,
              metadata: %{}

    @type t :: %__MODULE__{
            request_id: String.t(),
            prev_queue_state: QueueState.t() | nil,
            config: Config.t() | nil,
            metadata: map()
          }
  end

  @doc """
  Begin polling a future request.

  Returns a Task so callers can `Task.await/2` or monitor the work. Polling is
  not implemented yet; the Task currently returns `{:error, :not_implemented}`
  as a placeholder for upcoming phases.

  The Task's result uses the `poll_result/0` type (`{:ok, result}` tuples or
  `{:error, Tinkex.Error.t() | term()}`).
  """
  @spec poll(String.t(), keyword()) :: poll_task()
  def poll(request_id, opts \\ []) when is_binary(request_id) do
    state =
      %State{
        request_id: request_id,
        prev_queue_state: opts[:initial_queue_state],
        config: opts[:config],
        metadata: Map.new(opts[:telemetry_metadata] || %{})
      }

    telemetry_opts = [telemetry_metadata: state.metadata]

    _ =
      maybe_emit_queue_state_change(
        state.prev_queue_state,
        state.prev_queue_state,
        telemetry_opts
      )

    Task.async(fn -> {:error, :not_implemented} end)
  end

  defp maybe_emit_queue_state_change(prev_state, new_state, opts) do
    cond do
      not valid_queue_state?(new_state) ->
        new_state

      prev_state == new_state ->
        new_state

      true ->
        metadata =
          opts
          |> Keyword.get(:telemetry_metadata, %{})
          |> Map.put(:queue_state, new_state)

        :telemetry.execute(@queue_state_event, %{}, metadata)
        new_state
    end
  end

  defp valid_queue_state?(state) when is_atom(state) do
    state in [:active, :paused_rate_limit, :paused_capacity, :unknown]
  end

  defp valid_queue_state?(_), do: false
end
