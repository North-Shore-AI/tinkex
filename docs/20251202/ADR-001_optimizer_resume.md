# ADR-001: Optimizer-state resume helpers

- **Status:** Draft
- **Date:** 2025-12-02

## Context
- Upstream Python added `ServiceClient.create_training_client_from_state_with_optimizer` (+ async) and clarified that the existing helper loads weights only.
- The new helper pulls weights metadata via `get_weights_info_by_tinker_path`, creates a LoRA training client with the correct base model/rank, then loads both weights **and optimizer state**.
- Elixir already supports optimizer restore at the low level:
  - `Tinkex.TrainingClient.load_state_with_optimizer/3` sends `optimizer: true` (`lib/tinkex/types/load_weights_request.ex`).
  - `Tinkex.ServiceClient.create_training_client_from_state/3` can flip `load_optimizer: true` in opts, but there is no first-class `*_with_optimizer` helper and the weights-only/default behavior is not called out.

## Decision
- Add explicit ergonomics matching Python:
  - `Tinkex.ServiceClient.create_training_client_from_state_with_optimizer/3` and `/async` wrappers that set `load_optimizer: true`.
  - Document `create_training_client_from_state/3` as weights-only by default to mirror Python’s clarified contract.
- Keep default behavior (weights-only) unchanged for backward compatibility; optimizer restore requires opting in.

## Consequences
- Parity with Python helpers; less chance of users resuming without optimizer state by accident.
- Minimal surface-area change (thin wrappers) because the transport and request types already carry `optimizer: true`.
- Testing/docs need updates to show both flows and the reset-vs-resume semantics.

## Integration plan (Elixir)
1) Add the new wrappers to `lib/tinkex/service_client.ex`, delegating to the existing handler with `load_optimizer: true`.
2) Update docs/guides (e.g., `docs/guides/training_persistence.md` and CLI docs if applicable) to spell out weights-only vs. weights+optimizer.
3) Add unit/integration coverage that:
   - Ensures `create_training_client_from_state_with_optimizer/3` issues a load request with `optimizer: true`.
   - Confirms weights-only path still defaults to `optimizer: false`.

## Viability
- Transport support already exists (`LoadWeightsRequest.optimizer`, `TrainingClient.load_state_with_optimizer/3`, `ServiceClient.create_training_client_from_state/3` path).
- No server-side changes required; this is ergonomic parity and documentation clarity.
