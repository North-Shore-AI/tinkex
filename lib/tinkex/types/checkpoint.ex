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
    tinker_path = get_field(map, :tinker_path)

    %__MODULE__{
      checkpoint_id: get_field(map, :checkpoint_id),
      checkpoint_type: get_field(map, :checkpoint_type),
      tinker_path: tinker_path,
      training_run_id: get_field(map, :training_run_id) || training_run_from_path(tinker_path),
      size_bytes: get_field(map, :size_bytes),
      public: get_field(map, :public) || false,
      time: parse_time(get_field(map, :time))
    }
  end

  defp get_field(map, key) do
    atom_key = key
    string_key = Atom.to_string(key)
    map[string_key] || map[atom_key]
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
