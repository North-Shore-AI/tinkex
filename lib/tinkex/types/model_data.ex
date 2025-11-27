defmodule Tinkex.Types.ModelData do
  @moduledoc """
  Model metadata including architecture, display name, and tokenizer id.
  """

  defstruct [:arch, :model_name, :tokenizer_id]

  @type t :: %__MODULE__{
          arch: String.t() | nil,
          model_name: String.t() | nil,
          tokenizer_id: String.t() | nil
        }

  @doc """
  Parse model metadata from a JSON map (string or atom keys).
  """
  @spec from_json(map()) :: t()
  def from_json(%{} = json) do
    %__MODULE__{
      arch: json["arch"] || json[:arch],
      model_name: json["model_name"] || json[:model_name],
      tokenizer_id: json["tokenizer_id"] || json[:tokenizer_id]
    }
  end
end
