# Training persistence (save/load weights)

**Gap:** Python SDK exposes save/load of training checkpoints (with optimizer) and a convenience to create a training client from saved state; Elixir only supports saving sampler weights and lacks save/load APIs.

- **Python feature set**
  - `TrainingClient.save_state` → `/api/v1/save_weights` (checkpoint naming, returns path).
  - `TrainingClient.load_state` / `load_state_with_optimizer` → `/api/v1/load_weights` (optionally loads optimizer state).
  - `ServiceClient.create_training_client_from_state` rebuilds a training client from a checkpoint (`weights_info` + `load_state`).
  - Types: `SaveWeightsRequest/Response`, `LoadWeightsRequest/Response` (with `optimizer` flag), REST `weights_info` helper.
- **Elixir port status**
  - Types exist (`lib/tinkex/types/save_weights_request.ex`, `save_weights_response.ex`, `load_weights_request.ex`, `load_weights_response.ex`) but no public APIs use them.
  - `Tinkex.TrainingClient` only implements `save_weights_for_sampler`; there is no save/load checkpoint flow or optimizer toggle.
  - `ServiceClient` has no “from state” helper to recreate a training client from `tinker://` weights.
- **Impact**
  - Users cannot persist training checkpoints or resume training in Elixir; optimizer state restore is impossible.
  - Cross-language parity is broken for long-running training or warm-start workflows.
- **Suggested alignment**
  1) Add `Tinkex.API.Weights.save_weights[_typed]` and `load_weights[_typed]` wrappers using existing types, with optional `load_optimizer_state`.
  2) Wire `Tinkex.TrainingClient` calls for `save_state/2`, `load_state/2`, `load_state_with_optimizer/2`, sequencing `seq_id` like other calls.
  3) Add `Tinkex.ServiceClient.create_training_client_from_state/2` that uses `Rest.get_weights_info_by_tinker_path/2` then creates a LoRA training client and calls `load_state*`.
  4) Ensure CLI parity (checkpoint save/load as needed) once APIs exist.
