defmodule Tinkex.Types.FuturePendingResponse do
  @moduledoc """
  Response indicating a future is still pending.
  """

  defstruct status: "pending"

  @type t :: %__MODULE__{
          status: String.t()
        }
end

defmodule Tinkex.Types.FutureCompletedResponse do
  @moduledoc """
  Response indicating a future has completed successfully.
  """

  @enforce_keys [:status, :result]
  defstruct [:status, :result]

  @type t :: %__MODULE__{
          status: String.t(),
          result: map()
        }
end

defmodule Tinkex.Types.FutureFailedResponse do
  @moduledoc """
  Response indicating a future has failed.
  """

  @enforce_keys [:status, :error]
  defstruct [:status, :error]

  @type t :: %__MODULE__{
          status: String.t(),
          error: map()
        }
end

defmodule Tinkex.Types.FutureRetrieveResponse do
  @moduledoc """
  Union type for future retrieve responses.

  Parses the appropriate response type based on status/type field.
  """

  alias Tinkex.Types.{
    FutureCompletedResponse,
    FutureFailedResponse,
    FuturePendingResponse,
    TryAgainResponse
  }

  @type t ::
          FuturePendingResponse.t()
          | FutureCompletedResponse.t()
          | FutureFailedResponse.t()
          | TryAgainResponse.t()

  @doc """
  Parse a future retrieve response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"type" => "try_again"} = json), do: TryAgainResponse.from_map(json)
  def from_json(%{type: "try_again"} = json), do: TryAgainResponse.from_map(json)

  def from_json(%{"status" => "pending"}) do
    %FuturePendingResponse{status: "pending"}
  end

  def from_json(%{status: "pending"}) do
    %FuturePendingResponse{status: "pending"}
  end

  def from_json(%{"status" => "completed"} = json) do
    %FutureCompletedResponse{
      status: "completed",
      result: json["result"]
    }
  end

  def from_json(%{status: "completed"} = json) do
    %FutureCompletedResponse{
      status: "completed",
      result: json[:result]
    }
  end

  def from_json(%{"status" => "failed"} = json) do
    %FutureFailedResponse{
      status: "failed",
      error: json["error"]
    }
  end

  def from_json(%{status: "failed"} = json) do
    %FutureFailedResponse{
      status: "failed",
      error: json[:error]
    }
  end

  # Some endpoints (e.g. thinker forward_backward) return the final result
  # directly with no status/type wrapper. Detect the ForwardBackwardOutput shape
  # and normalize it into a completed response so the poll loop can handle it.
  def from_json(%{"loss_fn_output_type" => _} = json) do
    %FutureCompletedResponse{status: "completed", result: json}
  end

  def from_json(%{loss_fn_output_type: _} = json) do
    %FutureCompletedResponse{status: "completed", result: json}
  end

  def from_json(%{"type" => _} = json) do
    %FutureCompletedResponse{status: "completed", result: json}
  end

  def from_json(%{type: _} = json) do
    %FutureCompletedResponse{status: "completed", result: json}
  end
end
