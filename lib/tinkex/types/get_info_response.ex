defmodule Tinkex.Types.GetInfoResponse do
  @moduledoc """
  Response payload containing active model metadata.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.ModelData

  @enforce_keys [:model_id, :model_data]
  defstruct [:model_id, :model_data, :is_lora, :lora_rank, :model_name, :type]

  @schema Schema.define([
            {:model_id, :string, [required: true]},
            {:model_data, {:object, ModelData.schema()}, [optional: true, default: %{}]},
            {:is_lora, :boolean, [optional: true]},
            {:lora_rank, :integer, [optional: true]},
            {:model_name, :string, [optional: true]},
            {:type, :string, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          model_id: String.t(),
          model_data: ModelData.t(),
          is_lora: boolean() | nil,
          lora_rank: non_neg_integer() | nil,
          model_name: String.t() | nil,
          type: String.t() | nil
        }

  @doc """
  Parse from a JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__),
      coerce: true,
      converters: %{model_data: ModelData}
    )
  end
end
