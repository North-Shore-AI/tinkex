# Training Client Implementation Audit

**Date:** 2025-12-07  
**Python SDK Commit:** 5ad4282c (current `./tinker`)  
**Focus Area:** `TrainingClient` parity for forward/backward and custom loss

---

## Overview

The prior draft assumed the Python SDK had recently added structured regularizer composition, gradient-norm telemetry, and async regularizers. Those features **do not exist** in the current Python codebase. Both SDKs implement the same single custom-loss path, so the Elixir port is not missing those capabilities.

---

## Verified Parity

- **Custom loss flow**:  
  - Python (`training_client.py:343-415`) runs a forward pass, clones logprobs to Torch tensors with `requires_grad_(True)`, calls the user loss_fn, executes `loss.backward()`, and builds linearized gradients for a follow-up backward call. It raises if any `logprob.grad` is `None`.  
  - Elixir (`training_client.ex:874-941` + `training/custom_loss.ex`) runs a forward pass, converts logprobs to Nx tensors, and uses `Nx.Defn.grad/2` on the user loss_fn to generate gradients, then builds the linear loss data for the backward request. Metrics are merged into `ForwardBackwardOutput` in both SDKs. Neither SDK has structured regularizer weighting or gradient-norm reporting.

- **Chunking/byte limits**: Both SDKs chunk training data at `MAX_CHUNK_LEN = 1024` items and an estimated `MAX_CHUNK_BYTES_COUNT = 5_000_000` bytes. Python computes bytes via `InternalClientHolder.estimate_bytes_count_in_model_input()` plus a `len(*data) * 10` heuristic for loss_fn_inputs; Elixir uses `Tinkex.ByteEstimator` with the same 10-bytes-per-element rule.

- **Request ordering**: Python uses `_take_turn` to serialize sends by request_id; Elixir’s GenServer call path serializes sends similarly. Polling remains concurrent in both.

- **Error handling**: Python raises if a gradient is missing; Elixir relies on Nx gradients and does not explicitly assert per-datum gradients. Both wrap failures as request errors.

---

## Small Behavioral Differences

- **Autograd backend**: Python requires Torch tensors in the custom loss_fn; Elixir requires Nx-compatible tensors/ops. That is an ecosystem difference rather than a parity gap.
- **Gradient presence check**: Python enforces `logprob.grad` existence; Elixir does not currently check for missing gradients after differentiation. If a user loss returns a non-differentiable scalar, Elixir will likely surface an Nx error during grad computation rather than a post-check.

---

## Status

No critical gaps were identified between the Python SDK and the Elixir port for `forward/forward_backward/forward_backward_custom`. The earlier high-risk items (structured regularizers, gradient norm tracking, async regularizers, structured metrics schema) were based on incorrect assumptions and are not applicable to the current upstream Python implementation.
