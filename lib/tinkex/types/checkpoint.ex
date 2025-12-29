defmodule Tinkex.Types.Checkpoint do
  @moduledoc """
  Checkpoint metadata.

  Represents a saved model checkpoint with its metadata. Timestamps are parsed
  into `DateTime.t()` when ISO-8601 formatted; otherwise the original string is
  preserved.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
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

  @schema Schema.define([
            {:checkpoint_id, :string, [required: true]},
            {:checkpoint_type, :string, [required: true]},
            {:tinker_path, :string, [required: true]},
            {:training_run_id, :string, [optional: true]},
            {:size_bytes, {:nullable, :integer}, [optional: true]},
            {:public, {:nullable, :boolean}, [optional: true, default: false]},
            {:time, :any, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @doc """
  Convert a map (from JSON) to a Checkpoint struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    case SchemaCodec.validate(schema(), map, coerce: true) do
      {:ok, validated} ->
        struct = SchemaCodec.to_struct(struct(__MODULE__), validated)
        tinker_path = struct.tinker_path

        %__MODULE__{
          struct
          | training_run_id: struct.training_run_id || training_run_from_path(tinker_path),
            public: if(is_nil(struct.public), do: false, else: struct.public),
            time: parse_time(struct.time)
        }

      {:error, errors} ->
        raise ArgumentError, "invalid checkpoint map: #{inspect(errors)}"
    end
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
