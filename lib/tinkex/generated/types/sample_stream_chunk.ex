defmodule Tinkex.Generated.Types.SampleStreamChunk do
  @moduledoc """
  SampleStreamChunk type.
  """

  defstruct [:event_type, :finish_reason, :index, :logprob, :token, :token_id, :total_tokens]

  @type t :: %__MODULE__{
          event_type: term() | nil,
          finish_reason: term() | nil,
          index: term() | nil,
          logprob: term() | nil,
          token: term() | nil,
          token_id: term() | nil,
          total_tokens: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:event_type, :any, [optional: true]},
      {:finish_reason, :any, [optional: true]},
      {:index, :any, [optional: true]},
      {:logprob, :any, [optional: true]},
      {:token, :any, [optional: true]},
      {:token_id, :any, [optional: true]},
      {:total_tokens, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.SampleStreamChunk struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         event_type: validated["event_type"],
         finish_reason: validated["finish_reason"],
         index: validated["index"],
         logprob: validated["logprob"],
         token: validated["token"],
         token_id: validated["token_id"],
         total_tokens: validated["total_tokens"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.SampleStreamChunk struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "event_type" => struct.event_type,
      "finish_reason" => struct.finish_reason,
      "index" => struct.index,
      "logprob" => struct.logprob,
      "token" => struct.token,
      "token_id" => struct.token_id,
      "total_tokens" => struct.total_tokens
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.SampleStreamChunk from a map."
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

  @doc "Create a new Tinkex.Generated.Types.SampleStreamChunk."
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
