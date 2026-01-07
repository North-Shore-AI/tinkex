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
  @spec from_response(Pristine.Core.Response.t(), map(), non_neg_integer() | nil, keyword()) ::
          t()
  def from_response(%Pristine.Core.Response{status: status}, body, retry_after_ms, _opts)
      when is_map(body) do
    category = derive_category(body["category"], status)

    %__MODULE__{
      message: body["message"] || body["error"] || default_message(status),
      type: :api_status,
      status: status,
      category: category,
      data: body,
      retry_after_ms: retry_after_ms || body["retry_after_ms"]
    }
  end

  def from_response(%Pristine.Core.Response{status: status}, body, retry_after_ms, opts) do
    from_response(status, %{"message" => body}, retry_after_ms, opts)
  end

  @spec from_response(integer(), map(), non_neg_integer() | nil, keyword()) :: t()
  def from_response(status, body, retry_after_ms, _opts) when is_map(body) do
    category = derive_category(body["category"], status)

    %__MODULE__{
      message: body["message"] || body["error"] || default_message(status),
      type: :api_status,
      status: status,
      category: category,
      data: body,
      retry_after_ms: retry_after_ms || body["retry_after_ms"]
    }
  end

  @spec from_response(integer(), map()) :: t()
  def from_response(status, body) when is_integer(status) and is_map(body) do
    from_response(status, body, body["retry_after_ms"], [])
  end

  @doc """
  Create a validation error from a decoding failure.
  """
  @spec validation_error(term(), term()) :: t()
  def validation_error(reason, body) do
    new(:validation, "JSON decode error: #{inspect(reason)}",
      category: :user,
      data: %{body: body}
    )
  end

  @doc """
  Create a connection error from a transport failure.
  """
  @spec connection_error(term()) :: t()
  def connection_error(reason) do
    new(:api_connection, format_reason(reason), data: %{exception: reason})
  end

  defp format_reason(reason) do
    cond do
      is_struct(reason) and function_exported?(reason.__struct__, :message, 1) ->
        Exception.message(reason)

      is_atom(reason) ->
        Atom.to_string(reason)

      is_binary(reason) ->
        reason

      true ->
        inspect(reason)
    end
  end

  defp derive_category(category, _status) when is_binary(category) do
    RequestErrorCategory.parse(category)
  end

  defp derive_category(_category, status) when is_integer(status) do
    cond do
      status == 429 -> :server
      status >= 400 and status < 500 -> :user
      status >= 500 and status < 600 -> :server
      true -> :unknown
    end
  end

  defp derive_category(_category, _status), do: :unknown

  defp default_message(status) when is_integer(status), do: "HTTP #{status}"
  defp default_message(_status), do: "Request failed"

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
