# Gap #4: Queue State Observer Parity - Deep Dive Analysis

**Date:** 2025-11-27
**Status:** COMPREHENSIVE INVESTIGATION COMPLETE
**Priority:** HIGH - Core user experience feature affecting observability

---

## Executive Summary

This gap analysis reveals a **significant behavioral difference** between Python and Elixir SDKs in how queue state changes are communicated to users. While both codebases have the infrastructure for queue state observation, **only Python actively implements human-friendly logging** when rate limits or capacity issues occur. The Elixir SDK has all the plumbing but lacks the actual observer implementations in the client classes.

**Key Finding:** The Python SDK provides automatic user feedback ("concurrent LoRA rate limit hit", "out of capacity") while Elixir users see silence unless they manually attach telemetry handlers.

Python file paths live under `./tinker/src/tinker/lib/...`; Elixir paths live under `./lib/tinkex/...`.

---

## Part 1: Python Deep Dive

### 1.1 Core Architecture

#### File: `tinker/src/tinker/lib/api_future_impl.py` (Lines 38-49, 78-163)

**QueueState Enum:**
```python
class QueueState(Enum):
    ACTIVE = "active"
    PAUSED_RATE_LIMIT = "paused_rate_limit"
    PAUSED_CAPACITY = "paused_capacity"
    UNKNOWN = "unknown"
```

**QueueStateObserver ABC:**
```python
class QueueStateObserver(ABC):
    @abstractmethod
    def on_queue_state_change(self, queue_state: QueueState) -> None:
        raise NotImplementedError
```

**Observer Integration in `_APIFuture`:**
- Constructor accepts `queue_state_observer: QueueStateObserver | None = None` (line 59)
- Stored in `self._queue_state_observer` (line 76)
- Callback triggered on **408 Request Timeout** with queue_state in response (lines 148-163)

**Critical Logic (Lines 149-163):**
```python
if e.status_code == 408:
    if self._queue_state_observer is not None:
        with contextlib.suppress(Exception):
            response = e.response.json()
            if queue_state_str := response.get("queue_state", None):
                if queue_state_str == "active":
                    queue_state = QueueState.ACTIVE
                elif queue_state_str == "paused_rate_limit":
                    queue_state = QueueState.PAUSED_RATE_LIMIT
                elif queue_state_str == "paused_capacity":
                    queue_state = QueueState.PAUSED_CAPACITY
                else:
                    queue_state = QueueState.UNKNOWN
                self._queue_state_observer.on_queue_state_change(queue_state)
    continue  # Retry indefinitely on 408
```

**Key Observations:**
1. Observer called during **408 error handling** (not try_again response type)
2. Manual string-to-enum parsing (no reuse of TryAgainResponse parsing)
3. Exceptions suppressed to prevent observer failures from breaking polling
4. 408s retry forever when no timeout is passed (default), or until an explicit timeout expires
5. The 200 `"try_again"` path logs and retries but **ignores** the queue_state field defined in `tinker/types/try_again_response.py`, so observers only fire for 408 JSON bodies

---

### 1.2 SamplingClient Implementation

#### File: `tinker/src/tinker/lib/public_interfaces/sampling_client.py` (Lines 33, 77-78, 187, 301-317)

**Class Declaration:**
```python
class SamplingClient(TelemetryProvider, QueueStateObserver):
```

**State Tracking:**
```python
self._last_queue_state_logged: float = 0  # Line 77
```

**Observer Injection (Line 187):**
```python
return await _APIFuture(
    types.SampleResponse,
    self.holder,
    untyped_future,
    request_start_time=time.time(),
    request_type="Sample",
    queue_state_observer=self,  # <-- Injects itself
).result_async()
```

**Human-Friendly Message Handler (Lines 301-317):**
```python
def on_queue_state_change(self, queue_state: QueueState) -> None:
    QUEUE_STATE_LOG_INTERVAL = 60  # Rate limit logging to once per minute

    if queue_state == QueueState.ACTIVE:
        return  # Don't log active state

    if time.time() - self._last_queue_state_logged < QUEUE_STATE_LOG_INTERVAL:
        return  # Debounce repeated logs

    # Map states to human-readable reasons
    if queue_state == QueueState.PAUSED_RATE_LIMIT:
        reason = "concurrent LoRA rate limit hit"
    elif queue_state == QueueState.PAUSED_CAPACITY:
        reason = "out of capacity"
    else:
        reason = "unknown"

    self._last_queue_state_logged = time.time()
    logger.warning(
        f"Sampling is paused for sampler {self._sampling_session_id}. Reason: {reason}"
    )
```

**UX Features:**
- **Debouncing:** 60-second interval prevents log spam
- **Human-readable messages:** Technical enum values → user-friendly explanations
- **Contextual info:** Includes sampling_session_id for multi-client debugging
- **Automatic silence for ACTIVE:** No noise when operations resume normally

---

### 1.3 TrainingClient Implementation

#### File: `tinker/src/tinker/lib/public_interfaces/training_client.py` (Lines 50, 87, 218, 311, 467, 521, 556, 648, 833-847)

**Class Declaration:**
```python
class TrainingClient(TelemetryProvider, QueueStateObserver):
```

**Observer Injection Sites:**
- `forward()` (line 218)
- `forward_backward()` (line 311)
- `optim_step()` (line 467)
- `save_state()` (line 521)
- `load_state_impl()` (line 556)
- `save_weights_for_sampler_impl()` (line 648)

