# Refactoring http_case.ex

## Current State

`test/support/http_case.ex` provides test infrastructure for HTTP-based tests using Bypass. It includes:

- Bypass setup and configuration
- `stub_sequence/2` for multi-response mocking
- `attach_telemetry/1` for telemetry handler management
- JSON response helpers

The telemetry handling uses global handlers without test-scoped filtering.

---

## Target State

Update HTTPCase to:
1. Integrate with Supertester v0.4.0's ExUnitFoundation
2. Enable telemetry isolation by default
3. Enable logger isolation by default
4. Provide TelemetryHelpers as the primary telemetry testing interface
5. Deprecate the old `attach_telemetry/1` function

---

## Complete Refactored File

```elixir
defmodule Tinkex.HTTPCase do
  @moduledoc """
  Test case template for HTTP-based tests using Bypass.

  Provides:
  - Automatic Bypass setup and cleanup
  - Pre-configured Tinkex.Config pointing to Bypass
  - Response stubbing helpers
  - Telemetry and Logger isolation via Supertester

  ## Usage

      defmodule MyTest do
        use Tinkex.HTTPCase, async: true

        test "makes request", %{bypass: bypass, config: config} do
          Bypass.expect_once(bypass, "POST", "/api/endpoint", fn conn ->
            resp(conn, 200, %{"result" => "success"})
          end)

          assert {:ok, _} = MyApp.make_request(config)
        end
      end

  ## Telemetry Testing

      test "emits telemetry", %{config: config} do
        {:ok, _} = TelemetryHelpers.attach_isolated([:myapp, :event])

        do_work(config)

        TelemetryHelpers.assert_telemetry([:myapp, :event], %{status: :ok})
      end

  ## Logger Testing

      test "logs correctly" do
        log = LoggerIsolation.capture_isolated!(:debug, fn ->
          do_work()
        end)

        assert log =~ "expected message"
      end
  """

  use ExUnit.CaseTemplate

  alias Tinkex.Config
  alias Supertester.TelemetryHelpers
  alias Supertester.LoggerIsolation

  using do
    quote do
      use Supertester.ExUnitFoundation,
        isolation: :full_isolation,
        telemetry_isolation: true,
        logger_isolation: true

      import Plug.Conn
      import Tinkex.HTTPCase

      alias Tinkex.Config
      alias Tinkex.Error
      alias Supertester.TelemetryHelpers
      alias Supertester.LoggerIsolation
    end
  end

  setup context do
    # Start Bypass
    bypass = Bypass.open()

    # Create config pointing to Bypass
    config = Config.new(
      base_url: "http://localhost:#{bypass.port}",
      api_key: "test-api-key",
      request_id: context[:request_id] || "test-#{System.unique_integer([:positive])}",
      timeout: context[:timeout] || 5_000
    )

    # Inject test telemetry ID into config for propagation
    telemetry_test_id = TelemetryHelpers.get_test_id()
    config = if telemetry_test_id do
      %{config | user_metadata: Map.put(config.user_metadata || %{}, :supertester_test_id, telemetry_test_id)}
    else
      config
    end

    {:ok, bypass: bypass, config: config}
  end

  @doc """
  Stub a sequence of responses for a Bypass endpoint.

  Each request to the endpoint will return the next response in the sequence.
  After all responses are consumed, subsequent requests will receive a 500 error.

  ## Example

      stub_sequence(bypass, [
        fn conn -> resp(conn, 408, %{"message" => "timeout"}) end,
        fn conn -> resp(conn, 200, %{"result" => "success"}) end
      ])

  ## Options

  - `:method` - HTTP method (default: "POST")
  - `:path` - Request path (default: "/api/v1/retrieve_future")
  """
  def stub_sequence(bypass, responses, opts \\ []) do
    method = Keyword.get(opts, :method, "POST")
    path = Keyword.get(opts, :path, "/api/v1/retrieve_future")

    counter = :counters.new(1, [:atomics])

    Bypass.stub(bypass, method, path, fn conn ->
      index = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)

      case Enum.at(responses, index) do
        nil ->
          resp(conn, 500, %{"error" => "No more stubbed responses"})

        response_fn when is_function(response_fn, 1) ->
          response_fn.(conn)
      end
    end)
  end

  @doc """
  Send a JSON response with proper content-type header.

  ## Example

      Bypass.expect_once(bypass, "POST", "/endpoint", fn conn ->
        resp(conn, 200, %{"result" => "success"})
      end)
  """
  def resp(conn, status, body) when is_map(body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end

  def resp(conn, status, body) when is_binary(body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, body)
  end

  @doc """
  Read and decode the request body as JSON.

  ## Example

      Bypass.expect_once(bypass, "POST", "/endpoint", fn conn ->
        {:ok, body} = read_body(conn)
        assert body["key"] == "value"
        resp(conn, 200, %{"ok" => true})
      end)
  """
  def read_body(conn) do
    {:ok, raw, _conn} = Plug.Conn.read_body(conn)
    Jason.decode(raw)
  end

  # ============================================================================
  # DEPRECATED FUNCTIONS
  # ============================================================================

  @doc """
  DEPRECATED: Use `TelemetryHelpers.attach_isolated/1` instead.

  Attach telemetry handlers for testing.

  This function is deprecated because it doesn't provide test isolation.
  Use `TelemetryHelpers.attach_isolated/1` for async-safe telemetry testing.
  """
  @deprecated "Use TelemetryHelpers.attach_isolated/1 instead"
  def attach_telemetry(events) do
    IO.warn(
      "attach_telemetry/1 is deprecated. Use TelemetryHelpers.attach_isolated/1 instead.",
      Macro.Env.stacktrace(__ENV__)
    )

    handler_id = "test-handler-#{:erlang.unique_integer()}"
    parent = self()

    :telemetry.attach_many(
      handler_id,
      events,
      &handle_event/4,
      parent
    )

    ExUnit.Callbacks.on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    handler_id
  end

  @doc false
  def handle_event(event, measurements, metadata, parent) do
    send(parent, {:telemetry, event, measurements, metadata})
  end
end
```

