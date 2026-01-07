defmodule Tinkex.SamplingDispatchTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Foundation.RateLimit.BackoffWindow
  alias Tinkex.{PoolKey, SamplingDispatch}

  test "applies 20x byte penalty during recent backoff" do
    limiter =
      BackoffWindow.for_key(
        :tinkex_rate_limiters,
        {:limiter, {PoolKey.normalize_base_url("http://example.com"), "k"}}
      )

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

          receive do
            :release_task1 -> :ok
          end

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

    send(task1.pid, :release_task1)

    assert_receive :task2_acquired, 500

    assert :done = Task.await(task1, 1_000)
    assert :done = Task.await(task2, 1_000)
  end

  test "executes without throttling when no backoff" do
    limiter =
      BackoffWindow.for_key(
        :tinkex_rate_limiters,
        {:limiter, {PoolKey.normalize_base_url("http://example.com"), "k2"}}
      )

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

  test "acquires with jittered exponential backoff when busy" do
    limiter =
      BackoffWindow.for_key(
        :tinkex_rate_limiters,
        {:limiter, {PoolKey.normalize_base_url("http://example.com"), "k3"}}
      )

    parent = self()
    attempts = :atomics.new(1, [])

    acquire_fun = fn _name, _limit ->
      attempt = :atomics.add_get(attempts, 1, 1)
      attempt > 3
    end

    sleep_fun = fn ms -> send(parent, {:slept, ms}) end

    {:ok, dispatch} =
      SamplingDispatch.start_link(
        rate_limiter: limiter,
        base_url: "http://example.com",
        api_key: "tml-k3",
        byte_budget: 1_000_000,
        concurrency: 1,
        throttled_concurrency: 1,
        acquire_backoff: [
          base_ms: 2,
          max_ms: 20,
          jitter: 0.0,
          sleep_fun: sleep_fun,
          acquire_fun: acquire_fun,
          release_fun: fn _name -> :ok end,
          rand_fun: fn -> 0.0 end
        ]
      )

    assert :ok == SamplingDispatch.with_rate_limit(dispatch, 0, fn -> :ok end)
    assert_receive {:slept, 2}
    assert_receive {:slept, 4}
    assert_receive {:slept, 8}
    refute_receive {:slept, _}
  end
end