**Message Handler (Lines 833-847):**
```python
def on_queue_state_change(self, queue_state: QueueState) -> None:
    QUEUE_STATE_LOG_INTERVAL = 60

    if queue_state == QueueState.ACTIVE:
        return

    if time.time() - self._last_queue_state_logged < QUEUE_STATE_LOG_INTERVAL:
        return

    self._last_queue_state_logged = time.time()

    # Different message for training vs sampling
    if queue_state == QueueState.PAUSED_RATE_LIMIT:
        reason = "concurrent models rate limit hit"  # Note: "models" not "LoRA"
    elif queue_state == QueueState.PAUSED_CAPACITY:
        reason = "out of capacity"
    else:
        reason = "unknown"

    logger.warning(f"Training is paused for {self.model_id}. Reason: {reason}")
```

**Differences from SamplingClient:**
- Message says "Training" instead of "Sampling"
- Reason says "concurrent models" instead of "concurrent LoRA"
- Context includes `model_id` instead of `sampling_session_id`

---

## Part 2: Elixir Deep Dive

### 2.1 Core Architecture

#### File: `lib/tinkex/queue_state_observer.ex` (Lines 1-31)

**Behaviour Definition:**
```elixir
defmodule Tinkex.QueueStateObserver do
  @moduledoc """
  Behaviour for modules that want to react to queue-state transitions.

  `Tinkex.Future.poll/2` emits telemetry for queue-state changes and, when given
  a `queue_state_observer`, will invoke the callback below. Training and
  Sampling clients can implement this behaviour to update local backpressure
  tracking whenever the server sends a `TryAgainResponse`.
  """

  alias Tinkex.Types.QueueState

  @callback on_queue_state_change(QueueState.t()) :: any()
end
```

**Documentation Claims:**
- States that "Training and Sampling clients can implement this behaviour"
- Notes it's for "backpressure tracking"
- Mentions `TryAgainResponse` as trigger

**Reality Check:** The documentation promises what Python does, but implementation is missing!

---

#### File: `types/queue_state.ex` (Lines 1-30)

**Type Definition:**
```elixir
@type t :: :active | :paused_rate_limit | :paused_capacity | :unknown
```

**Parser (Lines 19-29):**
```elixir
@spec parse(String.t() | nil) :: t()
def parse(value) when is_binary(value) do
  case value |> String.trim() |> String.downcase() do
    "active" -> :active
    "paused_rate_limit" -> :paused_rate_limit
    "paused_capacity" -> :paused_capacity
    _ -> :unknown  # Defaults to :unknown (matches Python's UNKNOWN)
  end
end

def parse(_), do: :unknown
```

**Key Differences vs Python parsing:**
- Elixir trims and lowercases input before matching; Python's manual parsing expects the exact lowercase string the server sends and will fall back to `QueueState.UNKNOWN` on any casing drift.
- Both SDKs now map unexpected/missing values to `unknown` (Elixir previously defaulted to `:active` before this parser change).

---

#### File: `lib/tinkex/future.ex` (Lines 1-373)

**Observer Integration (Lines 79-80, 116, 213-217, 278-292, 294-312):**

**State Tracking:**
```elixir
defmodule State do
  defstruct prev_queue_state: nil,  # Track last seen state (line 59)
            observer: nil,           # Observer module (line 79)
            # ... other fields
end
```

**Observer Initialization (Line 116):**
```elixir
state = %State{
  # ...
  observer: opts[:queue_state_observer],  # Module atom or nil
  # ...
}
```

**Trigger Point - TryAgainResponse Handler (Lines 213-217):**
```elixir
defp handle_response(%TryAgainResponse{} = response, state, iteration) do
  state = maybe_emit_queue_state_change(state, response.queue_state)
  sleep_ms = try_again_sleep_ms(response, iteration)
  sleep_and_continue(state, sleep_ms, iteration)
end
```

**Emission Logic (Lines 278-292):**
```elixir
defp maybe_emit_queue_state_change(state, queue_state) do
  cond do
    not valid_queue_state?(queue_state) ->
      state  # Ignore invalid states

    state.prev_queue_state == queue_state ->
      state  # Suppress duplicate events

    true ->
      metadata = Map.put(state.metadata, :queue_state, queue_state)
      :telemetry.execute(@queue_state_event, %{}, metadata)
      notify_observer(state.observer, queue_state)
      %{state | prev_queue_state: queue_state}
  end
end
```

**Observer Notification (Lines 294-312):**
```elixir
defp notify_observer(nil, _queue_state), do: :ok

defp notify_observer(observer, queue_state) when is_atom(observer) do
  try do
    observer.on_queue_state_change(queue_state)
  rescue
    _e in UndefinedFunctionError ->
      :ok  # Silently ignore if behaviour not implemented

    exception ->
      Logger.warning(
        "QueueStateObserver #{inspect(observer)} crashed: #{Exception.message(exception)}"
      )
      :ok
  end
end

defp notify_observer(_observer, _queue_state), do: :ok
```

**Critical Differences from Python:**
1. **Trigger:** Fires on `TryAgainResponse` (not 408 error like Python)
2. **Deduplication:** Only fires when queue_state **changes** (Python only applies a 60-second time-based debounce and does not track state transitions)
3. **Telemetry:** **Always** emits `[:tinkex, :queue, :state_change]` event
4. **Error Handling:** Catches `UndefinedFunctionError` to allow optional implementation
5. **Logging:** Logs observer crashes but doesn't break polling

---

### 2.2 SamplingClient (NON-)Implementation

#### File: `lib/tinkex/sampling_client.ex` (Lines 1-401)

**Observer Status: NOT IMPLEMENTED**

**Evidence:**
1. **No behaviour declaration** in module attributes
2. **No `on_queue_state_change/1` function** defined
3. **Observer passing** (lines 315-319):
   ```elixir
   poll_task = Future.poll(future,
     config: entry.config,
     # ...
     queue_state_observer: opts[:queue_state_observer],  # Passes through from caller
     # ...
   )
   ```
