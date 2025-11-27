defmodule Tinkex.Types.GetInfoResponse do
  @moduledoc """
  Response payload containing active model metadata.
  """

  alias Tinkex.Types.ModelData

  @enforce_keys [:model_id, :model_data]
  defstruct [:model_id, :model_data, :is_lora, :lora_rank, :model_name, :type]

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
    model_data_json = json["model_data"] || json[:model_data] || %{}

    %__MODULE__{
      model_id: json["model_id"] || json[:model_id],
      model_data: ModelData.from_json(model_data_json),
      is_lora: json["is_lora"] || json[:is_lora],
      lora_rank: json["lora_rank"] || json[:lora_rank],
      model_name: json["model_name"] || json[:model_name],
      type: json["type"] || json[:type]
    }
  end
end
