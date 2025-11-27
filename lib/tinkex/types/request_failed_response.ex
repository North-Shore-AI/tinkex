defmodule Tinkex.Types.RequestFailedResponse do
  @moduledoc """
  Response indicating a request has failed.

  Mirrors Python `tinker.types.RequestFailedResponse`.
  """

  alias Tinkex.Types.RequestErrorCategory

  @enforce_keys [:error, :category]
  defstruct [:error, :category]

  @type t :: %__MODULE__{
          error: String.t(),
          category: RequestErrorCategory.t()
        }

  @doc """
  Create a new RequestFailedResponse.
  """
  @spec new(String.t(), RequestErrorCategory.t()) :: t()
  def new(error, category) when is_binary(error) do
    %__MODULE__{error: error, category: category}
  end

  @doc """
  Parse from JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"error" => error, "category" => category}) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(category)
    }
  end

  def from_json(%{error: error, category: category}) do
    %__MODULE__{
      error: error,
      category: RequestErrorCategory.parse(category)
    }
  end
end
