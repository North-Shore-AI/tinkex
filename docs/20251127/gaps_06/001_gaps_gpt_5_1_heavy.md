Here’s what I see missing or meaningfully different in the Elixir port compared to the Python SDK, *excluding* things that are naturally “obviated” by BEAM/OTP (e.g., Python’s thread-pools, asyncio bridges, pydantic, etc.).

I’ll group them by impact.

---

## 1. Custom loss training (major semantic gap)

**Python:**
`TrainingClient.forward_backward_custom` (in `tinker/lib/public_interfaces/training_client.py`) actually **trains the model** with your custom loss:

* Runs a forward pass to get logprobs (`forward_async(..., "cross_entropy")`).
* Wraps those logprobs as `torch.Tensor` with `requires_grad_()`.
* Calls the user’s custom loss function to get a scalar loss and metrics.
* Calls `.backward()` in PyTorch to get gradients w.r.t. logprobs.
* Builds a new synthetic dataset (`linear_loss_data`) whose `loss_fn_inputs["weights"]` carry those gradients.
* Calls `forward_backward_async(linear_loss_data, "cross_entropy")` so the *server* applies that gradient.
* Wraps the result in a `_CombinedAPIFuture` so you still get a normal `ForwardBackwardOutput` with merged metrics.

So: **custom loss -> actual backward pass -> gradients on the server -> usable with `optim_step`**.

**Elixir:**
`Tinkex.TrainingClient.forward_backward_custom/4`:

* Calls `do_forward_for_custom_loss/3` to run a forward pass and collect logprobs (mirroring the first half).
* Then calls `Tinkex.Regularizer.Pipeline.compute/4` with a user-provided loss function and regularizers, using Nx to compute loss and gradient norms.

But:

* It **never calls** `Tinkex.API.Training.forward_backward/…` again with the custom gradients.
* It returns a `Tinkex.Types.CustomLossOutput`, not a `ForwardBackwardOutput`, and doesn’t hook into `optim_step/3`.

So in Elixir, `forward_backward_custom` is currently **an analysis/metrics tool**, not an actual training step that pushes gradients to the backend. That’s a real algorithmic feature gap vs. Python.

---

## 2. File upload & multipart handling

**Python:**

* `_files.py` + `_types.FileTypes` + `to_httpx_files/async_to_httpx_files` give full support for:

  * `FileTypes` unions (paths, bytes, file handles).
  * Multipart encoding with nested “file fields” extracted from request bodies.
  * `file_from_path(path)` helper.

Any resource can accept files and they’ll be converted to `files=...` for httpx with correct content-type and boundaries.

**Elixir:**

* `Tinkex.API` always builds JSON via `Jason.encode!()` on transformed maps (`Tinkex.Transform.transform/2`).
* There’s no Elixir equivalent of `FileTypes`, no multipart builder, no file-extraction helper.

So **generic file upload / multipart support is missing**. If the Tinker API later exposes endpoints that take actual file bodies (beyond current JSON-only endpoints), the Elixir layer can't talk to them yet.

---

## 3. Server capabilities: reduced type information

**Python:**

* `GetServerCapabilitiesResponse` and `SupportedModel` (in `tinker/types/get_server_capabilities_response.py`) model per-model metadata:

  * `supported_models: List[SupportedModel]`
  * Each `SupportedModel` can carry structured fields (`model_name`, and often more in practice: context limits, features, etc.).

**Elixir:**

* `Tinkex.Types.GetServerCapabilitiesResponse` is:

  ```elixir
  defstruct [:supported_models]
  @type t :: %__MODULE__{supported_models: [String.t()]}
  ```

  And `from_json/1` just plucks `model_name` strings or literal names.

So the Elixir type **throws away all per-model structured metadata** and just keeps a list of strings. If downstream callers need things like context limits or capabilities per model, that information is not exposed from Elixir even if the server sends it.

---

## 4. Queue state observer parity

**Python:**

* Defines `QueueState` enum and `QueueStateObserver` in `api_future_impl.py`.
* `SamplingClient` **implements** `QueueStateObserver.on_queue_state_change` and logs human-friendly reasons:

  * `"concurrent LoRA rate limit hit"`, `"out of capacity"`, `"unknown"`.
* `TrainingClient` also implements it with `"concurrent models rate limit hit"` etc.
* These callbacks fire when `_APIFuture` sees `TryAgainResponse.queue_state` change, *in addition to* emitting telemetry.

**Elixir:**

* You have `Tinkex.Types.QueueState` and `Tinkex.QueueStateObserver` behaviour.
* `Tinkex.Future` supports an injected `:queue_state_observer` and emits `[:tinkex, :queue, :state_change]` telemetry.
* **But** neither `Tinkex.SamplingClient` nor `Tinkex.TrainingClient` implements `Tinkex.QueueStateObserver`. They just pass through any observer given in options.

