# ADR-004: API Endpoint and Type Parity

- **Status:** Accepted
- **Date:** 2025-11-26

## Context
- Confirmed missing or divergent API surfaces:
  - Service: no `/api/v1/healthz` or `/api/v1/get_server_capabilities` in Elixir (`lib/tinkex/api/service.ex`), present in Python `resources/service.py:14-56`.
  - Sampling client lacks `compute_logprobs` while Python exposes it (`lib/public_interfaces/sampling_client.py:65-116`).
  - Weight responses: Elixir lacks typed structs for `SaveWeightsResponse`, `SaveWeightsForSamplerResponse`, `LoadWeightsResponse`; only requests exist.
  - Training run list/info types (`training_run.py`, `training_runs_response.py`) missing in `lib/tinkex/types/`.
  - Session heartbeat path differs: Elixir uses `/api/v1/heartbeat`, Python uses `/api/v1/session_heartbeat`.

## Decision
- Add capability and health endpoints to `Tinkex.API.Service` (and clients as needed).
- Implement `compute_logprobs` in `Tinkex.SamplingClient` or document as unsupported; target parity recommended.
- Add typed response structs for weight save/load operations and wire them into clients.
- Port training run types and expose list/info helpers to match Python REST surface.
- Decide on heartbeat path: either switch to `/api/v1/session_heartbeat` or document/server-route alias; treat as compatibility, not a missing feature.

## Consequences
- Brings Elixir surface in line with Python for monitoring and discovery.
- Weight operations gain typed results for downstream code and CLI outputs.
- Sampling client reaches feature parity for prompt logprob evaluation.
- Training run management becomes possible from Elixir.

## Evidence
- Python: `tinker/src/tinker/resources/service.py`, `lib/public_interfaces/sampling_client.py`, `types/training_run*.py`, `types/save_weights*_response.py`, `types/load_weights_response.py`.
- Elixir gaps: absence in `lib/tinkex/api/service.ex`, `lib/tinkex/sampling_client.ex`, missing response/type modules in `lib/tinkex/types/`.
