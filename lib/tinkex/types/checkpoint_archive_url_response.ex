defmodule Tinkex.Types.CheckpointArchiveUrlResponse do
  @moduledoc """
  Response containing a download URL for a checkpoint archive.
  """

  @type t :: %__MODULE__{
          url: String.t(),
          expires: DateTime.t() | String.t() | nil
        }

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct [:url, :expires]

  @schema Schema.define([
            {:url, :string, [required: true]},
            {:expires, :any, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @doc """
  Convert a map (from JSON) to a CheckpointArchiveUrlResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    case SchemaCodec.validate(schema(), map, coerce: true) do
      {:ok, validated} ->
        struct = SchemaCodec.to_struct(struct(__MODULE__), validated)
        %__MODULE__{struct | expires: parse_expires(struct.expires)}

      {:error, errors} ->
        raise ArgumentError, "invalid checkpoint archive url map: #{inspect(errors)}"
    end
  end

  defp parse_expires(nil), do: nil
  defp parse_expires(%DateTime{} = dt), do: dt

  defp parse_expires(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> value
    end
  end

  defp parse_expires(other), do: other
end
