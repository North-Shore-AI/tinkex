defmodule Tinkex.Generated.Types.AdamParams do
  @moduledoc """
  AdamParams type.
  """

  defstruct [:beta1, :beta2, :eps, :grad_clip_norm, :learning_rate, :weight_decay]

  @type t :: %__MODULE__{
          beta1: term() | nil,
          beta2: term() | nil,
          eps: term() | nil,
          grad_clip_norm: term() | nil,
          learning_rate: term() | nil,
          weight_decay: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:beta1, :any, [optional: true]},
      {:beta2, :any, [optional: true]},
      {:eps, :any, [optional: true]},
      {:grad_clip_norm, :any, [optional: true]},
      {:learning_rate, :any, [optional: true]},
      {:weight_decay, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.AdamParams struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         beta1: validated["beta1"],
         beta2: validated["beta2"],
         eps: validated["eps"],
         grad_clip_norm: validated["grad_clip_norm"],
         learning_rate: validated["learning_rate"],
         weight_decay: validated["weight_decay"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.AdamParams struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "beta1" => struct.beta1,
      "beta2" => struct.beta2,
      "eps" => struct.eps,
      "grad_clip_norm" => struct.grad_clip_norm,
      "learning_rate" => struct.learning_rate,
      "weight_decay" => struct.weight_decay
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.AdamParams from a map."
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

  @doc "Create a new Tinkex.Generated.Types.AdamParams."
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
