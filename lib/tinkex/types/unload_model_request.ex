defmodule Tinkex.Types.UnloadModelRequest do
  @moduledoc """
  Request payload to unload model weights and end the session.
  """

  alias Sinter.Schema

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :type]}
  defstruct [:model_id, type: "unload_model"]

  @schema Schema.define([
            {:model_id, :string, [required: true]},
            {:type, :string, [optional: true, default: "unload_model"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          model_id: String.t(),
          type: String.t()
        }

  @doc """
  Convenience constructor.
  """
  @spec new(String.t()) :: t()
  def new(model_id) when is_binary(model_id) do
    %__MODULE__{model_id: model_id}
  end
end
