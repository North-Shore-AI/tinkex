defmodule Tinkex.CircuitBreakerTest do
  @moduledoc """
  Tests for the circuit breaker pattern.
  """
  use ExUnit.Case, async: true

  alias Tinkex.CircuitBreaker

  describe "new/1" do
    test "creates a circuit breaker with default options" do
      cb = CircuitBreaker.new("test-endpoint")
      assert cb.name == "test-endpoint"
      assert cb.state == :closed
      assert cb.failure_count == 0
      assert cb.failure_threshold == 5
      assert cb.reset_timeout_ms == 30_000
    end

    test "creates a circuit breaker with custom options" do
      cb =
        CircuitBreaker.new("custom-endpoint",
          failure_threshold: 3,
          reset_timeout_ms: 10_000,
          half_open_max_calls: 2
        )

      assert cb.failure_threshold == 3
      assert cb.reset_timeout_ms == 10_000
      assert cb.half_open_max_calls == 2
    end
  end

  describe "allow_request?/1" do
    test "allows requests when closed" do
      cb = CircuitBreaker.new("test")
      assert CircuitBreaker.allow_request?(cb)
    end

    test "denies requests when open and timeout not elapsed" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 1)
        |> CircuitBreaker.record_failure()

      refute CircuitBreaker.allow_request?(cb)
    end

    test "allows requests in half-open state" do
      cb =
        CircuitBreaker.new("test",
          failure_threshold: 1,
          reset_timeout_ms: 0
        )
        |> CircuitBreaker.record_failure()

      # Wait briefly for timeout to elapse
      Process.sleep(10)

      assert CircuitBreaker.allow_request?(cb)
    end
  end

  describe "record_success/1" do
    test "resets failure count when closed" do
      cb =
        CircuitBreaker.new("test")
        |> Map.put(:failure_count, 2)
        |> CircuitBreaker.record_success()

      assert cb.failure_count == 0
    end

    test "transitions from half-open to closed after success" do
      cb =
        CircuitBreaker.new("test",
          failure_threshold: 1,
          reset_timeout_ms: 0,
          half_open_max_calls: 1
        )
        |> CircuitBreaker.record_failure()

      # Wait for reset timeout
      Process.sleep(10)

      # Now in half-open state (after allow_request? check)
      cb = CircuitBreaker.record_success(cb)

      assert cb.state == :closed
      assert cb.failure_count == 0
    end
  end

  describe "record_failure/1" do
    test "increments failure count" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 5)
        |> CircuitBreaker.record_failure()

      assert cb.failure_count == 1
      assert cb.state == :closed
    end

    test "opens circuit when threshold reached" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 2)
        |> CircuitBreaker.record_failure()
        |> CircuitBreaker.record_failure()

      assert cb.state == :open
    end

    test "sets opened_at timestamp when opening" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 1)
        |> CircuitBreaker.record_failure()

      assert cb.state == :open
      assert cb.opened_at != nil
    end
  end

  describe "state/1" do
    test "returns current state" do
      cb = CircuitBreaker.new("test")
      assert CircuitBreaker.state(cb) == :closed
    end

    test "returns :open when circuit is open" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 1)
        |> CircuitBreaker.record_failure()

      assert CircuitBreaker.state(cb) == :open
    end

    test "returns :half_open after reset timeout" do
      cb =
        CircuitBreaker.new("test",
          failure_threshold: 1,
          reset_timeout_ms: 0
        )
        |> CircuitBreaker.record_failure()

      Process.sleep(10)

      assert CircuitBreaker.state(cb) == :half_open
    end
  end

  describe "call/3" do
    test "executes function when circuit is closed" do
      cb = CircuitBreaker.new("test")

      {result, updated_cb} =
        CircuitBreaker.call(cb, fn -> {:ok, "success"} end)

      assert result == {:ok, "success"}
      assert updated_cb.failure_count == 0
    end

    test "records success on successful call" do
      cb =
        CircuitBreaker.new("test")
        |> Map.put(:failure_count, 2)

      {_result, updated_cb} =
        CircuitBreaker.call(cb, fn -> {:ok, "success"} end)

      assert updated_cb.failure_count == 0
    end

    test "records failure on error" do
      cb = CircuitBreaker.new("test", failure_threshold: 5)

      {result, updated_cb} =
        CircuitBreaker.call(cb, fn -> {:error, "failed"} end)

      assert result == {:error, "failed"}
      assert updated_cb.failure_count == 1
    end

    test "returns circuit_open error when open" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 1)
        |> CircuitBreaker.record_failure()

      {result, _cb} =
        CircuitBreaker.call(cb, fn -> {:ok, "should not run"} end)

      assert {:error, :circuit_open} = result
    end

    test "applies custom success/failure classification" do
      cb = CircuitBreaker.new("test", failure_threshold: 5)

      # 400 errors should not count as failures
      {_result, updated_cb} =
        CircuitBreaker.call(
          cb,
          fn -> {:error, %{status: 400}} end,
          success?: fn
            {:ok, _} -> true
            {:error, %{status: status}} when status < 500 -> true
            _ -> false
          end
        )

      assert updated_cb.failure_count == 0
    end
  end
end
