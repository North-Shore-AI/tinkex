defmodule Tinkex.Types.TelemetryResponse do
  @moduledoc """
  Response to a telemetry send request.

  Mirrors Python `tinker.types.TelemetryResponse`.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct status: "accepted"

  @schema Schema.define([
            {:status, :string, [optional: true, default: "accepted"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type status :: :accepted

  @type t :: %__MODULE__{
          status: String.t()
        }

  @doc """
  Create a new TelemetryResponse.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{status: "accepted"}
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    case SchemaCodec.validate(schema(), json, coerce: true) do
      {:ok, validated} -> SchemaCodec.to_struct(struct(__MODULE__), validated)
      {:error, _} -> new()
    end
  end
end
