# ADR-001: Parity Scope and Counting Method

- **Status:** Accepted
- **Date:** 2025-11-26

## Context
- Prior gap doc overstated parity gaps (~57% complete, 268 gaps) by counting BEAM-irrelevant patterns (async wrappers, Click lazy-loading) and marking implemented features as missing.
- False positives identified:
  - Session heartbeats exist (`lib/tinkex/session_manager.ex`, `lib/tinkex/api/session.ex:55`) though path differs from Python (`/api/v1/session_heartbeat`).
  - Tinker URI parser already present (`lib/tinkex/api/rest.ex:249-269`, reused in `checkpoint_download.ex`).
  - Custom loss / regularizer pipeline already implemented in `lib/tinkex/training_client.ex` and `lib/tinkex/regularizer/*`.
  - Weight save/load endpoints exist (`lib/tinkex/api/weights.ex`); missing pieces are typed responses, not the endpoints.

## Decision
- Re-baseline gap accounting to only include:
  1) Features required for wire compatibility or parity,
  2) Missing types/endpoints affecting API surface,
  3) Safety/validation gaps that change behavior.
- Do not count: Python-specific ergonomics (Click lazy loading, thread executors), BEAM-native alternatives, or already-implemented features.

## Consequences
- Lower, more accurate gap count; critical list centers on serialization, response handling, missing endpoints/types.
- Heartbeat is not a blocker; focus moves to wire-path alignment and type parity.
- Path parsing is complete; avoid duplicative work.
- Custom loss flow is complete; future work should be tests/docs only.

## Evidence
- Elixir heartbeat implementation: `lib/tinkex/session_manager.ex`, `lib/tinkex/api/session.ex:55`.
- Path parsing: `lib/tinkex/api/rest.ex:249-269`.
- Custom loss: `lib/tinkex/training_client.ex` (forward_backward_custom) and `lib/tinkex/regularizer/*`.
- Weights endpoints: `lib/tinkex/api/weights.ex`.
