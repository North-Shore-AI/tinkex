# ADR 0001: Align checkpoint list UX with Python CLI

Status: Proposed  
Date: 2025-12-03

## Context
- Python `tinker checkpoint list` accepts `--run-id`, `--limit` (with `0` meaning "fetch all"), paginates in batches with a progress bar, and reports remaining counts (`tinker/src/tinker/cli/commands/checkpoint.py:264-348`).
- Elixir `tinkex checkpoint list` always calls `list_user_checkpoints/3` once, ignores run-specific filtering, and lacks pagination/progress feedback (`lib/tinkex/cli.ex:866-885`).
- Users with many checkpoints cannot enumerate all entries or scope to a specific run via the Elixir CLI, creating parity gaps for automation and troubleshooting.

## Decision
- Add a run filter option to `tinkex checkpoint list` that routes to `Rest.list_checkpoints/2` when provided.
- Implement paginated fetching for user-wide listing, supporting `--limit 0` (fetch all) and showing a progress indicator when multiple pages are pulled.
- Preserve table output while emitting structured counts (total/shown) for JSON output to match Python semantics.

## Consequences
- More API calls during full listings; large enumerations will take longer but mirror Python behavior and give the user visibility via progress updates.
- CLI help surface grows slightly; scripts gain deterministic pagination semantics compatible with Python examples.

## Alternatives considered
- Document the limitation and keep single-page listing: rejected because it blocks parity-driven automation and fails for accounts with >page-size checkpoints.
