# Queue State Reason Propagation Specification

## Summary

Surface server-supplied `queue_state_reason` strings through the Future polling pipeline to QueueStateObserver callbacks and logging. Python SDK v0.7.0 now prefers server-provided reasons over hardcoded client defaults.

## Python SDK Reference

### API Future Implementation

```python
# tinker/src/tinker/lib/api_future_impl.py

class QueueStateObserver(ABC):
    @abstractmethod
    def on_queue_state_change(self, queue_state: QueueState, queue_state_reason: str | None) -> None:
        raise NotImplementedError

# In _APIFuture._result_async(), handling 408 responses:
if e.status_code == 408:
    if self._queue_state_observer is not None:
        with contextlib.suppress(Exception):
            response = e.response.json()
            if queue_state_str := response.get("queue_state", None):
                queue_state_reason = response.get("queue_state_reason", None)  # NEW
                # ... parse queue_state ...
                self._queue_state_observer.on_queue_state_change(queue_state, queue_state_reason)
```

### Training Client Observer

```python
# tinker/src/tinker/lib/public_interfaces/training_client.py

def on_queue_state_change(self, queue_state: QueueState, queue_state_reason: str | None) -> None:
    # ...
    if not queue_state_reason:  # Server reason takes priority
        if queue_state == QueueState.PAUSED_RATE_LIMIT:
            queue_state_reason = "concurrent training clients rate limit hit"
        elif queue_state == QueueState.PAUSED_CAPACITY:
            queue_state_reason = "Tinker backend is running short on capacity, please wait"
        else:
            queue_state_reason = "unknown"
    logger.warning(f"Training is paused for {self.model_id}. Reason: {queue_state_reason}")
```

### Sampling Client Observer

```python
# tinker/src/tinker/lib/public_interfaces/sampling_client.py

def on_queue_state_change(self, queue_state: QueueState, queue_state_reason: str | None) -> None:
    # ...
    if not queue_state_reason:  # Server reason takes priority
        if queue_state == QueueState.PAUSED_RATE_LIMIT:
            queue_state_reason = "concurrent sampler weights limit hit"  # UPDATED from "concurrent LoRA rate limit hit"
        elif queue_state == QueueState.PAUSED_CAPACITY:
            queue_state_reason = "Tinker backend is running short on capacity, please wait"  # UPDATED
        else:
            queue_state_reason = "unknown"
```

## Current Elixir Implementation

### QueueStateObserver Behaviour

```elixir
# lib/tinkex/queue_state_observer.ex
@callback on_queue_state_change(QueueState.t()) :: any()
```

### TryAgainResponse

```elixir
# lib/tinkex/types/try_again_response.ex
defstruct [:type, :request_id, :queue_state, :retry_after_ms]
# Missing: queue_state_reason field
```

### Future.poll

```elixir
# lib/tinkex/future.ex
defp notify_observer(observer, queue_state, metadata) when is_atom(observer) do
  if function_exported?(observer, :on_queue_state_change, 2) do
    observer.on_queue_state_change(queue_state, metadata)
  else
    observer.on_queue_state_change(queue_state)
  end
end
```

### QueueStateLogger

```elixir
# lib/tinkex/queue_state_logger.ex
def reason_for_state(:paused_rate_limit, :sampling), do: "concurrent LoRA rate limit hit"
def reason_for_state(:paused_rate_limit, :training), do: "concurrent models rate limit hit"
def reason_for_state(:paused_capacity, _), do: "out of capacity"
```

## Required Changes

### 1. TryAgainResponse - Add `queue_state_reason` Field

**File**: `lib/tinkex/types/try_again_response.ex`

```elixir
@enforce_keys [:type, :request_id, :queue_state]
defstruct [:type, :request_id, :queue_state, :retry_after_ms, :queue_state_reason]  # ADD

@type t :: %__MODULE__{
        type: String.t(),
        request_id: String.t(),
        queue_state: QueueState.t(),
        retry_after_ms: non_neg_integer() | nil,
        queue_state_reason: String.t() | nil  # ADD
      }

def from_map(map) when is_map(map) do
  # ... existing validation ...
  queue_state_reason = get_optional(map, :queue_state_reason)  # ADD

  %__MODULE__{
    type: type,
    request_id: request_id,
    queue_state: QueueState.parse(queue_state),
    retry_after_ms: retry_after_ms,
    queue_state_reason: queue_state_reason  # ADD
  }
end
```

### 2. Future State - Track Reason

**File**: `lib/tinkex/future.ex`

