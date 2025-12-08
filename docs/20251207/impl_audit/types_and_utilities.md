# Types & Utilities Audit (AdamParams, TryAgainResponse, Byte Estimation)

**Date:** 2025-12-07  
**Python SDK Commit:** 5ad4282c (`./tinker`)  
**Scope:** Optimizer params, queue backpressure types, byte budgeting utilities

---

## AdamParams

- **Python (`types/optim_step_request.py`)**: `AdamParams` includes **six** fields (`learning_rate`, `beta1`, `beta2`, `eps`, `weight_decay`, `grad_clip_norm`). Defaults match the Elixir port.  
- **Elixir (`types/adam_params.ex`)**: Same six fields, plus stricter validation (positive learning_rate/eps, betas in [0,1), non-negative decay/clip).  
- **Status**: **Parity**. No schema divergence; earlier note about “extra fields in Elixir” was incorrect.

---

## TryAgainResponse

- **Python (`types/try_again_response.py`)**: Schema defines `type`, `request_id`, and `queue_state` only. Queue-state reasons aren’t part of the model, but `_APIFuture` will pass through `queue_state_reason` from 408 responses when present.
- **Elixir (`types/try_again_response.ex`)**: Adds optional `retry_after_ms` and `queue_state_reason`, and normalizes queue_state strings to atoms.
- **Status**: Elixir is a superset; extra fields are optional and safe when absent upstream.

---

## Byte Estimation & Byte Semaphores

- **Python (`lib/internal_client_holder.py`)**:
  - `estimate_bytes_count_in_model_input` and `estimate_bytes_count_in_chunk` use the same 10-bytes-per-token heuristic for text and raw sizes for image chunks.
  - Sampling dispatch uses three semaphores: global (400), throttled (10 during backoff), and a `BytesSemaphore` (5 MB) that blocks until capacity is available.
- **Elixir**:
  - `Tinkex.ByteEstimator` mirrors the Python heuristics (10 bytes per token/tensor element; raw sizes for image chunks).
  - `SamplingDispatch` uses `Tinkex.BytesSemaphore` (5 MB default) plus count semaphores; the byte semaphore allows the budget to dip negative before blocking new acquisitions, whereas Python blocks pre-acquire.
- **Status**: Functional parity with a minor implementation difference in how byte budgets are enforced (Elixir can transiently go negative; Python cannot).

---

## Overall Assessment

- **No critical mismatches** between the Python SDK and the Elixir port for the audited types/utilities.
- Primary corrections from the earlier draft:
  - Python already includes `weight_decay` and `grad_clip_norm`; the Elixir port matches.
  - Python does have byte estimation and a byte semaphore; these are not Elixir-only features.
  - Extra TryAgain fields in Elixir are optional and do not indicate a gap in Python.
