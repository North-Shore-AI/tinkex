defmodule Tinkex.Types.TrainingRun do
  @moduledoc """
  Training run metadata with last checkpoint details.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.Checkpoint

  @enforce_keys [:training_run_id, :base_model, :model_owner, :is_lora, :last_request_time]
  defstruct [
    :training_run_id,
    :base_model,
    :model_owner,
    :is_lora,
    :lora_rank,
    :corrupted,
    :last_request_time,
    :last_checkpoint,
    :last_sampler_checkpoint,
    :user_metadata
  ]

  @schema Schema.define([
            {:training_run_id, :string, [required: true]},
            {:base_model, :string, [required: true]},
            {:model_owner, :string, [required: true]},
            {:is_lora, :boolean, [optional: true, default: false]},
            {:lora_rank, {:nullable, :integer}, [optional: true]},
            {:corrupted, :boolean, [optional: true, default: false]},
            {:last_request_time, :any, [optional: true]},
            {:last_checkpoint, {:nullable, {:object, Checkpoint.schema()}}, [optional: true]},
            {:last_sampler_checkpoint, {:nullable, {:object, Checkpoint.schema()}},
             [optional: true]},
            {:user_metadata, {:nullable, :map}, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          training_run_id: String.t(),
          base_model: String.t(),
          model_owner: String.t(),
          is_lora: boolean(),
          lora_rank: integer() | nil,
          corrupted: boolean(),
          last_request_time: DateTime.t() | String.t(),
          last_checkpoint: Checkpoint.t() | nil,
          last_sampler_checkpoint: Checkpoint.t() | nil,
          user_metadata: map() | nil
        }

  @doc """
  Parse a training run from a JSON map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    map = normalize_training_run_id(map)

    case SchemaCodec.validate(schema(), map, coerce: true) do
      {:ok, validated} ->
        struct =
          SchemaCodec.to_struct(struct(__MODULE__), validated,
            converters: %{
              last_checkpoint: Checkpoint,
              last_sampler_checkpoint: Checkpoint
            }
          )

        %__MODULE__{struct | last_request_time: parse_datetime(struct.last_request_time)}

      {:error, errors} ->
        raise ArgumentError, "invalid training run map: #{inspect(errors)}"
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> value
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(other), do: other

  defp normalize_training_run_id(map) do
    training_run_id =
      Map.get(map, "training_run_id") || Map.get(map, :training_run_id) ||
        Map.get(map, "id") || Map.get(map, :id)

    if training_run_id do
      Map.put_new(map, "training_run_id", training_run_id)
    else
      map
    end
  end
end
