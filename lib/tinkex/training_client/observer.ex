defmodule Tinkex.TrainingClient.Observer do
  @moduledoc """
  Queue state observation and logging for TrainingClient.

  This module implements `Tinkex.QueueStateObserver` and automatically logs
  human-readable warnings when queue state changes indicate rate limiting
  or capacity issues.

  Logs are debounced to once per 60 seconds per model to avoid spam.
  """

  @behaviour Tinkex.QueueStateObserver

  alias Tinkex.QueueStateLogger

  @doc """
  Callback invoked when queue state changes (e.g., rate limit hit).

  Uses metadata to identify the model and :persistent_term to track
  debouncing per model.
  """
  @impl Tinkex.QueueStateObserver
  def on_queue_state_change(queue_state, metadata \\ %{}) do
    model_id = metadata[:model_id] || "unknown"

    # Use :persistent_term for debounce tracking keyed by model_id
    debounce_key = {:training_queue_state_debounce, model_id}

    last_logged =
      case :persistent_term.get(debounce_key, nil) do
        nil -> nil
        ts -> ts
      end

    new_timestamp = QueueStateLogger.maybe_log(queue_state, :training, model_id, last_logged)

    # Update the debounce timestamp if it changed
    if new_timestamp != last_logged do
      :persistent_term.put(debounce_key, new_timestamp)
    end

    :ok
  end
end
