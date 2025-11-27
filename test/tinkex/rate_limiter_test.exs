defmodule Tinkex.RateLimiterTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.{PoolKey, RateLimiter}

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  test "for_key reuses atomics for normalized URLs" do
    base_url = "https://EXAMPLE.com:443"
    api_key = "key-1"
    normalized = PoolKey.normalize_base_url(base_url)
    key = {:limiter, {normalized, api_key}}

    on_exit(fn -> :ets.delete(:tinkex_rate_limiters, key) end)

    :ets.delete(:tinkex_rate_limiters, key)
    limiter1 = RateLimiter.for_key({base_url, api_key})
    limiter2 = RateLimiter.for_key({"https://example.com", api_key})

    assert limiter1 == limiter2
    assert [{^key, ^limiter1}] = :ets.lookup(:tinkex_rate_limiters, key)
  end

  test "insert_new prevents duplicate limiter creation" do
    base_url = unique_base_url()
    api_key = "key-" <> Integer.to_string(System.unique_integer([:positive]))
    normalized = PoolKey.normalize_base_url(base_url)
    key = {:limiter, {normalized, api_key}}

    on_exit(fn -> :ets.delete(:tinkex_rate_limiters, key) end)

    :ets.delete(:tinkex_rate_limiters, key)

    task =
      Task.async(fn ->
        RateLimiter.for_key({base_url, api_key})
      end)

    limiter1 = RateLimiter.for_key({base_url, api_key})
    limiter2 = Task.await(task, 2_000)

    assert limiter1 == limiter2
    assert [{^key, ^limiter1}] = :ets.lookup(:tinkex_rate_limiters, key)
  end

  test "set_backoff and wait_for_backoff cooperate with should_backoff?" do
    base_url = unique_base_url()
    api_key = "key-" <> Integer.to_string(System.unique_integer([:positive]))
    normalized = PoolKey.normalize_base_url(base_url)
    key = {:limiter, {normalized, api_key}}

    on_exit(fn -> :ets.delete(:tinkex_rate_limiters, key) end)

    :ets.delete(:tinkex_rate_limiters, key)
    limiter = RateLimiter.for_key({base_url, api_key})

    RateLimiter.clear_backoff(limiter)
    refute RateLimiter.should_backoff?(limiter)

    RateLimiter.set_backoff(limiter, 120)
    assert RateLimiter.should_backoff?(limiter)

    start_ms = System.monotonic_time(:millisecond)
    :ok = RateLimiter.wait_for_backoff(limiter)
    elapsed = System.monotonic_time(:millisecond) - start_ms
    assert elapsed >= 100

    RateLimiter.clear_backoff(limiter)
    refute RateLimiter.should_backoff?(limiter)
  end

  defp unique_base_url do
    "https://example#{System.unique_integer([:positive])}.com"
  end
end
