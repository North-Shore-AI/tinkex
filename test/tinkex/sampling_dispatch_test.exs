defmodule Tinkex.SamplingDispatchTest do
  use ExUnit.Case, async: true

  alias Tinkex.{RateLimiter, SamplingDispatch}

  test "applies 20x byte penalty during recent backoff" do
    limiter = RateLimiter.for_key({"http://example.com", "k"})

    {:ok, dispatch} =
      SamplingDispatch.start_link(
        rate_limiter: limiter,
        base_url: "http://example.com",
        api_key: "tml-k",
        byte_budget: 1_000,
        concurrency: 2,
        throttled_concurrency: 2
      )

    SamplingDispatch.set_backoff(dispatch, 10_000)

    parent = self()

    task1 =
      Task.async(fn ->
        SamplingDispatch.with_rate_limit(dispatch, 100, fn ->
          send(parent, :task1_acquired)
          Process.sleep(50)
          :done
        end)
      end)

    assert_receive :task1_acquired, 500

    task2 =
      Task.async(fn ->
        SamplingDispatch.with_rate_limit(dispatch, 100, fn ->
          send(parent, :task2_acquired)
          :done
        end)
      end)

    # Penalty drives effective bytes beyond budget so second task should block until release
    refute_receive :task2_acquired, 20
    assert_receive :task2_acquired, 500

    assert :done = Task.await(task1, 1_000)
    assert :done = Task.await(task2, 1_000)
  end

  test "executes without throttling when no backoff" do
    limiter = RateLimiter.for_key({"http://example.com", "k2"})

    {:ok, dispatch} =
      SamplingDispatch.start_link(
        rate_limiter: limiter,
        base_url: "http://example.com",
        api_key: "tml-k2",
        byte_budget: 1_000_000,
        concurrency: 2,
        throttled_concurrency: 2
      )

    result =
      SamplingDispatch.with_rate_limit(dispatch, 100, fn ->
        :result
      end)

    assert result == :result
  end
end
