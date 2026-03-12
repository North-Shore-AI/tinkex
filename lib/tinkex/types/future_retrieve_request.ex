defmodule Tinkex.Types.FutureRetrieveRequest do
  @moduledoc """
  Request to retrieve the result of a future/async operation.

  Mirrors Python `tinker.types.FutureRetrieveRequest`.
  """

  @enforce_keys [:request_id]
  defstruct [:request_id, allow_metadata_only: false]

  @type t :: %__MODULE__{
          request_id: String.t(),
          allow_metadata_only: boolean()
        }

  @doc """
  Create a new FutureRetrieveRequest.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(request_id, opts \\ []) when is_binary(request_id) do
    %__MODULE__{
      request_id: request_id,
      allow_metadata_only: Keyword.get(opts, :allow_metadata_only, false)
    }
  end

  @doc """
  Convert to JSON-encodable map.
  """
  @spec to_json(t()) :: map()
  def to_json(%__MODULE__{request_id: request_id, allow_metadata_only: allow_metadata_only}) do
    %{
      "request_id" => request_id,
      "allow_metadata_only" => allow_metadata_only
    }
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"request_id" => request_id} = json) do
    new(request_id, allow_metadata_only: Map.get(json, "allow_metadata_only", false))
  end

  def from_json(%{request_id: request_id} = json) do
    new(request_id, allow_metadata_only: Map.get(json, :allow_metadata_only, false))
  end
end
