defmodule Tinkex.Types.ForwardBackwardRequest do
  @moduledoc """
  Request for forward-backward pass.

  Mirrors Python tinker.types.ForwardBackwardRequest.
  """

  alias Sinter.Schema
  alias Tinkex.Types.ForwardBackwardInput

  @enforce_keys [:forward_backward_input, :model_id]
  @derive {Jason.Encoder, only: [:forward_backward_input, :model_id, :seq_id]}
  defstruct [:forward_backward_input, :model_id, :seq_id]

  @schema Schema.define([
            {:forward_backward_input, {:object, ForwardBackwardInput.schema()}, [required: true]},
            {:model_id, :string, [required: true]},
            {:seq_id, :integer, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          forward_backward_input: ForwardBackwardInput.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