So:

* Python clients *always* adjust/log queue state internally.
* Elixir leaves that completely up to the caller; built-in clients don’t implement the observer behaviour themselves.

If you expect parity where client instances automatically react to queue state transitions (logging, metrics, rate-limit awareness), that wiring is currently missing in the Elixir port.

---

## 5. Generic request-transform engine (annotations vs. ad-hoc)

This is more “shape of implementation” but has feature implications.

**Python:**

* `_transform.py` + `_typing.py` + `_models.BaseModel` use `Annotated[..., PropertyInfo(...)]` metadata to:

  * Automatically rename fields (snake_case → camelCase) via aliases.
  * Apply formats: `"iso8601"`, `"base64"`, `"custom"` on specific fields.
  * Work on nested TypedDicts / models / unions using type inspection.
* Transform happens centrally, driven by type metadata. Anything marked in the type definitions gets transformed consistently.

**Elixir:**

* `Tinkex.Transform` is a much thinner layer:

  ```elixir
  @spec transform(term(), opts()) :: term()
  # opts: aliases: %{from => to}, formats: %{key => :iso8601 | fun}, drop_nil?: boolean()
  ```

* It does:

  * Key aliasing by explicit `aliases` map.
  * Optional formatting via either `:iso8601` or custom functions.
  * Sentinels by `Tinkex.NotGiven`.

* All of the actual protocol-sensitive formatting (e.g., base64 image data, `type` fields, etc.) is handled in each type’s `Jason.Encoder` implementation, not by an annotation system.

So **there’s no equivalent of Python’s type-annotation driven transform engine**. Functionally you’ve reimplemented the specific transforms you needed (images, tensors, etc.), but you do *not* have the generic “attach `PropertyInfo` to a field and the SDK honours it everywhere” capability. If more endpoints/types start relying on that Python metadata, Elixir will need explicit work per type.

---

## 6. Streaming API parity

**Python:**

* `_response.py` + `_streaming.py` support:

  * `.with_streaming_response` on *any* request.
  * `Stream` / `AsyncStream` over SSE or arbitrary chunked/binary responses.
  * `BinaryAPIResponse` / `StreamedBinaryAPIResponse` helpers for binary downloads (e.g., archives) that can stream directly to disk.

**Elixir:**

* `Tinkex.API.StreamResponse` + `Tinkex.API.stream_get/2`:

  * Specific to SSE/event-stream endpoints (GET only).
  * Uses `Tinkex.Streaming.SSEDecoder` to decode a full in-memory response into events; **it doesn't expose a lazy chunked stream coming from Finch** – it builds the enumerable after the GET completes, rather than streaming in the HTTP sense.
* `Tinkex.API.Helpers.with_streaming_response/1` only sets `opts[:response] = :stream`, but `Tinkex.API` doesn’t branch on `:stream` in `handle_response/2` for POST/DELETE, etc.
* For checkpoint downloads, instead of using `API` + streaming response, you have a dedicated `Tinkex.CheckpointDownload` that uses `:httpc` and downloads the whole file (with an optional callback) before extraction.

So relative to Python:

* There’s no general “stream *any* response body from the underlying HTTP client” facility.
* Streaming is scoped to SSE + one checkpoint-download helper, not the generic `with_streaming_response` semantics.

---

## 7. Raw REST “extra_*” extension points

**Python resource methods** (e.g. in `resources/*.py`) accept:

* `extra_headers`
* `extra_query`
* `extra_body`
* `idempotency_key`
* `timeout`

Those all thread through `_base_client` and are merged on top of client defaults.

**Elixir:**

* `Tinkex.API` exposes a single `opts` keyword list; it does support:

  * `:headers` (merged onto default headers).
  * `:idempotency_key` (mapped to `x-idempotency-key` header).
  * `:timeout` per call.
* There’s **no explicit `extra_query` / `extra_body` concept**. All query string handling is ad-hoc (e.g., `"/api/v1/training_runs?limit=#{limit}&offset=#{offset}"`), and there’s no general mechanism to merge user-supplied query parameters into existing paths.

So extension points for “I want to add a weird extra query param/body field to this request without changing the client” are narrower in Elixir.

---

## 8. Proxies & custom HTTP clients

From the Python side:

* `_types.ProxiesTypes` and `_base_client` support setting `proxies` and fully customizing the underlying `httpx.AsyncClient` (including `timeout`, `limits`, `transport`).
* Users can pass `http_client=...` to `AsyncTinker`/`ServiceClient` to use their own client, as long as it implements the expected interface.

In Elixir:

