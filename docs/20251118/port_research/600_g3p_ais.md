The plan is exceptionally thorough and demonstrates a deep understanding of the Elixir ecosystem (OTP, ETS, Finch) and the specific challenges of porting this SDK (Types, Concurrency).

However, comparing the plan against the provided Python source code (`<ct>`), I have identified **three specific behavioral discrepancies** that should be addressed to ensure true parity with the Python SDK.

### 1. `SamplingClient` Retry Behavior Mismatch
**The Issue:**
The plan explicitly disables retries for `SamplingClient`:
> `SamplingClient`: Does NOT use this retry logic! ... Returns `{:error, %{status: 429}}` immediately (no retry) ... User must implement retry if desired.

**The Reality (Python Source):**
In `tinker/lib/public_interfaces/sampling_client.py`, the `sample` method uses `holder.execute_with_retries`:
```python
untyped_future = await self.holder.execute_with_retries(
    _send_request,
    retry_config=retry_config
)
```
The Python SDK **does** automatically retry sampling requests on 500s, 408s, and 429s (respecting backoff).

**Critique:**
By setting `max_retries: 0` in the Elixir `SamplingClient`, you are shifting the burden of transient error handling (e.g., a temporary 503 or 429) to the user. This makes the Elixir SDK significantly more brittle than its Python counterpart.

**Recommendation:**
The `SamplingClient` task should implement a retry loop similar to `Tinkex.API.with_retries`, but integrated with `Tinkex.RateLimiter`.
1.  Check `RateLimiter` (wait if needed).
2.  Attempt Request.
3.  If success -> Return.
4.  If 429 -> Update `RateLimiter`, **Retry** (decrement count).
5.  If 500/408 -> **Retry** (decrement count).
6.  Return error only after retries exhausted.

### 2. Queue State Backpressure Propagation
**The Issue:**
The plan correctly adds handling for `TryAgainResponse` and `QueueState` in `Future.poll/2` to back off the *polling* loop.
> `{:ok, %{status: "try_again", ...}}` -> `notify_queue_state_change(...)` -> `Process.sleep(...)`

**The Reality (Python Source):**
In `tinker/lib/api_future_impl.py` and `tinker/lib/internal_client_holder.py`:
When a `TryAgainResponse` (e.g. `PAUSED_RATE_LIMIT`) is received during polling, the client updates the **shared holder state** (`holder._sample_backoff_until`). This effectively pauses **new** `sample()` submissions from the `SamplingClient` as well.

**Critique:**
In your plan, if `Future.poll` receives a "Paused" signal, it only slows down that specific polling task. The `SamplingClient` (which reads from `RateLimiter` in ETS) remains unaware that the server is paused and will continue submitting new sampling requests, likely exacerbating the server load.

**Recommendation:**
Update `Future.poll/2` to write to the shared `Tinkex.RateLimiter` when it encounters a queue pause signal.
```elixir
# In Future.poll handling TryAgainResponse
case queue_state do
  "paused_rate_limit" ->
    # Block ALL new sampling requests for a short duration
    Tinkex.RateLimiter.for_key(pool_key) 
    |> Tinkex.RateLimiter.set_backoff(5000) # e.g. 5s default
  # ...
end
```

### 3. Slack Metric Reduction Logic
**The Issue:**
In `07_porting_strategy.md`, you implemented a placeholder for the `:slack` metric reduction:
```elixir
defp reduce_slack(values, weights, total_weight) do
  reduce_mean(values, weights, total_weight)
end
```
You noted this was a guess ("treat as weighted mean").

**The Reality (Python Source):**
While the implementation of `_slack` is hidden in the compressed view of `chunked_fwdbwd_helpers.py`, "slack" in ML optimization contexts usually refers to a constraint satisfaction metric (e.g., $C(x) \le 0$).
If the server returns "slack", it is often the *minimum* (worst case violation) or *maximum* (depending on sign convention) that matters, not the mean. 

**Recommendation:**
Since the Python source code implementation is ambiguous in the provided text, **add a TODO** to verify this behavior empirically against the API or assume `:min` (conservative for slack variables) rather than `:mean`, or simply flag this as "Pending Verification" in the final checklist.

### Summary of Required Actions

1.  **Enable Retries in SamplingClient:** Modify `SamplingClient.sample` to loop/retry on transient errors instead of returning immediate error, restoring parity with Python.
2.  **Link Polling to RateLimiter:** Ensure `Future.poll` updates the global `RateLimiter` when it sees `TryAgainResponse`, preventing new sampling submissions during server pauses.
3.  **Verify Slack Reduction:** Mark `reduce_slack` for verification.

With these adjustments, the plan is solid.