4. **Manual handling required:** Users must pass their own observer module

**What's Missing:**
- No debounced logging like Python
- No human-readable message mapping
- No automatic "concurrent LoRA rate limit hit" warnings
- No internal state tracking (`_last_queue_state_logged`)

---

### 2.3 TrainingClient (NON-)Implementation

#### File: `lib/tinkex/training_client.ex` (Lines 1-1556)

**Observer Status: NOT IMPLEMENTED**

**Evidence:**
1. **No behaviour declaration**
2. **No `on_queue_state_change/1` function**
3. **Observer passing** (lines 513, 575, 624, etc.):
   ```elixir
   task = state.future_module.poll(
     future,
     poll_opts_with_type(state, opts, "ForwardBackward")
   )
   ```

   Where `poll_opts_with_type/3` includes (lines 1425-1440):
   ```elixir
   defp poll_opts(state, opts) do
     opts
     |> Keyword.take([
       # ...
       :queue_state_observer,  # <-- Passes through from user opts
       # ...
     ])
   end
   ```

**What's Missing:**
- No automatic logging on rate limits
- No "Training is paused for {model_id}" messages
- No debouncing logic
- Must be manually implemented by users

---

## Part 3: Granular Differences

### 3.1 Observer Callback Signatures

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Type** | Abstract Base Class | Behaviour |
| **Signature** | `on_queue_state_change(self, queue_state: QueueState) -> None` | `on_queue_state_change(QueueState.t()) :: any()` |
| **Error Handling** | Exceptions suppressed in `_APIFuture` | Exceptions logged, UndefinedFunctionError silently ignored |
| **Return Value** | `None` | `any()` (more flexible) |

---

### 3.2 State Transition Handling

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Trigger Point** | 408 HTTP error with queue_state in JSON (200 `try_again` responses ignore queue_state) | `TryAgainResponse` type |
| **Parsing** | Manual, case-sensitive string-to-enum in `_APIFuture` | Case-insensitive `QueueState.parse/1` + `TryAgainResponse.from_map/1` |
| **Deduplication** | 60s time-based debounce only (state-agnostic) | Fires only on state **change** |
| **State Tracking** | Per-client `_last_queue_state_logged` (float) | Per-future `prev_queue_state` (atom) |
| **Telemetry** | None | Always emits `[:tinkex, :queue, :state_change]` |

---

### 3.3 Logging Behavior Differences

#### Python SamplingClient Messages:
```
WARNING  Sampling is paused for sampler <session-id>. Reason: concurrent LoRA rate limit hit
WARNING  Sampling is paused for sampler <session-id>. Reason: out of capacity
WARNING  Sampling is paused for sampler <session-id>. Reason: unknown
```

#### Python TrainingClient Messages:
```
WARNING  Training is paused for <model-id>. Reason: concurrent models rate limit hit
WARNING  Training is paused for <model-id>. Reason: out of capacity
WARNING  Training is paused for <model-id>. Reason: unknown
```

#### Elixir (Current):
```
(silence - no built-in logging)
```

---

### 3.4 Rate Limit Awareness Logic

**Python:**
- **Explicit debouncing:** 60-second `QUEUE_STATE_LOG_INTERVAL`
- **Time-based:** `time.time() - self._last_queue_state_logged < 60`
- **Per-client state:** Each client tracks its own last log time
- **Active state silence:** `if queue_state == QueueState.ACTIVE: return`

**Elixir:**
- **Change-based deduplication:** Only log on state transitions
- **Per-future state:** Each polling task tracks `prev_queue_state`
- **No time debouncing:** Multiple rapid transitions could all log
- **Telemetry always fires:** Observer can choose to debounce

---

## Part 4: Test Coverage Analysis

### 4.1 Python Tests

**Status:** No dedicated queue state observer tests found in scan

**Gaps:**
- No test for SamplingClient.on_queue_state_change
- No test for TrainingClient.on_queue_state_change
- No test for _APIFuture observer integration
- No test for message debouncing logic

---

### 4.2 Elixir Tests

#### File: `test/tinkex/types/queue_state_test.exs`

**Coverage:**
```elixir
test "parses known states case-insensitively"
test "treats unknown strings as :unknown (breaking change)"
test "handles nil values"
```

**Verdict:** Parser is well-tested ✓

---

#### File: `test/tinkex/future/poll_test.exs` (Lines 9-27, 95-134)

**TestObserver Implementation:**
```elixir
defmodule TestObserver do
  @behaviour Tinkex.QueueStateObserver

  def register(pid) when is_pid(pid) do
    :persistent_term.put({__MODULE__, :pid}, pid)
  end

  @impl true
  def on_queue_state_change(queue_state) do
    case :persistent_term.get({__MODULE__, :pid}, nil) do
      pid when is_pid(pid) -> send(pid, {:observer_called, queue_state})
      _ -> :ok
    end
  end
end
```

**Integration Test (Lines 95-134):**
```elixir
test "handles try_again responses with telemetry + observer" do
  stub_sequence(bypass, [
    {200,
     %{
       "type" => "try_again",
       "request_id" => "req-try",
       "queue_state" => "paused_rate_limit",
       "retry_after_ms" => nil
     }, []},
    {200, %{"status" => "completed", "result" => %{"done" => true}}, []}
  ])

  handler_id = attach_telemetry([[:tinkex, :queue, :state_change]])
  TestObserver.register(self())

  task = Future.poll("req-try",
    config: config,
    sleep_fun: sleep_fun,
    queue_state_observer: TestObserver
  )

  assert {:ok, %{"done" => true}} = Task.await(task, 1_000)

  # Verify telemetry
  assert_receive {:telemetry, [:tinkex, :queue, :state_change], %{},
                  %{queue_state: :paused_rate_limit, request_id: "req-try"}}

  # Verify observer callback
  assert_receive {:observer_called, :paused_rate_limit}
end
```

