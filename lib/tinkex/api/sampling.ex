defmodule Tinkex.API.Sampling do
  @moduledoc """
  Sampling API endpoints.

  Uses :sampling pool (high concurrency).
  Pool size: 100 connections.
  """

  @doc """
  Async sample request.

  Uses :sampling pool (high concurrency).
  Sets max_retries: 0 - Phase 4's SamplingClient will implement client-side
  rate limiting and retry logic via RateLimiter. The HTTP layer doesn't retry
  so that the higher-level client can make intelligent retry decisions based
  on rate limit state.

  Note: Named `sample_async` for consistency with Elixir naming conventions
  (adjective_noun or verb_object patterns). The API endpoint remains /api/v1/asample.

  ## Examples

      Tinkex.API.Sampling.sample_async(
        %{session_id: "...", prompts: [...]},
        config: config
      )
  """
  @spec sample_async(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def sample_async(request, opts) do
    opts =
      opts
      |> Keyword.put(:pool_type, :sampling)
      |> Keyword.put(:max_retries, 0)

    Tinkex.API.post("/api/v1/asample", request, opts)
  end
end
