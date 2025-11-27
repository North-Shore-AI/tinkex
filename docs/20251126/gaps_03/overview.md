# Tinkex Python→Elixir API parity gaps (set 03)

Date: 2025-11-26
Author: Codex review of Python public clients vs. `lib/tinkex` implementation.

## Context
- Source of truth (Python): `lib/public_interfaces/{service_client.py,training_client.py,sampling_client.py,rest_client.py,api_future.py}`.
- Elixir inspected: `Tinkex.ServiceClient`, `Tinkex.TrainingClient`, `Tinkex.SamplingClient`, `Tinkex.RestClient`, `Tinkex.Future`, `Tinkex.Tokenizer`, `Tinkex.API.Service`.
- Goal: identify API-surface gaps where Elixir SDK diverges from Python parity expectations.

## Gaps and pointers
- Gap 1: `ServiceClient.get_server_capabilities/0` not exposed (see `service_client_get_server_capabilities.md`).
- Gap 2: `TrainingClient.save_weights_and_get_sampling_client/1` (and ephemeral sampler flow) absent (see `training_client_save_weights_and_get_sampling_client.md`).

## Non-gaps / notes
- `ServiceClient.create_training_client_from_state/3` **is** present in Elixir; earlier checklist mis-flagged it.
- Tokenizer access is provided via `Tinkex.Tokenizer` rather than `TrainingClient.get_tokenizer`; considered a deliberate API reshaping, not a missing surface.