**Verdict:** Future.poll observer integration is well-tested ✓

---

**Missing Tests:**
- No tests for SamplingClient observer behavior (because not implemented)
- No tests for TrainingClient observer behavior (because not implemented)
- No tests for human-readable message generation
- No tests for debouncing/rate limiting of logs
- No tests for multi-client observer scenarios

---

## Part 5: TDD Implementation Plan

### Phase 1: Observer Behaviour Implementation (Red → Green → Refactor)

#### Test 1.1: SamplingClient Observer Callback (Red)

**File:** `test/tinkex/sampling_client_test.exs`

```elixir
defmodule Tinkex.SamplingClientTest.ObserverTest do
  use Tinkex.HTTPCase, async: false  # State tracking requires serial execution

  defmodule TestObserver do
    use Agent

    def start_link(_) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def get_events do
      Agent.get(__MODULE__, & &1)
    end

    def clear do
      Agent.update(__MODULE__, fn _ -> [] end)
    end
  end

  defmodule LogCapture do
    def start_link do
      {:ok, pid} = Agent.start_link(fn -> [] end, name: __MODULE__)
      {:ok, pid}
    end

    def logs do
      Agent.get(__MODULE__, & &1)
    end

    def capture(level, message) do
      Agent.update(__MODULE__, fn logs -> [{level, message} | logs] end)
    end
  end

  setup do
    {:ok, _} = TestObserver.start_link([])
    {:ok, _} = LogCapture.start_link()
    on_exit(fn -> TestObserver.clear() end)
    :ok
  end

  describe "queue state observer behaviour" do
    test "logs human-readable message on paused_rate_limit" do
      # RED: This will fail because SamplingClient doesn't implement the observer
      client = start_supervised!({SamplingClient,
        config: test_config(),
        session_id: "test-session",
        sampling_client_id: 1,
        base_model: "test-model"
      })

      # Simulate queue state change
      send(client, {:queue_state_change, :paused_rate_limit})

      # Should log warning with human-friendly message
      assert_receive {:log_captured, :warning, msg}, 1000
      assert msg =~ "Sampling is paused"
      assert msg =~ "concurrent LoRA rate limit hit"
    end

    test "logs different message on paused_capacity" do
      client = start_supervised!({SamplingClient,
        config: test_config(),
        session_id: "test-session",
        sampling_client_id: 1,
        base_model: "test-model"
      })

      send(client, {:queue_state_change, :paused_capacity})

      assert_receive {:log_captured, :warning, msg}, 1000
      assert msg =~ "out of capacity"
    end

    test "does not log when state is active" do
      client = start_supervised!({SamplingClient,
        config: test_config(),
        session_id: "test-session",
        sampling_client_id: 1,
        base_model: "test-model"
      })

      send(client, {:queue_state_change, :active})

      refute_receive {:log_captured, _, _}, 500
    end

    test "debounces repeated state changes within 60 seconds" do
      client = start_supervised!({SamplingClient,
        config: test_config(),
        session_id: "test-session",
        sampling_client_id: 1,
        base_model: "test-model"
      })

      # First log should fire
      send(client, {:queue_state_change, :paused_rate_limit})
      assert_receive {:log_captured, :warning, _}, 1000

      # Second log within 60s should be suppressed
      send(client, {:queue_state_change, :paused_rate_limit})
      refute_receive {:log_captured, _, _}, 500
    end

    test "allows logging after 60-second cooldown" do
      client = start_supervised!({SamplingClient,
        config: test_config(),
        session_id: "test-session",
        sampling_client_id: 1,
        base_model: "test-model"
      })

      # First log
      send(client, {:queue_state_change, :paused_rate_limit})
      assert_receive {:log_captured, :warning, _}, 1000

      # Fast-forward 61 seconds (mock System.monotonic_time)
      # This requires time mocking infrastructure
      Mox.stub(TimeMock, :monotonic_time, fn :millisecond -> 61_000 end)

      send(client, {:queue_state_change, :paused_rate_limit})
      assert_receive {:log_captured, :warning, _}, 1000
    end
  end
end
```

---

#### Implementation 1.1: SamplingClient Observer (Green)

**File:** `lib/tinkex/sampling_client.ex`