---

## Key Changes

### 1. Supertester Integration

```elixir
# Before
use ExUnit.CaseTemplate

# After
use ExUnit.CaseTemplate

using do
  quote do
    use Supertester.ExUnitFoundation,
      isolation: :full_isolation,
      telemetry_isolation: true,
      logger_isolation: true
    # ...
  end
end
```

### 2. Telemetry ID Propagation

The setup now injects the telemetry test ID into the config's user_metadata:

```elixir
telemetry_test_id = TelemetryHelpers.get_test_id()
config = if telemetry_test_id do
  %{config | user_metadata: Map.put(config.user_metadata || %{}, :supertester_test_id, telemetry_test_id)}
else
  config
end
```

This allows application code to include the test ID in telemetry events:

```elixir
# In application code (e.g., lib/tinkex/future.ex)
:telemetry.execute(
  [:tinkex, :future, :poll, :done],
  measurements,
  Map.merge(metadata, config.user_metadata || %{})
)
```

### 3. Deprecated attach_telemetry

The old function is kept for backward compatibility but marked deprecated:

```elixir
@deprecated "Use TelemetryHelpers.attach_isolated/1 instead"
def attach_telemetry(events) do
  IO.warn("attach_telemetry/1 is deprecated...")
  # ... old implementation
end
```

### 4. Helper Aliases

```elixir
alias Supertester.TelemetryHelpers
alias Supertester.LoggerIsolation
```

These are now available in all tests using HTTPCase.

---

## Application Code Changes

For telemetry isolation to work end-to-end, application code should propagate the test ID. Update telemetry emission points:

### lib/tinkex/future.ex (Example)

```elixir
defp emit_telemetry(event, measurements, config, additional_metadata \\ %{}) do
  metadata = %{
    request_id: config.request_id,
    # ... other metadata
  }

  # Merge user_metadata which may contain supertester_test_id
  metadata = Map.merge(metadata, config.user_metadata || %{})
  metadata = Map.merge(metadata, additional_metadata)

  :telemetry.execute([:tinkex, :future | event], measurements, metadata)
end
```

### lib/tinkex/api/request.ex (Example)

Similar pattern - ensure `config.user_metadata` is included in telemetry metadata.

---

## Migration Path

### Phase 1: Update HTTPCase

Apply the changes to `test/support/http_case.ex` as shown above.

### Phase 2: Update Tests Gradually

Tests using `attach_telemetry/1` will see deprecation warnings. Update them to use `TelemetryHelpers.attach_isolated/1`:

```elixir
# Before
handler_id = attach_telemetry([[:tinkex, :event]])
assert_receive {:telemetry, [:tinkex, :event], _, metadata}
:telemetry.detach(handler_id)

# After
{:ok, _} = TelemetryHelpers.attach_isolated([:tinkex, :event])
TelemetryHelpers.assert_telemetry([:tinkex, :event])
# No manual detach needed
```

### Phase 3: Update Application Code

Add user_metadata propagation to telemetry emission points.

### Phase 4: Remove Deprecated Function

After all tests are migrated, remove `attach_telemetry/1`.

---

## Backward Compatibility

- Tests using `attach_telemetry/1` continue to work but see deprecation warnings
- Tests not using telemetry are unaffected
- The `resp/2` and `stub_sequence/2` helpers are unchanged

---

## Testing the Changes

```bash
# Run all HTTP tests
mix test --only http

# Or run specific test files
mix test test/tinkex/future_test.exs test/tinkex/future/poll_test.exs

# Check for deprecation warnings
mix test 2>&1 | grep -i deprecated

# Verify no flakiness
for i in {1..20}; do
  mix test test/tinkex/future_test.exs test/tinkex/future/poll_test.exs --seed $RANDOM || echo "FAILED on run $i"
done
```

---

## File Diff Summary

| Section | Change |
|---------|--------|
| Module doc | Updated to include TelemetryHelpers usage |
| `using` block | Added ExUnitFoundation with isolation options |
| `setup` | Added telemetry ID injection into config |
| `attach_telemetry/1` | Marked as deprecated |
| Aliases | Added TelemetryHelpers and LoggerIsolation |
