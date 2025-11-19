Here’s what I see after diffing your port docs against the Python repo you pasted.

I’ll start with **clear, objective mismatches with the Python code**, then call out **intentional-but-different behavior**, and finally **internal inconsistencies inside the docs themselves**.

---

## 1. Clear type / enum mismatches

### 1.1 `StopReason` values

**Plan / docs**

* In multiple places (e.g. `01_type_system.md`, and Round 10 in `00_overview.md`) you say:

> StopReason enum: `"max_tokens" | "stop_sequence" | "eos"`

and show a `StrEnum`-style enum with those three values.

**Python code**

* In `tinker/types/stop_reason.py` you actually have:

```python
StopReason: TypeAlias = Literal["length", "stop"]
```

So:

* Python wire values are `"length"` and `"stop"` (only two values).
* Your port docs assume completely different values and an extra `"eos"` case.

**Impact**

* Any Elixir type or pattern matching based on `"max_tokens" | "stop_sequence" | "eos"` will not match the real API coming from this code snapshot.
* Your Round-10 “✅ Correct” bullet in `00_overview.md` about `StopReason` is **not correct for this repo**.

You’ll need to either:

* Update the docs to reflect `"length" | "stop"` (if that is still what the server emits), **or**
* Verify that the Python package you actually target *really* uses `"max_tokens" | "stop_sequence" | "eos"` now (and that this Repomix snapshot is from an older version).

Right now there’s a hard discrepancy.

---

### 1.2 Request error categories: doc still has stale names in places

**Plan / docs**

You’ve clearly converged on:

* Enum: `RequestErrorCategory(Unknown, Server, User)`
* Wire format: lowercase `"unknown" | "server" | "user"` (thanks to a patched `StrEnum.auto()`), and you show a correct Elixir parser for lowercase strings in `01_type_system.md`.

But in `05_error_handling.md` under “Python Exception Hierarchy” you still have:

```python
class RequestFailedError(TinkerError):
    """Server reported operation failed"""
    def __init__(
        self,
        message: str,
        *,
        request_id: str,
        error_category: RequestErrorCategory,
        details: dict | None = None,
    ):
        ...
        self.error_category = error_category  # USER_ERROR | TRANSIENT | FATAL
```

And later you define an Elixir parser for **capitalized** strings:

```elixir
def parse("Unknown"), do: :unknown
def parse("Server"),  do: :server
def parse("User"),    do: :user
```

**Python code**

* `tinker/types/request_error_category.py`:

```python
class RequestErrorCategory(StrEnum):
    Unknown = auto()
    Server = auto()
    User   = auto()
```

* `_types.py` holds the plumbing for `StrEnum`; we don’t see the implementation here, so we **can’t** confirm from this snippet whether the values are `"Unknown"` or `"unknown"`. Your docs assert that `_types.py` lowercases them.

**Inconsistencies**

* The comment `"USER_ERROR | TRANSIENT | FATAL"` is definitely stale relative to the current enum (`Unknown/Server/User`).
* You have **two different Elixir parsers** in your docs:

  * One for `"Unknown"/"Server"/"User"` (capitalized, `05_error_handling.md`)
  * One for `"unknown"/"server"/"user"` (lowercase, `01_type_system.md` + Round-10 overview)

At least one of those parsers is wrong for the real wire format.

**Action**

* Confirm from the *actual* runtime (or `_types.StrEnum` implementation) whether values are `"Unknown"` or `"unknown"`.
* Then delete the wrong parser and update 05_error_handling’s text (remove the `USER_ERROR/TRANSIENT/FATAL` comment and the capitalized parser if you stick with lowercase wire values).

---

### 1.3 `FutureRetrieveResponse` shape

**Plan / docs**

In `01_type_system.md` you present a *single* response type:

```python
class FutureRetrieveResponse(BaseModel):
    status: str  # "pending" | "completed" | "failed"
    result: Optional[Dict[str, Any]] = None
    error: Optional[RequestFailedResponse] = None
```

Later (Rounds 9/10) you discuss `TryAgainResponse` and queue-state handling as a separate type.

