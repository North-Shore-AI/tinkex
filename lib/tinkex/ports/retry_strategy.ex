defmodule Tinkex.Ports.RetryStrategy do
  @moduledoc """
  Port for retry policies.
  """

  @callback with_retry((-> term()), keyword()) :: term()
  @callback build_policy(keyword()) :: term()
  @callback build_backoff(keyword()) :: term()

  @doc """
  Determine if an HTTP response should be retried.
  """
  @callback should_retry?(map()) :: boolean()

  @doc """
  Parse a retry delay from HTTP response headers.
  """
  @callback parse_retry_after(map()) :: non_neg_integer() | nil

  @optional_callbacks [should_retry?: 1, parse_retry_after: 1]
end
