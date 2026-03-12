defmodule Tinkex.Generated.Types.SamplingParams do
  @moduledoc """
  SamplingParams type.
  """

  defstruct [:max_tokens, :seed, :stop, :temperature, :top_k, :top_p]

  @type t :: %__MODULE__{
          max_tokens: term() | nil,
          seed: term() | nil,
          stop: term() | nil,
          temperature: term() | nil,
          top_k: term() | nil,
          top_p: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:max_tokens, :any, [optional: true]},
      {:seed, :any, [optional: true]},
      {:stop, :any, [optional: true]},
      {:temperature, :any, [optional: true]},
      {:top_k, :any, [optional: true]},
      {:top_p, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.SamplingParams struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         max_tokens: validated["max_tokens"],
         seed: validated["seed"],
         stop: validated["stop"],
         temperature: validated["temperature"],
         top_k: validated["top_k"],
         top_p: validated["top_p"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.SamplingParams struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "max_tokens" => struct.max_tokens,
      "seed" => struct.seed,
      "stop" => struct.stop,
      "temperature" => struct.temperature,
      "top_k" => struct.top_k,
      "top_p" => struct.top_p
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.SamplingParams from a map."
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

  @doc "Create a new Tinkex.Generated.Types.SamplingParams."
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
