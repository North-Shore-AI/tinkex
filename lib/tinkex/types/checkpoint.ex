defmodule Tinkex.Types.Checkpoint do
  @moduledoc """
  Checkpoint metadata.

  Represents a saved model checkpoint with its metadata. Timestamps are parsed
  into `DateTime.t()` when ISO-8601 formatted; otherwise the original string is
  preserved.
  """

  alias Tinkex.Types.ParsedCheckpointTinkerPath

  @type t :: %__MODULE__{
          checkpoint_id: String.t(),
          checkpoint_type: String.t(),
          tinker_path: String.t(),
          training_run_id: String.t() | nil,
          size_bytes: integer() | nil,
          public: boolean(),
          time: DateTime.t() | String.t() | nil
        }

  defstruct [
    :checkpoint_id,
    :checkpoint_type,
    :tinker_path,
    :training_run_id,
    :size_bytes,
    :public,
    :time
  ]

  @doc """
  Convert a map (from JSON) to a Checkpoint struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      checkpoint_id: map["checkpoint_id"] || map[:checkpoint_id],
      checkpoint_type: map["checkpoint_type"] || map[:checkpoint_type],
      tinker_path: map["tinker_path"] || map[:tinker_path],
      training_run_id:
        map["training_run_id"] || map[:training_run_id] ||
          training_run_from_path(map["tinker_path"] || map[:tinker_path]),
      size_bytes: map["size_bytes"] || map[:size_bytes],
      public: map["public"] || map[:public] || false,
      time: parse_time(map["time"] || map[:time])
    }
  end

  defp parse_time(nil), do: nil
  defp parse_time(%DateTime{} = dt), do: dt

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> value
    end
  end

  defp parse_time(other), do: other

  defp training_run_from_path(path) do
    case ParsedCheckpointTinkerPath.from_tinker_path(path) do
      {:ok, parsed} -> parsed.training_run_id
      _ -> nil
    end
  end
end
