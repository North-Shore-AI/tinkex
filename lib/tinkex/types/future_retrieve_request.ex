defmodule Tinkex.Types.FutureRetrieveRequest do
  @moduledoc """
  Request to retrieve the result of a future/async operation.

  Mirrors Python `tinker.types.FutureRetrieveRequest`.
  """

  @enforce_keys [:request_id]
  defstruct [:request_id]

  @type t :: %__MODULE__{
          request_id: String.t()
        }

  @doc """
  Create a new FutureRetrieveRequest.
  """
  @spec new(String.t()) :: t()
  def new(request_id) when is_binary(request_id) do
    %__MODULE__{request_id: request_id}
  end

  @doc """
  Convert to JSON-encodable map.
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{request_id: request_id}) do
    %{"request_id" => request_id}
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"request_id" => request_id}), do: new(request_id)
  def from_json(%{request_id: request_id}), do: new(request_id)
end
