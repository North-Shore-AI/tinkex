# Sync Review Findings (Dec 8, 2025)

Notes from reviewing Python SDK commit `5ad4282c` (“Sync contents”) against the Elixir port.

## 1) Sampling byte semaphore allows budget overshoot (Python)
- **Where:** `src/tinker/lib/internal_client_holder.py` (`BytesSemaphore.acquire`)
- **What:** The guard only waits while `_bytes < 0`, so requests proceed even when the remaining budget is smaller than the requested bytes. Example: budget 5 MB → request 4 MB leaves 1 MB → next request for 2 MB checks `1 < 0` (false), proceeds, and drives `_bytes` to -1 MB before any waiter blocks.
- **Impact:** The intended 5 MB cap on in-flight sampling payloads is not enforced; a single large request or two medium ones can exceed the budget. Downstream throttling is therefore weaker than expected, especially under concurrent load.
- **Fix sketch:** Wait while `_bytes < bytes` (or subtract under the condition lock), and keep the non-cancellable release task. This matches the Elixir `BytesSemaphore.with_bytes/3` behavior, which blocks before consuming budget and only permits negative balance once a backoff penalty is applied explicitly.

## 2) Queue-state reason not surfaced on 429 sampling (Elixir gap vs Python intent)
- **Where:** `lib/tinkex/sampling_client.ex` (`do_sample_once/5`)
- **What:** On `{:error, %Error{status: 429}}` we set size-based backoff but do not propagate the server’s `queue_state` / `queue_state_reason` to the `QueueStateObserver`. Telemetry and logs therefore miss server-provided pause reasons during backoff.
- **Impact:** Users lose visibility into why sampling paused; Python emits reasoned warnings (and the observer receives the reason) on queue transitions coming from `TryAgainResponse`.
- **Fix sketch:** Extract queue state + reason from the 429 response body (if present), emit telemetry/observer callbacks (or call `QueueStateLogger`) before invoking `SamplingDispatch.set_backoff/2`.

## 3) Capacity message wording diverges from Python
- **Where:** `lib/tinkex/queue_state_logger.ex`
- **What:** Default capacity message is `"Tinker backend is running short on capacity"`; Python’s warning appends “, please wait”.
- **Impact:** Minor UX mismatch; Elixir instructions tell users to wait but the log line omits it unless the server sends a reason.
- **Fix sketch:** Either append the clause or rely on server-provided `queue_state_reason` once (2) is addressed.