**Python code**

* In `tinker/types/future_retrieve_response.py` you have:

```python
FutureRetrieveResponse: TypeAlias = Union[
    ...
]
```

i.e. it’s a **union of several concrete types**, one of which is `TryAgainResponse` from `tinker/types/try_again_response.py`:

```python
class TryAgainResponse(BaseModel):
    type: Literal["try_again"] = "try_again"
    request_id: str
    queue_state: Literal["active", "paused_capacity", "paused_rate_limit"]
```

And `_APIFuture._result_async` in `lib/api_future_impl.py` clearly branches on these shapes (we see `QueueState` and queue_state mapping).

**Mismatch**

* Your early `FutureRetrieveResponse` struct is a simplification that no longer matches the actual type alias in the Python code.
* Later docs (03_async_model / 07_porting_strategy) *do* talk about `TryAgainResponse` explicitly, so this fragment is just stale.

**Impact**

* If you implement the Elixir types exactly as in `01_type_system` (single struct with `status/result/error`) you’ll miss the `"type": "try_again"` variant entirely.
* The rest of the plan correctly expects a separate `TryAgainResponse` type, so `01_type_system` should be updated to match the union the Python SDK actually uses.

---

### 1.4 TensorData / `from_nx` story is inconsistent inside the docs

**Plan / docs**

You have *two* different Elixir `TensorData.from_nx/1` implementations:

1. In `01_type_system.md` (Round 3 “Tensor Conversion with Aggressive Casting”), you include a version that:

   * Detects `{:f, 64}`, `{:f, 32}`, `{:s, 32}`, `{:s, 64}`, `{:u, _}`.
   * Calls `Nx.as_type/2` to actually **cast** tensors to a supported backend dtype before flattening.
   * Sets `dtype` based on the *casted* dtype.

2. In `07_porting_strategy.md` (“Nx Integration”), you have a simpler snippet:

   ```elixir
   def from_nx(%Nx.Tensor{} = tensor) do
     %__MODULE__{
       data: Nx.to_flat_list(tensor),
       dtype: nx_dtype_to_tensor_dtype(tensor.type),
       shape: Tuple.to_list(tensor.shape)
     }
   end

   defp nx_dtype_to_tensor_dtype({:f, 32}), do: :float32
   defp nx_dtype_to_tensor_dtype({:f, 64}), do: :float32  # Downcast to float32
   defp nx_dtype_to_tensor_dtype({:s, 32}), do: :int64    # Upcast to int64
   defp nx_dtype_to_tensor_dtype({:s, 64}), do: :int64
   ```

   This **does not** call `Nx.as_type/2`; it just labels the dtype as float32/int64 while leaving the tensor’s runtime type untouched.

**Python code**

* `tinker/types/tensor_data.py` uses `_convert_numpy_dtype_to_tensor` and similar helpers to aggressively cast NumPy/torch dtypes so only `"int64"` and `"float32"` are emitted. That’s the behavior you are trying to mirror.

**Inconsistency**

* One Elixir snippet correctly mirrors the Python casting behavior (actually converting the tensor before serializing).
* The other only *relabels* the dtype without converting the underlying Nx tensor.

**Impact**

* If you implement the 07_porting version, you still send JSON numbers, so the backend *probably* accepts them, but:

  * It no longer exactly mirrors Python’s conversion rules.
  * Your own `to_nx/1` round-trip can become inconsistent.

**Action**

* Pick one canonical implementation (the “aggressive cast + Nx.as_type” one from `01_type_system.md` is closer to the Python semantics) and delete the outdated snippet from `07_porting_strategy.md` to avoid confusion.

---

### 1.5 Minor doc/code mismatches in error docs

In `05_error_handling.md`:

* The text around `RequestFailedError` still mentions legacy categories `USER_ERROR/TRANSIENT/FATAL`, while the codebase uses `Unknown/Server/User` (`tinker/types/request_error_category.py`). You’ve fixed this conceptually later in the doc, but the snippet itself is wrong.
* The Elixir `RequestErrorCategory` example in 05 expects `"Unknown"/"Server"/"User"` as *wire* values, while `01_type_system` later shows a different parser that expects lowercase `"unknown"/"server"/"user"`. That’s self-contradictory (see 1.2).