```elixir
defmodule State do
  defstruct request_id: nil,
            request_payload: nil,
            prev_queue_state: nil,
            prev_queue_state_reason: nil,  # ADD
            # ... rest unchanged
end

defp maybe_emit_queue_state_change(state, queue_state) do
  # Keep existing signature for backward compatibility
  maybe_emit_queue_state_change(state, queue_state, nil)
end

defp maybe_emit_queue_state_change(state, queue_state, queue_state_reason) do  # NEW overload
  cond do
    not valid_queue_state?(queue_state) ->
      state

    state.prev_queue_state == queue_state and
    state.prev_queue_state_reason == queue_state_reason ->
      state

    true ->
      metadata =
        state.metadata
        |> Map.put(:queue_state, queue_state)
        |> Map.put(:queue_state_reason, queue_state_reason)  # ADD

      :telemetry.execute(@queue_state_event, %{}, metadata)
      notify_observer(state.observer, queue_state, metadata)
      %{state |
        prev_queue_state: queue_state,
        prev_queue_state_reason: queue_state_reason}
  end
end
```

### 3. Update `handle_response` for TryAgainResponse

**File**: `lib/tinkex/future.ex`

```elixir
defp handle_response(%TryAgainResponse{} = response, state, iteration) do
  state = maybe_emit_queue_state_change(
    state,
    response.queue_state,
    response.queue_state_reason  # PASS REASON
  )
  sleep_ms = try_again_sleep_ms(response, iteration)
  sleep_and_continue(state, sleep_ms, iteration)
end
```

### 4. QueueStateObserver Behaviour - Optional 3-Arity Callback

**File**: `lib/tinkex/queue_state_observer.ex`

```elixir
@moduledoc """
Behaviour for modules that want to react to queue-state transitions.

## Callback Signatures

The behaviour supports two callback signatures for backward compatibility:

- `on_queue_state_change(queue_state)` - Legacy 1-arity
- `on_queue_state_change(queue_state, metadata)` - Extended 2-arity with metadata map

The metadata map now includes `:queue_state_reason` when provided by the server.
Observers can extract the reason via `metadata[:queue_state_reason]`.
"""

@callback on_queue_state_change(QueueState.t()) :: any()
@callback on_queue_state_change(QueueState.t(), map()) :: any()

@optional_callbacks [on_queue_state_change: 1, on_queue_state_change: 2]
```

### 5. QueueStateLogger - Prefer Server Reason

**File**: `lib/tinkex/queue_state_logger.ex`

```elixir
@doc """
Log a queue state change with appropriate human-readable reason.

When `server_reason` is provided and non-empty, it takes precedence
over the default client-side reasons. This matches Python SDK v0.7.0
behavior where server-supplied reasons are preferred.

## Parameters

- `queue_state` - One of `:active`, `:paused_rate_limit`, `:paused_capacity`, `:unknown`
- `client_type` - Either `:sampling` or `:training`
- `identifier` - Session ID for sampling, model ID for training
- `server_reason` - Optional server-supplied reason string (nil to use defaults)
"""
@spec log_state_change(queue_state(), client_type(), String.t(), String.t() | nil) :: :ok
def log_state_change(:active, _client_type, _identifier, _server_reason), do: :ok

def log_state_change(queue_state, client_type, identifier, server_reason \\ nil) do
  reason = resolve_reason(queue_state, client_type, server_reason)
  action = client_type_name(client_type)
  Logger.warning("#{action} is paused for #{identifier}. Reason: #{reason}")
end

@doc """
Resolve the reason string, preferring server-supplied reason.
"""
@spec resolve_reason(queue_state(), client_type(), String.t() | nil) :: String.t()
def resolve_reason(_queue_state, _client_type, reason) when is_binary(reason) and byte_size(reason) > 0 do
  reason
end

def resolve_reason(queue_state, client_type, _nil_or_empty) do
  reason_for_state(queue_state, client_type)
end

# UPDATE default messages to match Python SDK v0.7.0
@spec reason_for_state(queue_state(), client_type()) :: String.t()
def reason_for_state(:paused_rate_limit, :sampling), do: "concurrent sampler weights limit hit"  # UPDATED
def reason_for_state(:paused_rate_limit, :training), do: "concurrent training clients rate limit hit"  # UPDATED
def reason_for_state(:paused_capacity, _), do: "Tinker backend is running short on capacity"  # UPDATED
def reason_for_state(_, _), do: "unknown"
```

### 6. Update `maybe_log/5` Signature

**File**: `lib/tinkex/queue_state_logger.ex`

