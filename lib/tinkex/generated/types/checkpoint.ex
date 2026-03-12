defmodule Tinkex.Generated.Types.Checkpoint do
  @moduledoc """
  Checkpoint type.
  """

  defstruct [
    :checkpoint_id,
    :checkpoint_type,
    :public,
    :size_bytes,
    :time,
    :tinker_path,
    :training_run_id
  ]

  @type t :: %__MODULE__{
          checkpoint_id: term() | nil,
          checkpoint_type: term() | nil,
          public: term() | nil,
          size_bytes: term() | nil,
          time: term() | nil,
          tinker_path: term() | nil,
          training_run_id: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:checkpoint_id, :any, [optional: true]},
      {:checkpoint_type, :any, [optional: true]},
      {:public, :any, [optional: true]},
      {:size_bytes, :any, [optional: true]},
      {:time, :any, [optional: true]},
      {:tinker_path, :any, [optional: true]},
      {:training_run_id, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.Checkpoint struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         checkpoint_id: validated["checkpoint_id"],
         checkpoint_type: validated["checkpoint_type"],
         public: validated["public"],
         size_bytes: validated["size_bytes"],
         time: validated["time"],
         tinker_path: validated["tinker_path"],
         training_run_id: validated["training_run_id"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.Checkpoint struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "checkpoint_id" => struct.checkpoint_id,
      "checkpoint_type" => struct.checkpoint_type,
      "public" => struct.public,
      "size_bytes" => struct.size_bytes,
      "time" => struct.time,
      "tinker_path" => struct.tinker_path,
      "training_run_id" => struct.training_run_id
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.Checkpoint from a map."
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

  @doc "Create a new Tinkex.Generated.Types.Checkpoint."
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
