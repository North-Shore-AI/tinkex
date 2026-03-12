defmodule Tinkex.Generated.Types.TrainingRun do
  @moduledoc """
  TrainingRun type.
  """

  defstruct [
    :base_model,
    :corrupted,
    :is_lora,
    :last_checkpoint,
    :last_request_time,
    :last_sampler_checkpoint,
    :lora_rank,
    :model_owner,
    :training_run_id,
    :user_metadata
  ]

  @type t :: %__MODULE__{
          base_model: term(),
          corrupted: term() | nil,
          is_lora: term(),
          last_checkpoint: term() | nil,
          last_request_time: term(),
          last_sampler_checkpoint: term() | nil,
          lora_rank: term() | nil,
          model_owner: term(),
          training_run_id: term(),
          user_metadata: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:base_model, :any, [required: true]},
      {:corrupted, :any, [optional: true]},
      {:is_lora, :any, [required: true]},
      {:last_checkpoint, :any, [optional: true]},
      {:last_request_time, :any, [required: true]},
      {:last_sampler_checkpoint, :any, [optional: true]},
      {:lora_rank, :any, [optional: true]},
      {:model_owner, :any, [required: true]},
      {:training_run_id, :any, [required: true]},
      {:user_metadata, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.TrainingRun struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         base_model: validated["base_model"],
         corrupted: validated["corrupted"],
         is_lora: validated["is_lora"],
         last_checkpoint: validated["last_checkpoint"],
         last_request_time: validated["last_request_time"],
         last_sampler_checkpoint: validated["last_sampler_checkpoint"],
         lora_rank: validated["lora_rank"],
         model_owner: validated["model_owner"],
         training_run_id: validated["training_run_id"],
         user_metadata: validated["user_metadata"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.TrainingRun struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "base_model" => struct.base_model,
      "corrupted" => struct.corrupted,
      "is_lora" => struct.is_lora,
      "last_checkpoint" => struct.last_checkpoint,
      "last_request_time" => struct.last_request_time,
      "last_sampler_checkpoint" => struct.last_sampler_checkpoint,
      "lora_rank" => struct.lora_rank,
      "model_owner" => struct.model_owner,
      "training_run_id" => struct.training_run_id,
      "user_metadata" => struct.user_metadata
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.TrainingRun from a map."
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

  @doc "Create a new Tinkex.Generated.Types.TrainingRun."
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
