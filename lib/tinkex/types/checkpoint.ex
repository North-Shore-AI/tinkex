defmodule Tinkex.Types.Checkpoint do
  @moduledoc """
  Checkpoint metadata.

  Represents a saved model checkpoint with its metadata.
  """

  @type t :: %__MODULE__{
          checkpoint_id: String.t(),
          checkpoint_type: String.t(),
          tinker_path: String.t(),
          training_run_id: String.t() | nil,
          size_bytes: integer() | nil,
          public: boolean(),
          time: String.t()
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
      time: map["time"] || map[:time]
    }
  end

  defp training_run_from_path("tinker://" <> rest) do
    case String.split(rest, "/") do
      [run_id | _] -> run_id
      _ -> nil
    end
  end

  defp training_run_from_path(_), do: nil
end
