defmodule Tinkex.QueueStateObserver do
  @moduledoc """
  Behaviour for modules that want to react to queue-state transitions.

  `Tinkex.Future.poll/2` emits telemetry for queue-state changes and, when given
  a `queue_state_observer`, will invoke the callback below. Training and
  Sampling clients can implement this behaviour to update local backpressure
  tracking whenever the server sends a `TryAgainResponse`.

  ## Example

      defmodule MyObserver do
        @behaviour Tinkex.QueueStateObserver

        @impl true
        def on_queue_state_change(queue_state) do
          Logger.metadata(queue_state: queue_state)
          :ok
        end
      end

  The observer is passed to `Tinkex.Future.poll/2` via the
  `:queue_state_observer` option and will receive callbacks on every state
  transition alongside the telemetry events under
  `[:tinkex, :queue, :state_change]`.

  ## Callback Signatures

  Implement either of the callbacks below. The 2-arity version receives a
  metadata map (request_id, queue_state_reason, etc.) for richer context while
  the 1-arity version is kept for backwards compatibility.
  """

  alias Tinkex.Types.QueueState

  @callback on_queue_state_change(QueueState.t()) :: any()
  @callback on_queue_state_change(QueueState.t(), map()) :: any()

  @optional_callbacks on_queue_state_change: 1, on_queue_state_change: 2
end
