# ADR 0002: Expose full checkpoint metadata in `checkpoint info`

Status: Proposed  
Date: 2025-12-03

## Context
- Python `tinker checkpoint info` resolves the checkpoint, surfaces type, size, public flag, created-at timestamp, path, and training run ID (`tinker/src/tinker/cli/commands/checkpoint.py:351-417`).
- Elixir `tinkex checkpoint info` only prints base model and LoRA flags from `weights_info` (`lib/tinkex/cli.ex:893-909`), omitting visibility, size, timestamps, and run identifiers.
- Users cannot audit checkpoint state (public/private, size, creation time) via the Elixir CLI, diverging from Python tooling and complicating operational checks.

## Decision
- Rework `tinkex checkpoint info` to fetch checkpoint details (e.g., via `list_checkpoints` for the run) and render the same fields Python shows: checkpoint ID, type, size, public, created, path, training_run_id plus the existing base model / LoRA attributes.
- Ensure JSON output includes the full checkpoint object for scripting parity.
- Keep the existing validation of `tinker://` paths.

## Consequences
- Slightly more API work per info call (may require parsing the path to locate the checkpoint), but delivers feature parity and operational usefulness.
- CLI output changes; scripts relying on the old minimal text must adapt, but richer data aligns with Python.

## Alternatives considered
- Leave info minimal and document the gap: rejected because parity and observability are explicit goals for the CLI gap analysis.
