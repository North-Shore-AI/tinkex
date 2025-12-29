defmodule Tinkex.Types.ForwardRequest do
  @moduledoc """
  Request for forward-only pass (inference without backward).

  Uses `forward_input` field as expected by the `/api/v1/forward` endpoint.
  """

  alias Sinter.Schema
  alias Tinkex.Types.ForwardBackwardInput

  @enforce_keys [:forward_input, :model_id]
  @derive {Jason.Encoder, only: [:forward_input, :model_id, :seq_id]}
  defstruct [:forward_input, :model_id, :seq_id]

  @schema Schema.define([
            {:forward_input, {:object, ForwardBackwardInput.schema()}, [required: true]},
            {:model_id, :string, [required: true]},
            {:seq_id, :integer, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          forward_input: ForwardBackwardInput.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
