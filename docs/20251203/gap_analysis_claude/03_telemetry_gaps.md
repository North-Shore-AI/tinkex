# Telemetry Gaps

## Overview

Telemetry achieves ~90% parity. Both SDKs batch events, respect queue limits, and upload to `/api/v1/telemetry`. Differences are in retry semantics and decorator vs macro capture style.

## Feature Comparison

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Event batching | 100 events/batch | 100 events/batch | Parity |
| Queue size limit | 10,000 events | 10,000 events | Parity |
| Flush interval | 10 seconds | 10 seconds | Parity |
| Session start/end events | Yes | Yes | Parity |
| Generic events | Yes | Yes | Parity |
| Exception capture | Decorator | Macro | Different pattern |
| Server upload | Yes (`POST /api/v1/telemetry`) | Yes (`POST /api/v1/telemetry`) | Parity |
| Retry on upload | Infinite retry loop | Bounded (max_retries=3, exponential backoff) | Different |

## Differences

### 1. Retry semantics
- **Python:** Infinite retry loop on upload failures (1s backoff).
- **Elixir:** Bounded retries (default max_retries=3 with exponential backoff); async and sync send variants.

### 2. Exception chain traversal (Low Priority)

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

### 3. Capture pattern (Low Priority)
- **Python:** Decorator/contextmanager (sync and async).
- **Elixir:** Macros (`TelemetryCapture`) around GenServer handlers/tasks; no async context manager wrapper but functionally equivalent capture points.

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

1. Consider exposing retry/backoff knobs to align with Python’s infinite retry behavior when desired.
2. Keep `:telemetry` integration for BEAM ecosystem compatibility; document capture macro usage vs Python decorators.

## Files Reference

- Python: `tinker/lib/telemetry.py`, `tinker/lib/telemetry_provider.py`, `tinker/resources/telemetry.py`
- Elixir: `lib/tinkex/telemetry/reporter.ex`, `lib/tinkex/telemetry/capture.ex`
