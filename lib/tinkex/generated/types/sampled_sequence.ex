defmodule Tinkex.Generated.Types.SampledSequence do
  @moduledoc """
  SampledSequence type.
  """

  defstruct [:logprobs, :stop_reason, :tokens]

  @type t :: %__MODULE__{
          logprobs: term() | nil,
          stop_reason: term() | nil,
          tokens: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:logprobs, :any, [optional: true]},
      {:stop_reason, :any, [optional: true]},
      {:tokens, :any, [required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.SampledSequence struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         logprobs: validated["logprobs"],
         stop_reason: validated["stop_reason"],
         tokens: validated["tokens"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.SampledSequence struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "logprobs" => struct.logprobs,
      "stop_reason" => struct.stop_reason,
      "tokens" => struct.tokens
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.SampledSequence from a map."
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

  @doc "Create a new Tinkex.Generated.Types.SampledSequence."
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
