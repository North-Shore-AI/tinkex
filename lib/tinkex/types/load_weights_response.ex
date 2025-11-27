defmodule Tinkex.Types.LoadWeightsResponse do
  @moduledoc """
  Response payload for load_weights.
  """

  defstruct [:path, type: "load_weights"]

  @type t :: %__MODULE__{
          path: String.t() | nil,
          type: String.t()
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"path" => path} = json) do
    %__MODULE__{path: path, type: json["type"] || "load_weights"}
  end

  def from_json(%{} = json) do
    %__MODULE__{path: json[:path], type: json[:type] || "load_weights"}
  end
end
