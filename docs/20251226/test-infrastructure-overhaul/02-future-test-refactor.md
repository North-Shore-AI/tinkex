# Refactoring future_test.exs

## Current State

`test/tinkex/future_test.exs` currently uses a custom `MockHTTPClient` module with:
- A globally-named Agent (`name: __MODULE__`)
- Manual `mock_id` partitioning for test isolation
- Complex state management for responses and call counts

This pattern is inconsistent with the rest of the codebase which uses `Tinkex.HTTPCase` with Bypass.

---

## Target State

Rewrite the file to use:
- `Tinkex.HTTPCase` (which extends ExUnitFoundation)
- Bypass for HTTP mocking
- `stub_sequence/2` for multi-response scenarios
- `TelemetryHelpers` for telemetry assertions

---

## Complete Refactored File

```elixir
defmodule Tinkex.FutureTest do
  @moduledoc """
  Tests for Future polling behavior, covering retry logic, error handling,
  and telemetry emission.
  """

  use Tinkex.HTTPCase, async: true

  alias Tinkex.Future
  alias Tinkex.Error

  describe "poll_loop 408 handling (Python SDK parity)" do
    test "retries on 408 without backoff until success", %{bypass: bypass, config: config} do
      # Simulate: 408 -> 408 -> 408 -> success
      stub_sequence(bypass, [
        fn conn -> resp(conn, 408, %{"message" => "Request timeout"}) end,
        fn conn -> resp(conn, 408, %{"message" => "Request timeout"}) end,
        fn conn -> resp(conn, 408, %{"message" => "Request timeout"}) end,
        fn conn ->
          resp(conn, 200, %{
            "type" => "completed",
            "result" => %{"output" => "final result"}
          })
        end
      ])

      task = Future.poll("test-request", config: config)
      assert {:ok, %{"output" => "final result"}} = Task.await(task, 10_000)
    end

    test "eventually times out on endless 408s", %{bypass: bypass, config: config} do
      # Return 408 for every request
      Bypass.stub(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 408, %{"message" => "Request timeout"})
      end)

      # Use a short timeout for testing
      config = %{config | timeout: 500}

      task = Future.poll("test-request", config: config)
      assert {:error, %Error{type: :timeout}} = Task.await(task, 5_000)
    end
  end

  describe "poll_loop 5xx handling (Python SDK parity)" do
    test "continues polling on 500 status until success", %{bypass: bypass, config: config} do
      # Simulate: 500 -> 502 -> 503 -> success
      stub_sequence(bypass, [
        fn conn -> resp(conn, 500, %{"message" => "Internal error"}) end,
        fn conn -> resp(conn, 502, %{"message" => "Bad gateway"}) end,
        fn conn -> resp(conn, 503, %{"message" => "Service unavailable"}) end,
        fn conn ->
          resp(conn, 200, %{
            "type" => "completed",
            "result" => %{"output" => "success after errors"}
          })
        end
      ])

      task = Future.poll("test-request", config: config)
      assert {:ok, %{"output" => "success after errors"}} = Task.await(task, 10_000)
    end
  end

  describe "poll_loop mixed error handling" do
    test "handles 408 then 5xx then success", %{bypass: bypass, config: config} do
      stub_sequence(bypass, [
        fn conn -> resp(conn, 408, %{"message" => "Timeout"}) end,
        fn conn -> resp(conn, 503, %{"message" => "Unavailable"}) end,
        fn conn ->
          resp(conn, 200, %{
            "type" => "completed",
            "result" => %{"output" => "mixed recovery"}
          })
        end
      ])

      task = Future.poll("test-request", config: config)
      assert {:ok, %{"output" => "mixed recovery"}} = Task.await(task, 10_000)
    end
  end

  describe "poll_loop terminal errors" do
    test "stops on 410 (expired promise)", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 410, %{"message" => "Promise expired", "category" => "server"})
      end)

      task = Future.poll("test-request", config: config)
      assert {:error, %Error{status: 410}} = Task.await(task, 5_000)
    end

    test "stops on 4xx user errors (except 408)", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 400, %{"message" => "Bad request", "category" => "user"})
      end)

      task = Future.poll("test-request", config: config)
      assert {:error, %Error{status: 400, category: :user}} = Task.await(task, 5_000)
    end
  end

  describe "poll_loop connection errors" do
    test "retries on connection errors until success", %{bypass: bypass, config: config} do
      # First call fails with connection error (Bypass down)
      # Subsequent calls succeed
      call_count = :counters.new(1, [:atomics])

      Bypass.stub(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count < 2 do
          # Simulate connection failure by closing socket
          Plug.Conn.send_resp(conn, 503, "")
        else
          resp(conn, 200, %{
            "type" => "completed",
            "result" => %{"output" => "recovered"}
          })
        end
      end)

      task = Future.poll("test-request", config: config)
      assert {:ok, %{"output" => "recovered"}} = Task.await(task, 10_000)
    end
  end

  describe "poll telemetry" do
    test "emits telemetry events on successful poll", %{bypass: bypass, config: config} do
      {:ok, _} = TelemetryHelpers.attach_isolated([
        [:tinkex, :future, :poll, :start],
        [:tinkex, :future, :poll, :stop]
      ])

      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 200, %{
          "type" => "completed",
          "result" => %{"output" => "done"}
        })
      end)

      task = Future.poll("test-request", config: config)
      assert {:ok, _} = Task.await(task, 5_000)

      TelemetryHelpers.assert_telemetry([:tinkex, :future, :poll, :start])
      TelemetryHelpers.assert_telemetry([:tinkex, :future, :poll, :stop], %{status: :ok})
    end

    test "emits error telemetry on failure", %{bypass: bypass, config: config} do
      {:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :api_error])

      Bypass.expect_once(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
        resp(conn, 400, %{"message" => "Bad request", "category" => "user"})
      end)

      task = Future.poll("test-request", config: config)
      assert {:error, _} = Task.await(task, 5_000)

      TelemetryHelpers.assert_telemetry([:tinkex, :future, :api_error], %{status: 400})
    end
  end
end
```

