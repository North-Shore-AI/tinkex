defmodule Tinkex.Types.SaveWeightsResponse do
  @moduledoc """
  Response payload for save_weights.
  """

  @enforce_keys [:path]
  defstruct [:path, type: "save_weights"]

  @type t :: %__MODULE__{
          path: String.t(),
          type: String.t()
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"path" => path} = json) do
    %__MODULE__{path: path, type: json["type"] || "save_weights"}
  end

  def from_json(%{path: path} = json) do
    %__MODULE__{path: path, type: json[:type] || "save_weights"}
  end
end
