defmodule Tinkex.RetryTest do
  use ExUnit.Case, async: true

  alias Tinkex.Error
  alias Tinkex.Retry
  alias Tinkex.RetryHandler

  describe "with_retry/3" do
    test "returns success on first try" do
      result = Retry.with_retry(fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
    end

    test "retries on retryable error" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        attempt = :counters.get(counter, 1)

        if attempt < 3 do
          {:error, %Error{type: :api_status, status: 500, message: "server error"}}
        else
          {:ok, "success"}
        end
      end

      opts = [
        handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1, jitter_pct: 0.0)
      ]

      result = Retry.with_retry(fun, opts)
      assert result == {:ok, "success"}
      assert :counters.get(counter, 1) == 3
    end

    test "gives up after max_retries" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:error, %Error{type: :api_status, status: 500, message: "server error"}}
      end

      opts = [
        handler: RetryHandler.new(max_retries: 2, base_delay_ms: 1, jitter_pct: 0.0)
      ]

      result = Retry.with_retry(fun, opts)
      assert {:error, %Error{status: 500}} = result
      assert :counters.get(counter, 1) == 3
    end

    test "does not retry user errors" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:error, %Error{type: :api_status, status: 400, message: "bad request"}}
      end

      opts = [
        handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1)
      ]

      result = Retry.with_retry(fun, opts)
      assert {:error, %Error{status: 400}} = result
      assert :counters.get(counter, 1) == 1
    end

    test "emits telemetry events" do
      parent = self()
      handler_id = "test-retry-telemetry-#{System.unique_integer([:positive])}"

      events = [
        [:tinkex, :retry, :attempt, :start],
        [:tinkex, :retry, :attempt, :stop],
        [:tinkex, :retry, :attempt, :retry],
        [:tinkex, :retry, :attempt, :failed]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        attempt = :counters.get(counter, 1)

        if attempt < 2 do
          {:error, %Error{type: :api_status, status: 500, message: "server error"}}
        else
          {:ok, "success"}
        end
      end

      opts = [
        handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1, jitter_pct: 0.0),
        telemetry_metadata: %{test: true}
      ]

      result = Retry.with_retry(fun, opts)
      assert result == {:ok, "success"}

      :telemetry.detach(handler_id)

      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :start], _, _}
      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :retry], _, _}
      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :start], _, _}
      assert_receive {:telemetry, [:tinkex, :retry, :attempt, :stop], _, _}
    end

    test "handles exceptions" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        attempt = :counters.get(counter, 1)

        if attempt < 2 do
          raise "transient error"
        else
          {:ok, "success"}
        end
      end

      opts = [
        handler: RetryHandler.new(max_retries: 5, base_delay_ms: 1, jitter_pct: 0.0)
      ]

      result = Retry.with_retry(fun, opts)
      assert result == {:ok, "success"}
      assert :counters.get(counter, 1) == 2
    end

    test "respects progress timeout" do
      counter = :counters.new(1, [])

      fun = fn ->
        :counters.add(counter, 1, 1)
        {:error, %Error{type: :api_status, status: 500, message: "server error"}}
      end

      handler =
        RetryHandler.new(max_retries: 10, base_delay_ms: 1, progress_timeout_ms: 50)
        |> Map.put(:last_progress_at, System.monotonic_time(:millisecond) - 100)

      opts = [handler: handler]

      result = Retry.with_retry(fun, opts)
      assert {:error, %Error{type: :api_timeout}} = result
      assert :counters.get(counter, 1) == 0
    end
  end
end
