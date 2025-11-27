defmodule Tinkex.Types.HealthResponse do
  @moduledoc """
  Health check response.
  """

  @enforce_keys [:status]
  defstruct [:status]

  @type t :: %__MODULE__{status: String.t()}

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(map) do
    %__MODULE__{status: map["status"] || map[:status]}
  end
end
