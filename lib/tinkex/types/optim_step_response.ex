defmodule Tinkex.Types.OptimStepResponse do
  @moduledoc """
  Response from optimizer step request.

  Mirrors Python tinker.types.OptimStepResponse.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct [:metrics]

  @schema Schema.define([
            {:metrics, {:nullable, :map}, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          metrics: %{String.t() => float()} | nil
        }

  @doc """
  Parse an optim step response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end

  @doc """
  Convenience helper to check if the step succeeded.
  """
  @spec success?(t()) :: boolean()
  def success?(_response), do: true
end