These are mostly documentation drift, but they *will* leak into the port if you copy/paste the wrong example.

---

## 2. Behavioral differences vs Python (probably intentional, but worth surfacing)

These aren’t “bugs” in your plan per se, but they are **real divergences** from the Python SDK that you should double-check you actually want.

### 2.1 `Retry-After` HTTP date support

**Python**

* `_base_client.BaseClient._parse_retry_after_header` supports:

  * `retry-after-ms` (milliseconds)
  * `retry-after` numeric seconds (with float support)
  * `retry-after` HTTP date (parsed via `email.utils.parsedate_tz` / `mktime_tz`)

### Plan

* In `04_http_layer.md` you deliberately *do not* support HTTP-date format:

  ```elixir
  # v1.0: supports retry-after-ms and retry-after seconds only.
  # HTTP-date parsing TODO for v2.0 – currently falls back to 1000 ms.
  ```

**Impact**

* If the server ever sends a full HTTP-date `Retry-After`, the Python SDK will honor the actual delay; Tinkex v1.0 will just sleep ~1s.
* That’s a subtle divergence that could matter under heavy rate limiting.

If you’re okay with this as a v1 trade-off, fine — but it is a real discrepancy from Python behavior.

---

### 2.2 SamplingClient retry semantics

**Python** (`lib/public_interfaces/sampling_client.py` + `lib/retry_handler.py`)

* Sampling requests go through both:

  * The shared holder’s `execute_with_retries`, and
  * A `RetryHandler` with `RetryConfig` (max_retries, backoff, jitter, etc.).
* Retryable errors (5xx, 408, 429, `RequestFailedError` with `Server/Unknown` categories, connection errors) are retried automatically.

**Plan**

* In `02_client_architecture.md` and `04_http_layer.md` you explicitly choose to:

  * Use a shared ETS-backed `RateLimiter` keyed by `{base_url, api_key}`.
  * Set `max_retries: 0` for sampling HTTP calls.
  * Have `SamplingClient.sample/…` **not** auto-retry 429s or 5xxs; it returns `{:error, %Tinkex.Error{}}` and relies on callers to wrap their own retry logic.
* You document this explicitly as an “intentional divergence” from Python.

**Impact**

* With the Elixir SDK, callers need to explicitly wrap sampling in their own retry loop if they want parity with Python’s `RetryHandler`.
* Training/futures will behave closer to Python; sampling will be “fail fast”.

This is fine if it’s a conscious UX decision, but it absolutely is a discrepancy with the Python client.

---

### 2.3 Streaming support

**Python**

* `_streaming.py` + `_response.py` implement proper SSE handling, buffered by `SSEDecoder` / `AsyncStream`, and are used via `.with_streaming_response`.

**Plan**

* `04_http_layer.md` includes a streaming sketch using `Finch.stream/…`, but marks it **explicitly non-production** (no buffer management, accumulates all data, assumes complete events per chunk).
* You also state v1.0 does **not** support streaming officially.

**Impact**

* Python users can use the official streaming API; Elixir v1.0 users cannot.
* Anyone porting examples that rely on streaming will be surprised unless the docs are very explicit.

You already flag this, but from a parity perspective this is one of the larger behavioral gaps.

---

### 2.4 Metrics reduction edge case

Your Elixir `Tinkex.MetricsReduction.reduce/1` is very close to Python’s `chunked_fwdbwd_helpers._metrics_reduction`, but there’s one subtle difference:

**Python**

* `_metrics_reduction` iterates over `keys = results[0].metrics.keys()` and then unconditionally reads `m.metrics[key]` for every `m` in `results`.
* If any chunk is missing a metric key present in the first chunk, you’ll get a `KeyError` and the training run blows up (which is arguably correct: metrics are expected to be consistent across actors).

**Plan**

* In `Tinkex.MetricsReduction.reduce/1` you guard with:

  ```elixir
  if Enum.all?(results, fn r -> Map.has_key?(r.metrics, key) end) do
    ...
  else
    acc
  end
  ```

  i.e. you **silently drop** metrics that aren’t present in all results instead of crashing.