---

## Key Changes

### 1. Use HTTPCase Instead of ExUnit.Case

```elixir
# Before
use ExUnit.Case, async: true

# After
use Tinkex.HTTPCase, async: true
```

### 2. Remove MockHTTPClient Module

The entire `MockHTTPClient` module (lines 18-106) is deleted. Bypass handles all HTTP mocking.

### 3. Use Bypass for Response Sequences

```elixir
# Before (MockHTTPClient)
MockHTTPClient.set_responses(config, [
  {:error, %Error{type: :api_status, status: 408, message: "Request timeout"}},
  {:error, %Error{type: :api_status, status: 408, message: "Request timeout"}},
  {:ok, %Response{body: %{"type" => "completed", "result" => %{}}}}
])

# After (Bypass)
stub_sequence(bypass, [
  fn conn -> resp(conn, 408, %{"message" => "Request timeout"}) end,
  fn conn -> resp(conn, 408, %{"message" => "Request timeout"}) end,
  fn conn -> resp(conn, 200, %{"type" => "completed", "result" => %{}}) end
])
```

### 4. Use TelemetryHelpers for Telemetry Testing

```elixir
# Before
# (manual telemetry handler not present in original, but needed)

# After
{:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :future, :poll, :start])
TelemetryHelpers.assert_telemetry([:tinkex, :future, :poll, :start])
```

### 5. Remove Manual State Management

No more:
- `mock_id` generation
- Agent state partitioning
- Call count tracking via persistent_term
- Manual cleanup in `on_exit`

All handled automatically by HTTPCase and Bypass.

---

## Migration Checklist

- [ ] Delete `MockHTTPClient` module definition (lines 18-106)
- [ ] Change `use ExUnit.Case` to `use Tinkex.HTTPCase`
- [ ] Update `setup` block to use `%{bypass: bypass, config: config}`
- [ ] Replace `MockHTTPClient.set_responses` with `stub_sequence`
- [ ] Replace `MockHTTPClient.get_call_count` with Bypass expectations or counters
- [ ] Add telemetry testing using `TelemetryHelpers`
- [ ] Verify all tests pass with `mix test test/tinkex/future_test.exs`
- [ ] Run 20 times with random seeds to verify no flakiness

---

## Notes

### Config Setup

HTTPCase automatically provides a `config` with the Bypass URL:

```elixir
# In HTTPCase setup
config = Config.new(base_url: "http://localhost:#{bypass.port}")
```

If additional config is needed:

```elixir
test "custom config", %{bypass: bypass, config: base_config} do
  config = %{base_config | timeout: 1000, request_id: "custom-id"}
  # ...
end
```

### Call Counting

If you need to verify call counts, use Erlang counters:

```elixir
test "retries correct number of times", %{bypass: bypass, config: config} do
  counter = :counters.new(1, [:atomics])

  Bypass.stub(bypass, "POST", "/api/v1/retrieve_future", fn conn ->
    :counters.add(counter, 1, 1)
    resp(conn, 200, %{"type" => "completed", "result" => %{}})
  end)

  task = Future.poll("test-request", config: config)
  Task.await(task, 5_000)

  assert :counters.get(counter, 1) == 1
end
```

### Bypass vs MockHTTPClient

| Aspect | MockHTTPClient | Bypass |
|--------|---------------|--------|
| HTTP fidelity | Low (mocks at client level) | High (real HTTP) |
| Isolation | Manual via mock_id | Per-test port |
| Setup complexity | High | Low (HTTPCase handles) |
| Debugging | Harder | Easier (real HTTP traffic) |
| Consistency | Inconsistent with codebase | Matches codebase pattern |
