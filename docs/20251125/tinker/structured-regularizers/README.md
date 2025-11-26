# Structured Regularizers for Tinker Custom Loss (Design Doc)

## Context
- Python Tinker currently has a custom loss hook in `TrainingClient.forward_backward_custom[_async]`:
  - Flow: forward → get logprobs → user callback `(data, logprobs)` → single scalar loss + metrics → `loss.backward()` → send linearized grads as weights via `forward_backward`.
  - Limitations: single monolithic callback, synchronous execution, no per-regularizer telemetry, under-documented.
- Tinkex (Elixir) deliberately deferred custom loss; there is no equivalent hook.
- Issue intent: make custom loss first-class with structured regularizers, async support, and richer telemetry.

## Goals (Python implementation)
1. Structured regularizer composition: allow multiple named regularizers with independent weights instead of a monolithic callback.
2. Async-capable callbacks: support async regularizers; thread/pool offload is optional (can be deferred).
3. Telemetry: return per-regularizer metrics (value, weight, contribution, custom metrics) plus totals.
4. Backward-compatibility: keep existing single-callback custom loss working.
5. Documentation: update API docs with examples and contracts.

Non-goals (for this pass)
- No new transport/protocol; reuse the current “client computes grads on logprobs, server consumes weights” pattern.
- No automatic ablation runner; users can toggle regularizers via config.
- Optional: skip thread/process pool offload if time-boxed; async callables alone partially address the “async” ask.

## Proposed API (Python)
Extend `forward_backward_custom`/`forward_backward_custom_async` to accept:
```python
def forward_backward_custom(
    data: List[Datum],
    base_loss_fn: CustomLossFnV1 | None = None,        # existing single loss hook (optional)
    regularizers: List[Dict] | None = None,            # new
) -> APIFuture[ForwardBackwardOutput]
```

Regularizer spec (per entry):
```python
{
  "fn": Callable[[List[Datum], List[Tensor]], Tuple[Tensor, Dict[str, float]]],  # accepts (data, logprobs)
  "weight": float,
  "name": str
}
```
- `fn` may be `async` or sync; if async, await it. (Thread/pool offload is optional; see below.)
- `base_loss_fn` remains the legacy single callback (optional); if omitted, base loss = 0 and only regularizers contribute.
- Backward-compat: if `regularizers` is None and `base_loss_fn` provided, behave exactly like today.

Loss composition:
```
loss_total = (base_loss or 0) + Σ (weight_i * loss_i)
```
Then `loss_total.backward()` as today; collect grads on logprobs and feed back via `forward_backward`.

Telemetry (returned in ForwardBackwardOutput.metrics):
```json
{
  "loss_total": ...,
  "regularizers": {
    "<name>": {
      "value": <float>,           // raw loss_i
      "weight": <float>,
      "contribution": <float>,    // weight * value
      "custom": { ...metrics from fn... }
    }
  },
  "regularizer_total": <float>
}
```
- Optionally add `grad_norm` per regularizer if readily available.
- Merge with any metrics returned by `base_loss_fn` (e.g., under `metrics["base_loss"]`).

Async support:
- Accept async regularizer fns; `await` them.
- Optional: add a `run_in_executor: bool` flag per regularizer to offload sync fns to a thread/process pool (can be deferred).

Docs:
- Update `docs/api/trainingclient.md` with:
  - Signature + types for `regularizers`.
  - Example with multiple regularizers (topology + sparsity).
  - Telemetry shape.
  - Note on async regularizers; if run-in-executor is added, document the flag.

Tests:
- Multiple regularizers composed; metrics include per-regularizer values and totals.
- Async regularizer returns awaited value.
- Backward-compat: old single-callback path still works.

## Implementation sketch (Python)
File: `src/tinker/lib/public_interfaces/training_client.py`
1) Update `forward_backward_custom` / `_async` signatures to accept `base_loss_fn` + `regularizers`.
2) After forward → logprobs, run:
   - If `base_loss_fn`: compute `(base_loss, base_metrics)`.
   - For each regularizer: run (await if needed), collect `(loss_i, metrics_i)`.
3) Compose `loss_total` and call `loss_total.backward()`.
4) Build telemetry struct (per-regularizer + totals + base metrics) and merge into the returned metrics.
5) Reuse the existing linearized-gradients path to send weights via `forward_backward`.
6) Keep backward compat: when `regularizers` is None, behave exactly as current.
7) Add tests and docs.

Optional executor offload:
- Add a per-regularizer flag `run_in_executor: bool`; if true, run sync fns in a thread/process pool. This is incremental and can be deferred.

## Mapping to issue ask
- Structured regularizer composition: ✅ (multiple named regularizers, weights, telemetry).
- Async support: ✅ for async callables; thread/pool offload is optional (mark as follow-up if not included).
- Telemetry: ✅ per-regularizer + totals, namespaced.
- Public API/docs: ✅ with the docs update/examples.
- Backward compatibility: ✅ existing single-callback API remains.

## Open questions / follow-ups
- Do we need grad norms per regularizer? (nice-to-have)
- Do we add run-in-executor now or defer? (trade latency vs complexity)
- Should we expose a higher-level config object (e.g., `training_config` dict) or keep function args? (recommend args for minimal change)

## Tinkex implications
- Tinkex currently has no custom loss hook. Once Python ships structured regularizers, we can decide:
  - Add a similar hook in Tinkex using Nx/EXLA autograd, or
  - Require user-provided gradients (weights) and skip Nx, or
  - Defer to Python for custom-loss training and keep Tinkex for standard losses.

