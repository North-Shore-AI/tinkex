defmodule Tinkex.Types.TryAgainResponse do
  @moduledoc """
  Response indicating queue backpressure - the client should retry polling.

  Mirrors the Python `TryAgainResponse` schema and normalizes queue state into
  atoms via `Tinkex.Types.QueueState`.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.QueueState

  @enforce_keys [:type, :request_id, :queue_state]
  defstruct [:type, :request_id, :queue_state, :retry_after_ms, :queue_state_reason]

  @schema Schema.define([
            {:type, :string, [required: true]},
            {:request_id, :string, [required: true]},
            {:queue_state, :string, [required: true]},
            {:retry_after_ms, {:nullable, :integer}, [optional: true, gteq: 0]},
            {:queue_state_reason, {:nullable, :string}, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

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
    type = fetch_type(map)
    validate_type!(type)
    validate_queue_state_reason!(map)

    case SchemaCodec.validate(schema(), map, coerce: true) do
      {:ok, validated} ->
        struct =
          SchemaCodec.to_struct(struct(__MODULE__), validated,
            converters: %{queue_state: &QueueState.parse/1}
          )

        %__MODULE__{struct | type: type}

      {:error, errors} ->
        raise ArgumentError, "invalid TryAgainResponse map: #{inspect(errors)}"
    end
  end

  def from_map(other) do
    raise ArgumentError,
          "TryAgainResponse.from_map/1 expects a map, got: #{inspect(other)}"
  end

  defp fetch_type(map) do
    Map.get(map, "type") || Map.get(map, :type)
  end

  defp validate_type!(type) when is_binary(type) do
    if String.downcase(type) == "try_again" do
      :ok
    else
      raise ArgumentError, "TryAgainResponse.type must be \"try_again\", got: #{inspect(type)}"
    end
  end

  defp validate_type!(other) do
    raise ArgumentError, "TryAgainResponse.type must be a string, got: #{inspect(other)}"
  end

  defp validate_queue_state_reason!(map) do
    reason = Map.get(map, "queue_state_reason") || Map.get(map, :queue_state_reason)

    if not is_nil(reason) and not is_binary(reason) do
      raise ArgumentError,
            "TryAgainResponse.queue_state_reason must be a string, got: #{inspect(reason)}"
    end
  end
end
