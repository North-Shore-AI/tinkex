# ADR 0003: Match run management listing/info to Python CLI

Status: Proposed  
Date: 2025-12-03

## Context
- Python `tinker run list` paginates with progress, exposes total vs shown counts, and prints owner, LoRA details, status, and last checkpoints; `run info` surfaces the same rich fields (`tinker/src/tinker/cli/commands/run.py:174-256`).
- Elixir `tinkex run list/info` fetches a single page and prints only training_run_id and base_model (`lib/tinkex/cli.ex:1078-1122`), omitting owner, LoRA rank, status, last checkpoint metadata, and pagination.
- This limits operational visibility and diverges from the Python UX, making automation and cross-SDK guidance inconsistent.

## Decision
- Add pagination with optional progress for `tinkex run list`, honoring `--limit` (and `0` for all) with cursor-based loops that aggregate runs until the target is reached.
- Extend list and info output to include owner, LoRA flag/rank, corruption status, last training/sampler checkpoints (IDs, times, paths), and user metadata, mirroring Python tables/JSON.
- Keep the existing defaults lightweight (20 items) but allow full fetches for parity.

## Consequences
- Larger responses and more API calls when fetching all runs, but users gain parity and richer diagnostics.
- CLI output surface changes; existing scripts printing two columns may need to adjust.

## Alternatives considered
- Leave minimal output and rely on REST APIs directly: rejected to keep the CLI experience aligned and reduce bespoke scripting for common tasks.
