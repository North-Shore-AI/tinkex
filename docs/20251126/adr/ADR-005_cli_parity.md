# ADR-005: CLI Parity and Scope

- **Status:** Accepted
- **Date:** 2025-11-26

## Context
- Python CLI (Click) includes management commands: checkpoint list/info/publish/unpublish/delete/download, run list/info, rich table/json output (`tinker/src/tinker/cli/commands/*`).
- Elixir CLI (`lib/tinkex/cli.ex`) implements only `run` (sampling), `checkpoint` (save weights flow), and `version`; options and semantics differ from Python (execution vs management).
- Prior doc treated these differences as missing commands without acknowledging purposeful scope change.

## Decision
- Document the scope divergence: current Elixir CLI is execution-focused.
- If parity is desired, add management commands (list/info/delete/download checkpoint, run list/info) backed by `RestClient` + new types; reuse an output abstraction for table/json.
- Keep escript/OptionParser approach; Click lazy-loading is not required.

## Consequences
- Avoids mislabeling intentional differences as gaps.
- Clear path to add management commands without rewriting the CLI architecture.
- Output abstraction becomes reusable for future commands if implemented.

## Evidence
- Python: `tinker/src/tinker/cli/commands/checkpoint.py`, `run.py`, `version.py`.
- Elixir: `lib/tinkex/cli.ex` (no management commands, only execution flows).
