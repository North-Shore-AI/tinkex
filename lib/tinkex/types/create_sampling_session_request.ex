defmodule Tinkex.Types.CreateSamplingSessionRequest do
  @moduledoc """
  Request to create a new sampling session.

  Mirrors Python tinker.types.CreateSamplingSessionRequest.
  """

  alias Sinter.Schema

  @enforce_keys [:session_id, :sampling_session_seq_id]
  @derive {Jason.Encoder,
           only: [:session_id, :sampling_session_seq_id, :base_model, :model_path, :type]}
  defstruct [
    :session_id,
    :sampling_session_seq_id,
    :base_model,
    :model_path,
    type: "create_sampling_session"
  ]

  @schema Schema.define([
            {:session_id, :string, [required: true]},
            {:sampling_session_seq_id, :integer, [required: true]},
            {:base_model, :string, [optional: true]},
            {:model_path, :string, [optional: true]},
            {:type, :string, [optional: true, default: "create_sampling_session"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          session_id: String.t(),
          sampling_session_seq_id: integer(),
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          type: String.t()
        }
end
