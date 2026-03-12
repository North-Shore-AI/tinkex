defmodule Tinkex.Generated.Types.RegularizerOutput do
  @moduledoc """
  RegularizerOutput type.
  """

  defstruct [:contribution, :custom, :grad_norm, :grad_norm_weighted, :name, :value, :weight]

  @type t :: %__MODULE__{
          contribution: term(),
          custom: term() | nil,
          grad_norm: term() | nil,
          grad_norm_weighted: term() | nil,
          name: term(),
          value: term(),
          weight: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:contribution, :any, [required: true]},
      {:custom, :any, [optional: true]},
      {:grad_norm, :any, [optional: true]},
      {:grad_norm_weighted, :any, [optional: true]},
      {:name, :any, [required: true]},
      {:value, :any, [required: true]},
      {:weight, :any, [required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.RegularizerOutput struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         contribution: validated["contribution"],
         custom: validated["custom"],
         grad_norm: validated["grad_norm"],
         grad_norm_weighted: validated["grad_norm_weighted"],
         name: validated["name"],
         value: validated["value"],
         weight: validated["weight"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.RegularizerOutput struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "contribution" => struct.contribution,
      "custom" => struct.custom,
      "grad_norm" => struct.grad_norm,
      "grad_norm_weighted" => struct.grad_norm_weighted,
      "name" => struct.name,
      "value" => struct.value,
      "weight" => struct.weight
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.RegularizerOutput from a map."
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

  @doc "Create a new Tinkex.Generated.Types.RegularizerOutput."
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
