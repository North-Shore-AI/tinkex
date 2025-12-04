# Telemetry Gaps

## Overview

Telemetry achieves ~70% parity. Both implementations capture events and exceptions, but the event model and server upload differ significantly.

## Feature Comparison

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Event batching | 100 events/batch | 100 events/batch | Parity |
| Queue size limit | 10,000 events | 10,000 events | Parity |
| Flush interval | 10 seconds | 10 seconds | Parity |
| Session start/end events | Yes | Yes | Parity |
| Generic events | Yes | Yes | Parity |
| Exception capture | Decorator | Macro | Different pattern |
| Server upload | Yes | No | **Gap** |
| Retry on upload | Infinite | Max retries | Different |

## Missing Features

### 1. Server-Side Telemetry Upload (High Priority)

**Python Implementation:**
```python
# telemetry.py lines 130-137
async def _send_batch_with_retry(self, batch: TelemetryBatch) -> TelemetryResponse:
    while True:  # Infinite retry
        try:
            return await self._send_batch(batch)
        except APIError as e:
            logger.warning("Failed to send telemetry batch", exc_info=e)
            await asyncio.sleep(1)
            continue
```

**Python API Endpoint:** `POST /api/v1/telemetry`

**Elixir Status:**
- Events collected locally
- No server upload implemented
- Uses `:telemetry` library for local event emission

**Implementation Recommendation:**
```elixir
# lib/tinkex/telemetry/uploader.ex
defmodule Tinkex.Telemetry.Uploader do
  use GenServer

  def upload_batch(events, config) do
    payload = %{
      events: Enum.map(events, &serialize_event/1),
      session_id: config.session_id
    }

    Tinkex.API.post(config, "/api/v1/telemetry", payload)
  end
end
```

### 2. Exception Chain Traversal (Low Priority)

**Python Implementation:**
```python
# telemetry.py lines 405-431
def _get_user_error(exception, visited=None):
    # Traverses __cause__ and __context__ for user errors
    if (cause := getattr(exception, "__cause__", None)) is not None:
        if (user_error := _get_user_error(cause, visited)) is not None:
            return user_error
    if (context := getattr(exception, "__context__", None)) is not None:
        return _get_user_error(context, visited)
```

**Elixir Status:** Uses depth-first candidate extraction with `:cause`, `:reason`, `:plug_status`

**Note:** Different error chain models. Elixir approach is idiomatic.

### 3. Async Context Manager for Capture (Low Priority)

**Python Implementation:**
```python
async def acapture_exceptions(self, fatal=False, severity="ERROR"):
    try:
        yield
    except Exception as e:
        self.capture_exception(e, fatal, severity)
        raise
```

**Elixir Status:** Only synchronous capture via macros

**Note:** Less critical in Elixir due to different concurrency model.

## Architecture Differences

### Concurrency Model

| Aspect | Python | Elixir |
|--------|--------|--------|
| State management | Thread locks | GenServer |
| Async coordination | asyncio + threading | BEAM processes |
| Flush sync | Cross-thread bridge | GenServer.call |

### Exception Capture Pattern

**Python:**
```python
@capture_exceptions(fatal=True)
def method(self):
    ...
```

**Elixir:**
```elixir
def method(state) do
  TelemetryCapture.capture_exceptions reporter: state.telemetry_reporter do
    ...
  end
end
```

## Event Types Comparison

| Event Type | Python | Elixir |
|------------|--------|--------|
| `session_start` | Yes | Yes |
| `session_end` | Yes | Yes |
| `generic_event` | Yes | Yes |
| `unhandled_exception` | Yes | Yes |
| Custom events | Via `generic_event` | Via `:telemetry.execute` |

## Severity Levels

Both support: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`

## Recommendations

1. **Add server telemetry upload** if server-side analytics are needed
2. Keep local `:telemetry` integration for BEAM ecosystem compatibility
3. Consider hybrid: local events + optional server upload

## Files Reference

- Python: `tinker/lib/telemetry.py`, `tinker/lib/telemetry_provider.py`, `tinker/resources/telemetry.py`
- Elixir: `lib/tinkex/telemetry/reporter.ex`, `lib/tinkex/telemetry/capture.ex`
