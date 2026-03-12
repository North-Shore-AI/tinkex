defmodule Tinkex.Generated.Types.ParsedCheckpointTinkerPath do
  @moduledoc """
  ParsedCheckpointTinkerPath type.
  """

  defstruct [:checkpoint_id, :checkpoint_type, :tinker_path, :training_run_id]

  @type t :: %__MODULE__{
          checkpoint_id: term(),
          checkpoint_type: term(),
          tinker_path: term(),
          training_run_id: term()
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:checkpoint_id, :any, [required: true]},
      {:checkpoint_type, :any, [required: true]},
      {:tinker_path, :any, [required: true]},
      {:training_run_id, :any, [required: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.ParsedCheckpointTinkerPath struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         checkpoint_id: validated["checkpoint_id"],
         checkpoint_type: validated["checkpoint_type"],
         tinker_path: validated["tinker_path"],
         training_run_id: validated["training_run_id"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.ParsedCheckpointTinkerPath struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "checkpoint_id" => struct.checkpoint_id,
      "checkpoint_type" => struct.checkpoint_type,
      "tinker_path" => struct.tinker_path,
      "training_run_id" => struct.training_run_id
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.ParsedCheckpointTinkerPath from a map."
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

  @doc "Create a new Tinkex.Generated.Types.ParsedCheckpointTinkerPath."
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
