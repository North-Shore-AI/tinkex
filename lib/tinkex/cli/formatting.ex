defmodule Tinkex.CLI.Formatting do
  @moduledoc """
  Output formatting utilities for the CLI (JSON, table, size formatting, datetime).
  """

  alias Tinkex.Types.{Checkpoint, ParsedCheckpointTinkerPath, TrainingRun, WeightsInfoResponse}

  @doc """
  Converts a checkpoint struct or map to a formatted map.
  """
  def checkpoint_to_map(%Checkpoint{} = checkpoint) do
    training_run_id =
      checkpoint.training_run_id ||
        training_run_from_path(checkpoint.tinker_path)

    %{
      "checkpoint_id" => checkpoint.checkpoint_id,
      "checkpoint_type" => checkpoint.checkpoint_type,
      "tinker_path" => checkpoint.tinker_path,
      "training_run_id" => training_run_id,
      "size_bytes" => checkpoint.size_bytes,
      "public" => checkpoint.public,
      "time" => format_datetime(checkpoint.time)
    }
  end

  def checkpoint_to_map(map) when is_map(map) do
    map
    |> Checkpoint.from_map()
    |> checkpoint_to_map()
  end

  @doc """
  Converts weights info to a formatted map.
  """
  def weights_info_to_map(%WeightsInfoResponse{} = info) do
    base = %{
      "base_model" => info.base_model,
      "is_lora" => info.is_lora
    }

    if info.lora_rank do
      Map.put(base, "lora_rank", info.lora_rank)
    else
      base
    end
  end

  @doc """
  Converts a training run struct or map to a formatted map.
  """
  def run_to_map(%TrainingRun{} = run) do
    %{
      "training_run_id" => run.training_run_id,
      "base_model" => run.base_model,
      "model_owner" => run.model_owner,
      "is_lora" => run.is_lora,
      "lora_rank" => run.lora_rank,
      "corrupted" => run.corrupted,
      "last_request_time" => format_datetime(run.last_request_time),
      "last_checkpoint" => maybe_checkpoint_map(run.last_checkpoint),
      "last_sampler_checkpoint" => maybe_checkpoint_map(run.last_sampler_checkpoint),
      "user_metadata" => run.user_metadata
    }
  end

  def run_to_map(map) when is_map(map) do
    map
    |> TrainingRun.from_map()
    |> run_to_map()
  end

  @doc """
  Formats a byte size into a human-readable string (B, KB, MB, GB, TB).
  """
  def format_size(nil), do: "N/A"

  def format_size(bytes) when is_integer(bytes) do
    units = ["B", "KB", "MB", "GB", "TB"]

    {value, unit} =
      Enum.reduce_while(units, {bytes * 1.0, "B"}, fn unit, {val, _} ->
        if abs(val) < 1024 do
          {:halt, {val, unit}}
        else
          {:cont, {val / 1024, unit}}
        end
      end)

    if unit == "B" do
      "#{trunc(value)} #{unit}"
    else
      :erlang.float_to_binary(value, decimals: 1) <> " #{unit}"
    end
  end

  def format_size(other), do: to_string(other || "N/A")

  @doc """
  Formats a datetime value into an ISO 8601 string.
  """
  def format_datetime(nil), do: "N/A"
  def format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  def format_datetime(value) when is_binary(value), do: value
  def format_datetime(other), do: to_string(other)

  @doc """
  Formats LoRA information for display.
  """
  def format_lora(map) do
    is_lora = Map.get(map, "is_lora") || Map.get(map, :is_lora)
    rank = Map.get(map, "lora_rank") || Map.get(map, :lora_rank)

    cond do
      is_lora == true and is_integer(rank) -> "Yes (rank #{rank})"
      is_lora == true -> "Yes"
      true -> "No"
    end
  end

  @doc """
  Formats training run status.
  """
  def format_status(map) do
    corrupted = Map.get(map, "corrupted") || Map.get(map, :corrupted)

    if corrupted, do: "Failed", else: "Active"
  end

  # Private functions

  defp training_run_from_path(path) do
    case ParsedCheckpointTinkerPath.from_tinker_path(path) do
      {:ok, parsed} -> parsed.training_run_id
      _ -> nil
    end
  end

  defp maybe_checkpoint_map(nil), do: nil
  defp maybe_checkpoint_map(%Checkpoint{} = checkpoint), do: checkpoint_to_map(checkpoint)

  defp maybe_checkpoint_map(map) when is_map(map) do
    map
    |> Checkpoint.from_map()
    |> checkpoint_to_map()
  end
end
