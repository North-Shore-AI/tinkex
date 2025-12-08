defmodule Tinkex.Error do
  @moduledoc """
  Error type for Tinkex operations.

  Mirrors Python tinker error handling with categorization for retry logic.
  """

  alias Tinkex.Types.RequestErrorCategory

  defstruct [:message, :type, :status, :category, :data, :retry_after_ms]

  @type error_type ::
          :api_connection
          | :api_timeout
          | :api_status
          | :request_failed
          | :validation

  @type t :: %__MODULE__{
          message: String.t(),
          type: error_type(),
          status: integer() | nil,
          category: RequestErrorCategory.t() | nil,
          data: map() | nil,
          retry_after_ms: non_neg_integer() | nil
        }

  @doc """
  Create a new error.
  """
  @spec new(error_type(), String.t(), keyword()) :: t()
  def new(type, message, opts \\ []) do
    %__MODULE__{
      message: message,
      type: type,
      status: Keyword.get(opts, :status),
      category: Keyword.get(opts, :category),
      data: Keyword.get(opts, :data),
      retry_after_ms: Keyword.get(opts, :retry_after_ms)
    }
  end

  @doc """
  Create an error from an HTTP response.
  """
  @spec from_response(integer(), map()) :: t()
  def from_response(status, body) when is_map(body) do
    category =
      case body["category"] do
        nil -> nil
        cat -> RequestErrorCategory.parse(cat)
      end

    %__MODULE__{
      message: body["message"] || body["error"] || "Request failed",
      type: :request_failed,
      status: status,
      category: category,
      data: body,
      retry_after_ms: body["retry_after_ms"]
    }
  end

  @doc """
  Check if error is a user error (not retryable).

  Truth table:
  - category == :user → YES
  - status 4xx (except 408, 429) → YES
  - Everything else → NO
  """
  @spec user_error?(t()) :: boolean()
  def user_error?(%__MODULE__{category: :user}), do: true

  def user_error?(%__MODULE__{status: status})
      when is_integer(status) and status >= 400 and status < 500 and status not in [408, 410, 429] do
    true
  end

  def user_error?(_), do: false

  @doc """
  Check if error is retryable.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(error) do
    not user_error?(error)
  end

  @doc """
  Format error as string.
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{message: message, type: type, status: status}) do
    status_str = if status, do: " (#{status})", else: ""
    "[#{type}#{status_str}] #{message}"
  end
end

defimpl String.Chars, for: Tinkex.Error do
  def to_string(error) do
    Tinkex.Error.format(error)
  end
end
