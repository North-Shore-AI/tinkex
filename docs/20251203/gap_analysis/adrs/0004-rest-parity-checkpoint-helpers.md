# ADR 0004: Restore REST parity for checkpoint helpers

Status: Proposed  
Date: 2025-12-03

## Context
- Python RestClient exposes archive/delete helpers keyed by training_run_id + checkpoint_id and defaults `list_user_checkpoints` limit to 100 (`tinker/src/tinker/lib/public_interfaces/rest_client.py:269-366`, `513-569`).
- Elixir `RestClient` only offers tinker-path variants for archive/delete and defaults `list_user_checkpoints` to 50 (`lib/tinkex/rest_client.ex:144-188`, `170-182`, `190-219`).
- This diverges from Python convenience APIs and pagination defaults, making parity and migration harder.

## Decision
- Add ID-based helpers in Elixir RestClient (and underlying API module) for archive and delete that mirror Python signatures.
- Adjust `list_user_checkpoints` default limit to 100 to match Python.
- Keep existing tinker-path helpers for backward compatibility.

## Consequences
- Improved API parity and easier cross-language examples.
- Minor behavior change (default page size); document in changelog and allow opts to override.

## Alternatives considered
- Leave defaults as-is and document differences: rejected to maintain parity goal.