```elixir
defmodule Tinkex.SamplingClient do
  use GenServer
  use Tinkex.Telemetry.Provider

  @behaviour Tinkex.QueueStateObserver  # <-- Add behaviour

  require Logger  # <-- Add Logger

  # ... existing code ...

  @impl true
  def init(opts) do
    # ... existing initialization ...

    state = %{
      # ... existing state fields ...
      last_queue_state_logged: nil  # Track last log time
    }

    {:ok, state}
  end

  # ... existing GenServer handlers ...

  # New: Implement QueueStateObserver behaviour
  @impl Tinkex.QueueStateObserver
  def on_queue_state_change(queue_state) do
    # This is called by Future.poll when queue state changes
    # We need to get the client PID to access state - use process dictionary
    case Process.get(:sampling_client_pid) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, {:queue_state_change, queue_state})

      _ ->
        # Fallback: just log without debouncing if we can't access client
        log_queue_state_change(queue_state, nil, nil)
    end
  end

  @impl true
  def handle_cast({:queue_state_change, queue_state}, state) do
    state = maybe_log_queue_state_change(queue_state, state)
    {:noreply, state}
  end

  defp maybe_log_queue_state_change(:active, state), do: state

  defp maybe_log_queue_state_change(queue_state, state) do
    now = System.monotonic_time(:millisecond)

    should_log =
      case state.last_queue_state_logged do
        nil -> true
        last_time -> now - last_time >= 60_000  # 60 seconds
      end

    if should_log do
      log_queue_state_change(queue_state, state.sampling_session_id, state.session_id)
      %{state | last_queue_state_logged: now}
    else
      state
    end
  end

  defp log_queue_state_change(queue_state, sampling_session_id, session_id) do
    reason =
      case queue_state do
        :paused_rate_limit -> "concurrent LoRA rate limit hit"
        :paused_capacity -> "out of capacity"
        :unknown -> "unknown"
        _ -> "unknown"
      end

    context =
      case sampling_session_id do
        id when is_binary(id) -> "sampler #{id}"
        _ when is_binary(session_id) -> "session #{session_id}"
        _ -> "sampler"
      end

    Logger.warning("Sampling is paused for #{context}. Reason: #{reason}")
  end

  # Modify sample/4 to inject self as observer
  defp poll_sample_future(future, entry, seq_id, opts) do
    # Store client PID in process dictionary for observer callback
    Process.put(:sampling_client_pid, self())

    poll_task =
      Future.poll(future,
        config: entry.config,
        timeout: Keyword.get(opts, :timeout, :infinity),
        http_timeout: Keyword.get(opts, :http_timeout, entry.config.timeout),
        telemetry_metadata: merge_metadata(entry.telemetry_metadata, opts[:telemetry_metadata]),
        queue_state_observer: __MODULE__,  # <-- Inject self as observer module
        sleep_fun: opts[:sleep_fun],
        tinker_request_type: "Sample",
        tinker_request_iteration: seq_id
      )

    # ... rest of implementation
  end
end
```

---

#### Test 1.2: TrainingClient Observer Callback (Red)

**File:** `test/tinkex/training_client_test.exs`

```elixir
defmodule Tinkex.TrainingClientTest.ObserverTest do
  use Tinkex.HTTPCase, async: false

  describe "queue state observer behaviour" do
    test "logs human-readable message on paused_rate_limit for training" do
      client = start_supervised!({TrainingClient,
        config: test_config(),
        session_id: "test-session",
        model_seq_id: 1,
        base_model: "test-model"
      })

      send(client, {:queue_state_change, :paused_rate_limit})

      assert_receive {:log_captured, :warning, msg}, 1000
      assert msg =~ "Training is paused"
      assert msg =~ "concurrent models rate limit hit"  # Different from sampling!
    end

    test "includes model_id in log message" do
      client = start_supervised!({TrainingClient,
        config: test_config(),
        session_id: "test-session",
        model_seq_id: 1,
        base_model: "test-model"
      })

      # Get model_id from client state
      {:ok, info} = TrainingClient.get_info(client)
      model_id = info.model_data.model_id

      send(client, {:queue_state_change, :paused_capacity})

      assert_receive {:log_captured, :warning, msg}, 1000
      assert msg =~ model_id
    end

    test "debounces repeated logs like SamplingClient" do
      client = start_supervised!({TrainingClient,
        config: test_config(),
        session_id: "test-session",
        model_seq_id: 1,
        base_model: "test-model"
      })

      send(client, {:queue_state_change, :paused_rate_limit})
      assert_receive {:log_captured, :warning, _}, 1000

      send(client, {:queue_state_change, :paused_rate_limit})
      refute_receive {:log_captured, _, _}, 500
    end
  end
end
```

---

#### Implementation 1.2: TrainingClient Observer (Green)

**File:** `lib/tinkex/training_client.ex`

```elixir
defmodule Tinkex.TrainingClient do
  use GenServer
  use Tinkex.Telemetry.Provider

  @behaviour Tinkex.QueueStateObserver  # <-- Add behaviour

  require Logger  # <-- Add Logger

  # ... existing code ...

  @impl true
  def init(opts) do
    # ... existing initialization ...

    state = %{
      # ... existing state fields ...
      last_queue_state_logged: nil  # Track last log time
    }

    {:ok, state}
  end

  # ... existing GenServer handlers ...

  @impl Tinkex.QueueStateObserver
  def on_queue_state_change(queue_state) do
    case Process.get(:training_client_pid) do
      pid when is_pid(pid) ->
        GenServer.cast(pid, {:queue_state_change, queue_state})

      _ ->
        log_queue_state_change(queue_state, nil)
    end
  end

  @impl true
  def handle_cast({:queue_state_change, queue_state}, state) do
    state = maybe_log_queue_state_change(queue_state, state)
    {:noreply, state}
  end

  defp maybe_log_queue_state_change(:active, state), do: state

  defp maybe_log_queue_state_change(queue_state, state) do
    now = System.monotonic_time(:millisecond)

    should_log =
      case state.last_queue_state_logged do
        nil -> true
        last_time -> now - last_time >= 60_000
      end

    if should_log do
      log_queue_state_change(queue_state, state.model_id)
      %{state | last_queue_state_logged: now}
    else
      state
    end
  end

  defp log_queue_state_change(queue_state, model_id) do
    reason =
      case queue_state do
        :paused_rate_limit -> "concurrent models rate limit hit"  # Note: "models" not "LoRA"
        :paused_capacity -> "out of capacity"
        :unknown -> "unknown"
        _ -> "unknown"
      end

    context =
      case model_id do
        id when is_binary(id) -> id
        _ -> "model"
      end

    Logger.warning("Training is paused for #{context}. Reason: #{reason}")
  end

  # Modify poll_opts_with_type/3 to inject self as observer
  defp poll_opts_with_type(state, opts, request_type) do
    Process.put(:training_client_pid, self())

    poll_opts(state, opts)
    |> Keyword.put(:tinker_request_type, request_type)
    |> Keyword.put(:queue_state_observer, __MODULE__)  # <-- Inject self
  end
end
```