**Impact**

* Elixir is more forgiving: inconsistent metrics across chunks will just vanish from the merged metrics instead of raising.
* This is *safer*, but not identical to Python semantics.

If strict parity is important, you might want to log or raise instead of silently skipping.

---

## 3. Internal documentation inconsistencies (no direct code mismatch, but could leak into the port)

These are issues where different docs contradict each other even if the Python code is fine.

1. **RequestErrorCategory wire format**

   * 01_type_system + 00_overview Round 10 say wire values are lowercase (`"unknown"/"server"/"user"`) and show a lowercase parser.
   * 05_error_handling shows a capitalized parser and mentions old category names.
   * Make one canonical story and delete the other to avoid copy-pasting the wrong parser into Elixir.

2. **FutureRetrieveResponse shape**

   * 01_type_system shows a single struct with `status/result/error`.
   * 03_async_model + 07_porting_strategy talk about `TryAgainResponse` and queue_state.
   * The actual Python type is a union, matching the latter. The early simple struct is stale and should be updated.

3. **TensorData / `from_nx`**

   * As noted above, two different implementations are given; choose the “cast then serialize” one.

4. **Error categories naming**

   * 05_error_handling still talks about `USER_ERROR/TRANSIENT/FATAL` in comments even though the enum is now `Unknown/Server/User`.
   * This is just doc drift, but it’s very easy for a future maintainer to reintroduce wrong Elixir atoms (`:transient`, `:fatal`) if they cargo-cult that snippet.

---

## 4. Things that *do* look consistent (for sanity)

Just to confirm: many of the big Round-10 items in `00_overview.md` actually **do** match the Python repo you pasted:

* `AdamParams` defaults: `learning_rate=0.0001`, `beta1=0.9`, `beta2=0.95`, `eps=1e-12` (`tinker/types/optim_step_request.py`).
* `LossFnType`: exactly `{"cross_entropy","importance_sampling","ppo"}` (`tinker/types/loss_fn_type.py`).
* `TensorDtype`: `"int64" | "float32"` (`tinker/types/tensor_dtype.py`).
* `ForwardBackwardOutput`: `loss_fn_output_type`, `loss_fn_outputs`, `metrics` and **no** standalone `loss` field (`tinker/types/forward_backward_output.py`).
* Image types: `ImageChunk.data`, `ImageAssetPointerChunk.location`, etc. match the docs (`tinker/types/image_chunk.py`, `image_asset_pointer_chunk.py`).
* Telemetry `event_session_index`: `Telemetry._next_session_index` & tests align with your description (`tinker/lib/telemetry.py`, `telemetry_test.py`).
* `TryAgainResponse` + `QueueState` and its use in `_APIFuture` match your Round-9 backpressure description (`tinker/types/try_again_response.py`, `lib/api_future_impl.py`).
* `chunked_fwdbwd_helpers._metrics_reduction` has the same 6 reducers you mirror (`_mean`, `_sum`, `_min`, `_max`, `_slack`, `_unique`).

So the plan is mostly in good shape; the main sharp edge is **StopReason**, plus a few places where older docs haven’t been fully updated (error categories, FutureRetrieveResponse, TensorData.from_nx).

---

### TL;DR

If you fix only a few things, I’d prioritize:

1. **StopReason**: align docs and Elixir types with whatever the *real* wire values are; right now docs and this repo disagree (`"max_tokens"/"stop_sequence"/"eos"` vs `"length"/"stop"`).
2. **RequestErrorCategory**: pick one canonical wire format (probably lowercase) and update *all* Elixir parser examples + comments to match.
3. **TensorData.from_nx**: keep only the “aggressive casting” version that actually calls `Nx.as_type/2`.
4. **FutureRetrieveResponse**: update 01_type_system to reflect the union + `TryAgainResponse`, to match the Python types and your Round-9 async model.

If you want, I can rewrite the affected sections of the markdown to make them internally consistent and aligned with the Python repo.
