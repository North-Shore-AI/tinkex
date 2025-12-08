defmodule Tinkex.Types.TryAgainResponse do
  @moduledoc """
  Response indicating queue backpressure - the client should retry polling.

  Mirrors the Python `TryAgainResponse` schema and normalizes queue state into
  atoms via `Tinkex.Types.QueueState`.
  """

  alias Tinkex.Types.QueueState

  @enforce_keys [:type, :request_id, :queue_state]
  defstruct [:type, :request_id, :queue_state, :retry_after_ms, :queue_state_reason]

  @type t :: %__MODULE__{
          type: String.t(),
          request_id: String.t(),
          queue_state: QueueState.t(),
          retry_after_ms: non_neg_integer() | nil,
          queue_state_reason: String.t() | nil
        }

  @doc """
  Build a `%TryAgainResponse{}` map decoded from JSON.

  Expects a map (string or atom keys) containing the `"type"`, `"request_id"`,
  and `"queue_state"` fields. Raises `ArgumentError` when data is malformed or
  missing required keys to keep the union invariant for callers like
  `FutureRetrieveResponse.from_json/1`.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    type = fetch_binary!(map, :type)

    unless String.downcase(type) == "try_again" do
      raise ArgumentError,
            "TryAgainResponse.from_map/1 only accepts type \"try_again\", got: #{inspect(type)}"
    end

    request_id = fetch_binary!(map, :request_id)
    queue_state = fetch_binary!(map, :queue_state)
    queue_state_reason = normalize_optional_string(get_optional(map, :queue_state_reason))
    retry_after_ms = normalize_retry_after(get_optional(map, :retry_after_ms))

    %__MODULE__{
      type: type,
      request_id: request_id,
      queue_state: QueueState.parse(queue_state),
      retry_after_ms: retry_after_ms,
      queue_state_reason: queue_state_reason
    }
  end

  def from_map(other) do
    raise ArgumentError,
          "TryAgainResponse.from_map/1 expects a map, got: #{inspect(other)}"
  end

  defp fetch_binary!(map, key) do
    case get_optional(map, key) do
      value when is_binary(value) ->
        value

      nil ->
        raise ArgumentError, "missing required field #{inspect(key)} in TryAgainResponse map"

      other ->
        raise ArgumentError,
              "expected #{inspect(key)} to be a binary, got: #{inspect(other)}"
    end
  end

  defp get_optional(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(map, key_to_string(key))
    end
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)

  defp normalize_retry_after(nil), do: nil

  defp normalize_retry_after(value) when is_integer(value) and value >= 0 do
    value
  end

  defp normalize_retry_after(value) do
    raise ArgumentError,
          "expected retry_after_ms to be nil or non-negative integer, got: #{inspect(value)}"
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value), do: value

  defp normalize_optional_string(value) do
    raise ArgumentError,
          "expected queue_state_reason to be nil or binary, got: #{inspect(value)}"
  end
end