---

### Phase 2: Integration Tests (Red → Green)

#### Test 2.1: End-to-End SamplingClient with Queue State

**File:** `test/tinkex/sampling_client_integration_test.exs`

```elixir
defmodule Tinkex.SamplingClientIntegrationTest do
  use Tinkex.HTTPCase, async: false

  setup :setup_http_client

  test "automatically logs when hitting rate limit during sample", %{bypass: bypass, config: config} do
    # Setup: Create sampling session
    Bypass.expect_once(bypass, "POST", "/api/v1/service/create_sampling_session", fn conn ->
      resp(conn, 200, %{
        "sampling_session_id" => "test-sampler-123"
      })
    end)

    # Setup: First sample returns try_again with paused_rate_limit
    # Setup: Second sample returns completed
    stub_sequence(bypass, "POST", "/api/v1/sampling/sample_async", [
      {200, %{
        "type" => "try_again",
        "request_id" => "sample-req-1",
        "queue_state" => "paused_rate_limit"
      }},
      {200, %{
        "request_id" => "sample-req-1"
      }}
    ])

    stub_sequence(bypass, "POST", "/api/v1/retrieve_future", [
      {200, %{
        "type" => "try_again",
        "request_id" => "sample-req-1",
        "queue_state" => "paused_rate_limit"
      }},
      {200, %{
        "status" => "completed",
        "result" => %{
          "samples" => [%{"tokens" => [1, 2, 3]}]
        }
      }}
    ])

    # Start log capture
    Logger.configure(level: :warning)
    capture_log = start_supervised!({LogCapture, []})

    # Create client
    {:ok, client} = SamplingClient.start_link(
      config: config,
      session_id: "test-session",
      sampling_client_id: 1,
      base_model: "test-model"
    )

    # Trigger sample
    prompt = %{tokens: [1, 2]}
    params = %{max_tokens: 10}
    {:ok, task} = SamplingClient.sample(client, prompt, params)

    # Should complete successfully despite rate limit
    assert {:ok, %{samples: _}} = Task.await(task, 5_000)

    # Should have logged the rate limit
    logs = LogCapture.get_logs()
    assert Enum.any?(logs, fn {level, msg} ->
      level == :warning and
      msg =~ "Sampling is paused" and
      msg =~ "concurrent LoRA rate limit hit"
    end)
  end

  test "does not spam logs for repeated rate limit states" do
    # Similar setup but send multiple try_again responses
    # Verify only one log appears (debouncing works)
  end
end
```

---

#### Test 2.2: End-to-End TrainingClient with Queue State

**File:** `test/tinkex/training_client_integration_test.exs`

```elixir
defmodule Tinkex.TrainingClientIntegrationTest do
  use Tinkex.HTTPCase, async: false

  test "automatically logs when hitting capacity limit during forward_backward" do
    # Similar to sampling test but for training operations
    # Verify "Training is paused" message appears
    # Verify "concurrent models rate limit hit" appears
  end
end
```

---

### Phase 3: Telemetry Integration Tests

#### Test 3.1: Verify Telemetry Events Fire Alongside Observer

**File:** `test/tinkex/telemetry_integration_test.exs`

```elixir
defmodule Tinkex.TelemetryIntegrationTest do
  use Tinkex.HTTPCase, async: false

  test "emits telemetry event and calls observer on queue state change" do
    handler_id = attach_telemetry([[:tinkex, :queue, :state_change]])

    # ... trigger queue state change via SamplingClient or TrainingClient ...

    # Verify telemetry event
    assert_receive {:telemetry, [:tinkex, :queue, :state_change], %{},
                    %{queue_state: :paused_rate_limit, request_id: _}}

    # Verify observer was also called (check logs)
    assert_receive {:log_captured, :warning, msg}
    assert msg =~ "paused"

    :telemetry.detach(handler_id)
  end
end
```

---

### Phase 4: Property-Based Tests

#### Test 4.1: Debouncing Invariants

**File:** `test/tinkex/sampling_client_property_test.exs`

```elixir
defmodule Tinkex.SamplingClientPropertyTest do
  use ExUnit.Case
  use PropCheck

  property "logs at most once per 60-second window regardless of event count" do
    forall events <- list({queue_state(), timestamp()}) do
      # Group events by 60-second windows
      # Verify each window has at most one log
    end
  end

  defp queue_state do
    oneof([:paused_rate_limit, :paused_capacity, :unknown])
  end

  defp timestamp do
    pos_integer()
  end
end
```

---

### Phase 5: Documentation Tests (Doctests)

**File:** `lib/tinkex/queue_state_observer.ex`

```elixir
defmodule Tinkex.QueueStateObserver do
  @moduledoc """
  Behaviour for modules that want to react to queue-state transitions.

  ## Usage

  Both `Tinkex.SamplingClient` and `Tinkex.TrainingClient` implement this
  behaviour automatically and log human-readable warnings when queue states
  change (e.g., hitting rate limits or capacity issues).

  ## Example: Custom Observer

      defmodule MyCustomObserver do
        @behaviour Tinkex.QueueStateObserver

        @impl true
        def on_queue_state_change(:paused_rate_limit) do
          # Custom logic: maybe send metric to monitoring system
          MyMetrics.increment("queue.rate_limited")
        end

        def on_queue_state_change(:paused_capacity) do
          MyMetrics.increment("queue.capacity_limited")
        end

        def on_queue_state_change(_), do: :ok
      end

  Pass your observer to operations:

      {:ok, task} = SamplingClient.sample(client, prompt, params,
        queue_state_observer: MyCustomObserver
      )

  ## Built-In Observers

  By default, both client modules log warnings automatically:

  **SamplingClient:**

      iex> # (When rate limit hit)
      iex> # WARNING: Sampling is paused for sampler abc-123. Reason: concurrent LoRA rate limit hit

  **TrainingClient:**

      iex> # (When capacity hit)
      iex> # WARNING: Training is paused for model-xyz. Reason: out of capacity

  Logs are debounced to once per 60 seconds to avoid spam.
  """

  # ... rest of implementation ...
end
```

