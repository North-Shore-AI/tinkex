defmodule Tinkex.Generated.Types.TryAgainResponse do
  @moduledoc """
  TryAgainResponse type.
  """

  defstruct [:queue_state, :queue_state_reason, :request_id, :retry_after_ms, :type]

  @type t :: %__MODULE__{
          queue_state: term(),
          queue_state_reason: term() | nil,
          request_id: term(),
          retry_after_ms: term() | nil,
          type: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:queue_state, :any, [required: true]},
      {:queue_state_reason, :any, [optional: true]},
      {:request_id, :any, [required: true]},
      {:retry_after_ms, :any, [optional: true]},
      {:type, :any, [required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.TryAgainResponse struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         queue_state: validated["queue_state"],
         queue_state_reason: validated["queue_state_reason"],
         request_id: validated["request_id"],
         retry_after_ms: validated["retry_after_ms"],
         type: validated["type"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.TryAgainResponse struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "queue_state" => struct.queue_state,
      "queue_state_reason" => struct.queue_state_reason,
      "request_id" => struct.request_id,
      "retry_after_ms" => struct.retry_after_ms,
      "type" => struct.type
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.TryAgainResponse from a map."
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data) do
    struct(__MODULE__, atomize_keys(data))
  end

  @doc "Convert to a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.TryAgainResponse."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ [])
  def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
  def new(attrs) when is_map(attrs), do: from_map(attrs)

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
