# ADR 0004: Add format/JSON output for checkpoint/run commands

Status: Proposed  
Date: 2025-12-03

## Context
- Python CLI accepts `--format table|json` globally, so `checkpoint` and `run` commands emit machine-readable JSON (`tinker/src/tinker/cli/__main__.py:17-37`).
- Elixir `tinkex` CLI exposes `--json` only for sampling; checkpoint and run management switches lack any format flag (`lib/tinkex/cli.ex:1420-1474`), always printing human tables.
- Without JSON output, scripts cannot reliably consume checkpoint/run metadata via the Elixir CLI, creating parity and automation gaps.

## Decision
- Introduce a format flag for management commands (reusing `--json` or `--format table|json`) and emit structured JSON payloads that mirror Python’s shapes for list/info/download/publish/unpublish/delete.
- Keep table output as default for interactive use; ensure help text documents the format option.

## Consequences
- CLI help and output options become richer; existing human-readable defaults remain unchanged.
- Adds code paths to serialize responses; must keep in sync with Python shapes to avoid divergence.

## Alternatives considered
- Recommend direct library usage for structured data: rejected to preserve CLI parity and support shell automation workflows already documented for Python.
