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

defmodule Tinkex.Types.TryAgainResponse do
  @moduledoc """
  Response indicating queue backpressure - client should retry.
  """

  @enforce_keys [:type, :request_id, :queue_state]
  defstruct [:type, :request_id, :queue_state, :retry_after_ms]

  @type queue_state :: :active | :paused_capacity | :paused_rate_limit
  @type t :: %__MODULE__{
          type: String.t(),
          request_id: String.t(),
          queue_state: queue_state(),
          retry_after_ms: non_neg_integer() | nil
        }

  @doc """
  Parse queue state from string.
  """
  @spec parse_queue_state(String.t()) :: queue_state()
  def parse_queue_state("active"), do: :active
  def parse_queue_state("paused_capacity"), do: :paused_capacity
  def parse_queue_state("paused_rate_limit"), do: :paused_rate_limit
  def parse_queue_state(_), do: :active
end

defmodule Tinkex.Types.FutureRetrieveResponse do
  @moduledoc """
  Union type for future retrieve responses.

  Parses the appropriate response type based on status/type field.
  """

  alias Tinkex.Types.{
    FuturePendingResponse,
    FutureCompletedResponse,
    FutureFailedResponse,
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
  def from_json(%{"type" => "try_again"} = json) do
    %TryAgainResponse{
      type: "try_again",
      request_id: json["request_id"],
      queue_state: TryAgainResponse.parse_queue_state(json["queue_state"]),
      retry_after_ms: json["retry_after_ms"]
    }
  end

  def from_json(%{"status" => "pending"}) do
    %FuturePendingResponse{status: "pending"}
  end

  def from_json(%{"status" => "completed"} = json) do
    %FutureCompletedResponse{
      status: "completed",
      result: json["result"]
    }
  end

  def from_json(%{"status" => "failed"} = json) do
    %FutureFailedResponse{
      status: "failed",
      error: json["error"]
    }
  end
end
