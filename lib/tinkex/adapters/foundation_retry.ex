defmodule Tinkex.Adapters.FoundationRetry do
  @moduledoc """
  Foundation-based retry adapter.
  """

  @behaviour Tinkex.Ports.RetryStrategy

  alias Foundation.Backoff
  alias Foundation.Retry
  alias Foundation.Retry.HTTP, as: HTTPRetry

  @impl true
  def with_retry(fun, opts) when is_function(fun, 0) do
    policy = Keyword.fetch!(opts, :policy)
    {result, _state} = Retry.run(fun, policy)
    result
  end

  @impl true
  def build_policy(opts \\ []) do
    Retry.Policy.new(opts)
  end

  @impl true
  def build_backoff(opts \\ []) do
    Backoff.Policy.new(opts)
  end

  @impl true
  def should_retry?(response) do
    HTTPRetry.should_retry?(response)
  end

  @impl true
  def parse_retry_after(response) do
    headers =
      case response do
        %{headers: headers} -> headers
        %{"headers" => headers} -> headers
        _ -> response
      end

    HTTPRetry.parse_retry_after(headers)
  end
end