---

## Part 6: Refactoring Opportunities

### 6.1 Shared Observer Logic

Both SamplingClient and TrainingClient have nearly identical debouncing logic. Extract to a shared module:

**File:** `lib/tinkex/queue_state_logger.ex`

```elixir
defmodule Tinkex.QueueStateLogger do
  @moduledoc """
  Shared debounced logging logic for queue state observers.

  Implements the 60-second debounce window and human-readable message
  generation used by both SamplingClient and TrainingClient.
  """

  require Logger

  @log_interval_ms 60_000

  defstruct last_logged_at: nil

  @type t :: %__MODULE__{
    last_logged_at: integer() | nil
  }

  @doc """
  Create a new logger state.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Maybe log a queue state change, respecting debounce interval.

  Returns updated logger state.
  """
  @spec maybe_log(t(), atom(), keyword()) :: t()
  def maybe_log(logger, :active, _opts), do: logger

  def maybe_log(logger, queue_state, opts) do
    now = System.monotonic_time(:millisecond)

    should_log =
      case logger.last_logged_at do
        nil -> true
        last -> now - last >= @log_interval_ms
      end

    if should_log do
      do_log(queue_state, opts)
      %{logger | last_logged_at: now}
    else
      logger
    end
  end

  defp do_log(queue_state, opts) do
    client_type = Keyword.fetch!(opts, :client_type)  # :sampling or :training
    context = Keyword.fetch!(opts, :context)  # e.g., session_id or model_id

    reason = humanize_reason(queue_state, client_type)
    action = action_verb(client_type)

    Logger.warning("#{action} is paused for #{context}. Reason: #{reason}")
  end

  defp humanize_reason(:paused_rate_limit, :sampling), do: "concurrent LoRA rate limit hit"
  defp humanize_reason(:paused_rate_limit, :training), do: "concurrent models rate limit hit"
  defp humanize_reason(:paused_capacity, _), do: "out of capacity"
  defp humanize_reason(:unknown, _), do: "unknown"
  defp humanize_reason(_, _), do: "unknown"

  defp action_verb(:sampling), do: "Sampling"
  defp action_verb(:training), do: "Training"
end
```

**Refactored SamplingClient:**

```elixir
defmodule Tinkex.SamplingClient do
  # ... existing code ...

  alias Tinkex.QueueStateLogger

  @impl true
  def init(opts) do
    state = %{
      # ... existing fields ...
      queue_state_logger: QueueStateLogger.new()
    }
    {:ok, state}
  end

  @impl true
  def handle_cast({:queue_state_change, queue_state}, state) do
    logger = QueueStateLogger.maybe_log(
      state.queue_state_logger,
      queue_state,
      client_type: :sampling,
      context: "sampler #{state.sampling_session_id}"
    )

    {:noreply, %{state | queue_state_logger: logger}}
  end
end
```

---

### 6.2 Configuration Options

Allow users to customize debounce interval and disable auto-logging:

```elixir
config :tinkex,
  queue_state_logging: [
    enabled: true,
    debounce_ms: 60_000,
    log_level: :warning
  ]
```

---

## Part 7: Migration Guide for Users

### 7.1 Current Behavior (Before Implementation)

**Elixir users must manually set up telemetry handlers:**

```elixir
# Attach telemetry handler to see queue state changes
:telemetry.attach(
  "my-queue-state-logger",
  [:tinkex, :queue, :state_change],
  fn _event, _measurements, metadata, _config ->
    Logger.warning("Queue state changed to #{inspect(metadata.queue_state)}")
  end,
  nil
)

# Create client
{:ok, client} = SamplingClient.start_link(
  config: config,
  session_id: session_id,
  base_model: "Qwen/Qwen2.5-7B"
)

# Sample
{:ok, task} = SamplingClient.sample(client, prompt, params)
```

---

### 7.2 New Behavior (After Implementation)

**Automatic logging with no setup required:**

```elixir
# Create client - now automatically logs queue state changes
{:ok, client} = SamplingClient.start_link(
  config: config,
  session_id: session_id,
  base_model: "Qwen/Qwen2.5-7B"
)

# Sample - if rate limited, will automatically log:
# WARNING: Sampling is paused for sampler abc-123. Reason: concurrent LoRA rate limit hit
{:ok, task} = SamplingClient.sample(client, prompt, params)
{:ok, response} = Task.await(task)
```

**Custom observers still supported:**

```elixir
defmodule MyObserver do
  @behaviour Tinkex.QueueStateObserver

  @impl true
  def on_queue_state_change(queue_state) do
    MyMetrics.record("queue_state", queue_state)
  end
end

# Pass custom observer (replaces built-in logging)
{:ok, task} = SamplingClient.sample(client, prompt, params,
  queue_state_observer: MyObserver
)
```

---

## Part 8: Success Criteria

### 8.1 Functional Requirements

- [ ] SamplingClient implements `Tinkex.QueueStateObserver` behaviour
- [ ] TrainingClient implements `Tinkex.QueueStateObserver` behaviour
- [ ] Both clients log human-readable warnings on queue state changes
- [ ] Messages match Python SDK format and content
- [ ] Debouncing works (max one log per 60 seconds per client)
- [ ] Active state does not trigger logs
- [ ] Telemetry events continue to fire alongside observer callbacks
- [ ] Users can still inject custom observers via opts

