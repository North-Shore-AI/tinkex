defmodule Tinkex.Types.SaveWeightsForSamplerRequest do
  @moduledoc """
  Request to save model weights for use in sampling.

  Mirrors Python tinker.types.SaveWeightsForSamplerRequest.
  """

  alias Sinter.Schema

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :path, :sampling_session_seq_id, :seq_id, :type]}
  defstruct [
    :model_id,
    :path,
    :sampling_session_seq_id,
    :seq_id,
    type: "save_weights_for_sampler"
  ]

  @schema Schema.define([
            {:model_id, :string, [required: true]},
            {:path, :string, [optional: true]},
            {:sampling_session_seq_id, :integer, [optional: true]},
            {:seq_id, :integer, [optional: true]},
            {:type, :string, [optional: true, default: "save_weights_for_sampler"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t() | nil,
          sampling_session_seq_id: integer() | nil,
          seq_id: integer() | nil,
          type: String.t()
        }
end
