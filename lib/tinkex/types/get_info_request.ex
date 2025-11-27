defmodule Tinkex.Types.GetInfoRequest do
  @moduledoc """
  Request payload for retrieving model metadata.
  """

  @enforce_keys [:model_id]
  @derive {Jason.Encoder, only: [:model_id, :type]}
  defstruct [:model_id, type: "get_info"]

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
