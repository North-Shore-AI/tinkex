# ADR 0001: Preserve checkpoint archive expiry metadata

Status: Proposed  
Date: 2025-12-03

## Context
- Python SDK returns `expires` alongside the signed URL for checkpoint archive downloads (`tinker/src/tinker/types/checkpoint_archive_url_response.py`).
- Elixir `Tinkex.Types.CheckpointArchiveUrlResponse` only surfaces `url`, discarding the expiry parsed from redirect headers (`lib/tinkex/api/api.ex:456-472`, `lib/tinkex/types/checkpoint_archive_url_response.ex`).
- Without expiry, Elixir callers cannot reason about URL validity windows or prefetch refresh logic.

## Decision
- Extend `Tinkex.Types.CheckpointArchiveUrlResponse` to include an `expires` field (timestamp or datetime ISO8601) and populate it when parsing redirect responses.
- Plumb the value through `Rest.get_checkpoint_archive_url/2` and `RestClient.get_checkpoint_archive_url/2` so it is available to SDK consumers.

## Consequences
- Parity with Python for archive metadata; callers can schedule downloads or refreshes before expiry.
- Minor API change (adds a field) that remains backward compatible for map consumers but requires version bump and doc update.

## Alternatives considered
- Ignore expiry and rely on server errors: rejected due to poorer UX and parity mismatch.
