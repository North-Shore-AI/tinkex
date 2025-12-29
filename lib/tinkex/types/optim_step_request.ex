defmodule Tinkex.Types.OptimStepRequest do
  @moduledoc """
  Request for optimizer step.

  Mirrors Python tinker.types.OptimStepRequest.
  """

  alias Sinter.Schema
  alias Tinkex.Types.AdamParams

  @enforce_keys [:adam_params, :model_id]
  @derive {Jason.Encoder, only: [:adam_params, :model_id, :seq_id]}
  defstruct [:adam_params, :model_id, :seq_id]

  @schema Schema.define([
            {:adam_params, {:object, AdamParams.schema()}, [required: true]},
            {:model_id, :string, [required: true]},
            {:seq_id, :integer, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          adam_params: AdamParams.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
