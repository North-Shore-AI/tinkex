defmodule Tinkex.Types.SessionHeartbeatResponse do
  @moduledoc """
  Response to a session heartbeat request.

  Mirrors Python `tinker.types.SessionHeartbeatResponse`.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct type: "session_heartbeat"

  @schema Schema.define([
            {:type, :string, [optional: true, default: "session_heartbeat"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          type: String.t()
        }

  @doc """
  Create a new SessionHeartbeatResponse.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
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
