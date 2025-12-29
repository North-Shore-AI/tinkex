defmodule Tinkex.Types.GetSessionResponse do
  @moduledoc """
  Response from get_session API.

  Contains the training run IDs and sampler IDs associated with a session.
  """

  @type t :: %__MODULE__{
          training_run_ids: [String.t()],
          sampler_ids: [String.t()]
        }

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  defstruct [:training_run_ids, :sampler_ids]

  @schema Schema.define([
            {:training_run_ids, {:array, :string}, [optional: true, default: []]},
            {:sampler_ids, {:array, :string}, [optional: true, default: []]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @doc """
  Convert a map (from JSON) to a GetSessionResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    SchemaCodec.decode_struct(schema(), map, struct(__MODULE__), coerce: true)
  end
end