```elixir
@spec maybe_log(queue_state(), client_type(), String.t(), integer() | nil, String.t() | nil) :: integer() | nil
def maybe_log(:active, _client_type, _identifier, last_logged_at, _server_reason), do: last_logged_at

def maybe_log(queue_state, client_type, identifier, last_logged_at, server_reason \\ nil) do
  if should_log?(last_logged_at) do
    log_state_change(queue_state, client_type, identifier, server_reason)
    System.monotonic_time(:millisecond)
  else
    last_logged_at
  end
end
```

### 7. SamplingClient Observer Update

**File**: `lib/tinkex/sampling_client.ex`

```elixir
@impl Tinkex.QueueStateObserver
def on_queue_state_change(queue_state, metadata \\ %{}) do
  session_id = metadata[:sampling_session_id] || metadata[:session_id] || "unknown"
  server_reason = metadata[:queue_state_reason]  # EXTRACT server reason

  debounce_key = {:sampling_queue_state_debounce, session_id}
  last_logged = :persistent_term.get(debounce_key, nil)

  # Pass server_reason to maybe_log
  new_timestamp = QueueStateLogger.maybe_log(
    queue_state,
    :sampling,
    session_id,
    last_logged,
    server_reason  # NEW
  )

  if new_timestamp != last_logged do
    :persistent_term.put(debounce_key, new_timestamp)
  end

  :ok
end
```

### 8. TrainingClient Observer Update

**File**: `lib/tinkex/training_client.ex` or `lib/tinkex/training_client/observer.ex`

Similar pattern to SamplingClient - extract `queue_state_reason` from metadata and pass to `maybe_log/5`.

## Telemetry Event Metadata Update

The `[:tinkex, :queue, :state_change]` telemetry event metadata will now include:

```elixir
%{
  queue_state: :paused_rate_limit | :paused_capacity | :active | :unknown,
  queue_state_reason: "server-supplied reason" | nil,  # NEW
  request_id: "...",
  session_id: "...",
  # ... other existing fields
}
```

## Test Cases

```elixir
# test/tinkex/types/try_again_response_test.exs
describe "from_map/1" do
  test "parses queue_state_reason when present" do
    map = %{
      "type" => "try_again",
      "request_id" => "req-123",
      "queue_state" => "paused_rate_limit",
      "queue_state_reason" => "server says: too many requests"
    }
    response = TryAgainResponse.from_map(map)
    assert response.queue_state_reason == "server says: too many requests"
  end

  test "handles missing queue_state_reason" do
    map = %{
      "type" => "try_again",
      "request_id" => "req-123",
      "queue_state" => "paused_capacity"
    }
    response = TryAgainResponse.from_map(map)
    assert response.queue_state_reason == nil
  end
end

# test/tinkex/queue_state_logger_test.exs
describe "resolve_reason/3" do
  test "prefers server reason when provided" do
    reason = QueueStateLogger.resolve_reason(:paused_rate_limit, :sampling, "custom server reason")
    assert reason == "custom server reason"
  end

  test "falls back to default when server reason is nil" do
    reason = QueueStateLogger.resolve_reason(:paused_rate_limit, :sampling, nil)
    assert reason == "concurrent sampler weights limit hit"
  end

  test "falls back to default when server reason is empty" do
    reason = QueueStateLogger.resolve_reason(:paused_rate_limit, :sampling, "")
    assert reason == "concurrent sampler weights limit hit"
  end
end

# test/tinkex/future_test.exs
describe "queue state reason propagation" do
  test "passes queue_state_reason to observer via metadata" do
    # Setup mock observer that captures metadata
    # Assert metadata[:queue_state_reason] matches server response
  end
end
```

## Backward Compatibility

| Component | Compatibility |
|-----------|--------------|
| `TryAgainResponse` | New field is optional, existing parsing unaffected |
| `QueueStateObserver` | 2-arity callback already supported, reason in metadata |
| `QueueStateLogger` | New 4-arity/5-arity uses defaults, old calls still work |
| Telemetry events | New metadata field, existing handlers ignore unknown keys |

## Files Affected

| File | Change |
|------|--------|
| `lib/tinkex/types/try_again_response.ex` | Add `queue_state_reason` field |
| `lib/tinkex/future.ex` | Track and propagate reason |
| `lib/tinkex/queue_state_observer.ex` | Document reason in metadata |
| `lib/tinkex/queue_state_logger.ex` | Prefer server reason, update defaults |
| `lib/tinkex/sampling_client.ex` | Extract and pass server reason |
| `lib/tinkex/training_client.ex` | Extract and pass server reason |
| `test/tinkex/types/try_again_response_test.exs` | Add reason tests |
| `test/tinkex/queue_state_logger_test.exs` | Add reason resolution tests |
| `test/tinkex/future_test.exs` | Add reason propagation tests |

## Implementation Priority

**Medium** - Improves observability and matches Python SDK UX.
