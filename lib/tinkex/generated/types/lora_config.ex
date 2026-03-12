defmodule Tinkex.Generated.Types.LoraConfig do
  @moduledoc """
  LoraConfig type.
  """

  defstruct [:rank, :seed, :train_attn, :train_mlp, :train_unembed]

  @type t :: %__MODULE__{
          rank: term() | nil,
          seed: term() | nil,
          train_attn: term() | nil,
          train_mlp: term() | nil,
          train_unembed: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:rank, :any, [optional: true]},
      {:seed, :any, [optional: true]},
      {:train_attn, :any, [optional: true]},
      {:train_mlp, :any, [optional: true]},
      {:train_unembed, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.LoraConfig struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         rank: validated["rank"],
         seed: validated["seed"],
         train_attn: validated["train_attn"],
         train_mlp: validated["train_mlp"],
         train_unembed: validated["train_unembed"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.LoraConfig struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "rank" => struct.rank,
      "seed" => struct.seed,
      "train_attn" => struct.train_attn,
      "train_mlp" => struct.train_mlp,
      "train_unembed" => struct.train_unembed
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.LoraConfig from a map."
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

  @doc "Create a new Tinkex.Generated.Types.LoraConfig."
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