---

### 8.2 Test Coverage

- [ ] Unit tests for observer callback logic (>95% coverage)
- [ ] Integration tests for end-to-end queue state handling
- [ ] Property tests for debouncing invariants
- [ ] Doctests in module documentation
- [ ] Tests pass in CI/CD

---

### 8.3 Documentation

- [ ] Update `Tinkex.QueueStateObserver` moduledoc with examples
- [ ] Add "Queue State Monitoring" section to README
- [ ] Document migration path from manual telemetry to automatic logging
- [ ] Add CHANGELOG entry for new feature
- [ ] Update API docs with behaviour implementation notes

---

### 8.4 Parity Verification

**Manual Testing Checklist:**

1. [ ] Start SamplingClient and hit rate limit
   - **Python:** `WARNING  Sampling is paused for sampler <id>. Reason: concurrent LoRA rate limit hit`
   - **Elixir:** Should match (same message, same frequency)

2. [ ] Start TrainingClient and hit capacity limit
   - **Python:** `WARNING  Training is paused for <model-id>. Reason: out of capacity`
   - **Elixir:** Should match

3. [ ] Rapid queue state changes (simulate 10 changes in 5 seconds)
   - **Python:** Logs once, then silence for 60s
   - **Elixir:** Should match

4. [ ] Custom observer injection
   - **Python:** Passes observer to `_APIFuture`
   - **Elixir:** Passes observer to `Future.poll`
   - Both should receive callbacks

---

## Part 9: Open Questions & Design Decisions

### 9.1 Observer Injection Strategy

**Question:** Should observers be module-based (current Elixir) or instance-based (current Python)?

**Python Approach:**
- Each client instance **is** an observer (implements `QueueStateObserver`)
- Observer has access to instance state (`self._sampling_session_id`, `self._last_queue_state_logged`)
- Simple to use but couples observer to client lifecycle

**Current Elixir Approach:**
- Observer is a **module** (behaviour implementer)
- Module is stateless (callbacks are pure functions)
- State must be tracked externally (e.g., Agent, GenServer, process dictionary)

**Recommended Hybrid:**
- Keep module-based for user-provided observers (flexibility)
- Use internal GenServer cast for built-in observers (access to state)
- Document both patterns

---

### 9.2 Telemetry vs Observer Priority

**Question:** If both telemetry handlers and observers are attached, which fires first?

**Current Behavior:**
```elixir
:telemetry.execute(@queue_state_event, %{}, metadata)
notify_observer(state.observer, queue_state)
```

Telemetry fires first, then observer. This is good because:
- Telemetry is fire-and-forget
- Observer might crash (logged and ignored)
- Telemetry always succeeds

**Decision:** Keep current order. Document that telemetry is more reliable for monitoring.

---

### 9.3 Debounce Interval Configuration

**Question:** Should debounce interval be configurable?

**Options:**
1. **Hardcoded 60s** (current Python approach)
   - Simple, predictable
   - Users can't override

2. **Application config** (`:tinkex, :queue_state_log_interval`)
   - Global setting
   - Affects all clients

3. **Per-client option** (`SamplingClient.start_link(queue_state_log_interval: 30_000)`)
   - Maximum flexibility
   - More complex API

**Recommendation:** Start with hardcoded 60s (match Python), add application config in later release if users request it.

---

### 9.4 Log Level

**Question:** Should queue state warnings always be `:warning` level?

**Python:** Always uses `logger.warning()`

**Elixir Options:**
1. Always `:warning` (match Python)
2. Configurable via `Application.get_env(:tinkex, :queue_state_log_level, :warning)`
3. Different levels for different states (`:info` for active, `:warning` for paused)

**Recommendation:** Always `:warning` to match Python. These are genuine issues users need to see.

---

## Part 10: Risk Analysis

### 10.1 Breaking Changes

**Risk:** LOW

- Adding behaviour implementation to existing modules is backward-compatible
- Existing code continues to work (telemetry still fires)
- New automatic logging is additive, not destructive

**Mitigation:** None needed - this is a pure feature add

---

### 10.2 Performance Impact

**Risk:** LOW

- Observer callback adds one GenServer cast per queue state change
- Queue state changes are rare (only during rate limiting/capacity issues)
- Debouncing prevents log spam
- Logger.warning is asynchronous (non-blocking)

**Mitigation:** Already minimal. Could add feature flag if concerns arise.

---

### 10.3 Testing Complexity

**Risk:** MEDIUM

- Need to mock time for debounce tests
- Need log capture infrastructure
- Integration tests require simulating 408 responses

**Mitigation:**
- Use existing `Tinkex.HTTPCase` test helpers
- Build reusable LogCapture module
- Document time mocking patterns

---

### 10.4 Documentation Drift

**Risk:** MEDIUM

- Current docs claim "Training and Sampling clients can implement this behaviour"
- After implementation, need to update to "Training and Sampling clients **do** implement this behaviour"
- Examples in docs will need updating

**Mitigation:** Include doc updates in PR review checklist

---

## Conclusion

This gap represents a **significant user experience difference** between Python and Elixir SDKs. Python users get automatic, human-friendly feedback when hitting rate limits or capacity issues. Elixir users currently see silence unless they manually attach telemetry handlers.

**The infrastructure exists** (QueueStateObserver behaviour, Future.poll integration, telemetry events) but **the client implementations are missing**. This is a straightforward TDD exercise:

1. Write tests for expected behavior (RED)
2. Implement observer callbacks in clients (GREEN)
3. Extract shared logic to QueueStateLogger module (REFACTOR)

**Estimated Effort:** 2-3 days for complete TDD implementation + testing + documentation.

**User Impact:** HIGH - Dramatically improves observability and debugging experience for production workloads.