* `Tinkex.Config` has `http_pool :: atom()` to pick which Finch pool to use.
* Pool configuration (size, count) is set in `Tinkex.Application` or via env vars (`TINKEX_POOL_SIZE`, `TINKEX_POOL_COUNT`).
* There is **no public, per-client injection** of an arbitrary HTTP adapter implementing `Tinkex.HTTPClient` – everything ultimately goes through the configured Finch pool.
* There’s also no proxy support exposed in config (no equivalent to `ProxiesTypes` / `HTTP(S)_PROXY` plumbing).

So compared to Python, you’re missing:

* Per-client custom HTTP adapter injection.
* Proxy support at the SDK layer.

---

## 9. REST / CLI ergonomics and output formatting

These are more “nice to have” than protocol features, but still differences:

* Python CLI:

  * Uses `OutputBase` + `rich` tables for nice aligned columns, titles, and JSON output via `--format json`.
  * `tinker run list` / `checkpoint list` implement progress bars when fetching many items (batch pagination).
* Elixir CLI (`Tinkex.CLI`):

  * Prints plain text lines or emits JSON when `--json` flag is used.
  * No rich tables, no progress bars around paginated REST calls.
  * The functional coverage (list/info/publish/unpublish/delete/download + run list/info + version) is there, but the *UX niceties* from Python are not.

From a “feature parity” perspective: table formatting & progress bars are missing, though functionally the commands exist.

---

## 10. Asynchronous convenience methods

In Python, many public methods have both sync and async variants:

* `ServiceClient.create_lora_training_client_async`
* `ServiceClient.create_training_client_from_state_async`
* `ServiceClient.create_sampling_client_async`
* `RestClient` methods with `*_async` variants, etc.

In Elixir:

* You do have some async helpers (`ServiceClient.create_sampling_client_async/2`, `get_server_capabilities_async/1`, `RestClient.*_async/2`, `TrainingClient.*` returning `Task.t()` for operations).
* But not all Python async entrypoints have direct 1:1 analogues (e.g. no `create_lora_training_client_async/…`; instead you’d wrap the sync call in `Task.async` yourself).

Given BEAM’s process model this is less painful (and arguably *is* obviated by OTP), but strictly speaking there are a few **missing convenience functions** vs. the Python set.

---

## 11. Minor type-shape differences

A few places where the Elixir types intentionally drop or compress some fields relative to Python:

* `GetServerCapabilitiesResponse` (discussed above).
* Some telemetry types (e.g., Elixir’s `TelemetryBatch` stores `events` + arbitrary metadata, while Python’s batch is more rigid and some metadata lives in `TelemetrySendRequest` instead). Functionally equivalent, but it means the exact object graph differs.
* `TrainingRun` in Elixir parses timestamps to `DateTime.t()` where possible, whereas Python leaves them as `datetime` objects – fine, but some extra fields that might exist on Python or future server-side types get dropped by `from_map/1` if you don’t extend the struct.

These are mostly safe simplifications, but they are technically “not full fidelity” compared to the Python models.

---

## 12. Things I deliberately *didn’t* count as missing (because BEAM/OTP obviates them)

Just so you know what I intentionally ignored:

* Python’s `asyncify`, thread pools (`asyncio.to_thread` backport), and `AwaitableConcurrentFuture` bridging between `concurrent.futures` and asyncio.
* Pydantic v1/v2 compatibility (`_compat.py`, `StrictBase` vs. `BaseModel` validation paths).
* `sync_only` decorator to prevent calling sync methods in async loops – BEAM doesn’t have that exact footgun.
* Low-level HTTPX details like idempotency headers via `_idempotency_header` vs. how Finch is configured.
* Python-specific tensor helpers (`from_numpy` / `from_torch`) vs. Elixir’s `Nx` integration.

These are genuinely Python-runtime problems that don’t exist in the same way on the BEAM, and the Elixir port solved them via OTP processes, `Task`, ETS, Nx, etc.

---

## Short summary

The most important **real** gaps are:

1. **Custom loss training**: Elixir’s `forward_backward_custom` only computes metrics and gradient norms; it does **not** send custom gradients back to the server the way Python does, so it doesn’t actually train with that loss yet.

2. **No generic multipart/file upload support**: Python has full `_files` machinery; Elixir currently only supports JSON bodies.

3. **Server capabilities and some types are “compressed”**: the Elixir types discard richer nested fields (e.g., `SupportedModel`), exposing only names/strings.

4. **Queue-state observer wiring**: the behaviour exists, but `SamplingClient` / `TrainingClient` don’t implement it the way Python clients do; only external observers see queue-state changes.

5. **HTTP/customization gaps**: Python lets you plug in proxies and custom `httpx` clients; Elixir only lets you choose a Finch pool, no proxies or per-client HTTP adapter injection.

If you want, I can take any one of these (e.g. custom loss training or file uploads) and sketch what an idiomatic Elixir implementation would look like to restore full parity.
