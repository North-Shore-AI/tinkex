defmodule Tinkex.Types.TrainingRun do
  @moduledoc """
  Training run metadata with last checkpoint details.
  """

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
    %__MODULE__{
      training_run_id: fetch(map, "training_run_id") || fetch(map, "id"),
      base_model: fetch(map, "base_model"),
      model_owner: fetch(map, "model_owner"),
      is_lora: fetch_boolean(map, "is_lora"),
      lora_rank: map["lora_rank"] || map[:lora_rank],
      corrupted: fetch_boolean(map, "corrupted", false),
      last_request_time: parse_datetime(fetch(map, "last_request_time")),
      last_checkpoint: map |> fetch("last_checkpoint") |> maybe_checkpoint(),
      last_sampler_checkpoint: map |> fetch("last_sampler_checkpoint") |> maybe_checkpoint(),
      user_metadata: map["user_metadata"] || map[:user_metadata]
    }
  end

  defp fetch(map, key) do
    map[key] || map[String.to_atom(key)]
  end

  defp fetch_boolean(map, key, default \\ false) do
    case fetch(map, key) do
      nil -> default
      value when is_boolean(value) -> value
      value when is_binary(value) -> String.downcase(value) == "true"
      _ -> default
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

  defp maybe_checkpoint(nil), do: nil
  defp maybe_checkpoint(%Checkpoint{} = checkpoint), do: checkpoint
  defp maybe_checkpoint(map) when is_map(map), do: Checkpoint.from_map(map)
end
