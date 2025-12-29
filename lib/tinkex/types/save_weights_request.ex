defmodule Tinkex.Types.SaveWeightsRequest do
  @moduledoc """
  Request to save model weights as a checkpoint.

  Mirrors Python tinker.types.SaveWeightsRequest.
  """

  alias Sinter.Schema

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :type]}
  defstruct [:model_id, :path, :seq_id, type: "save_weights"]

  @schema Schema.define([
            {:model_id, :string, [required: true]},
            {:path, :string, [optional: true]},
            {:seq_id, :integer, [optional: true]},
            {:type, :string, [optional: true, default: "save_weights"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t() | nil,
          seq_id: integer() | nil,
          type: String.t()
        }
end
