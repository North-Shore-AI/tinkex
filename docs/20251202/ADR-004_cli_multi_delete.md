# ADR-004: Multi-checkpoint delete CLI

- **Status:** Draft
- **Date:** 2025-12-02

## Context
- Python CLI `tinker checkpoint delete` now accepts multiple checkpoint paths, validates them up front, confirms the total count, and shows a progress bar while deleting sequentially.
- Elixir CLI (`lib/tinkex/cli.ex`) supports only a single path (`checkpoint delete <tinker_path>`) and does not batch or display progress.
- REST surface in Elixir already has `Tinkex.RestClient.delete_checkpoint/2` and `delete_checkpoint_by_tinker_path/2` for a single path; no batch endpoint exists server-side.

## Decision
- Extend the Elixir CLI to accept one or more checkpoint paths and delete them sequentially:
  - CLI parsing should allow `tinkex checkpoint delete <path> [<path> ...]`.
  - Validate all inputs start with `tinker://` before issuing any deletes.
  - Summarize the count and prompt once (unless `--yes`), then stream progress (spinner or per-path log) as deletes complete.
- Keep REST calls one-per-path; do not invent a batch HTTP endpoint.

## Consequences
- Ergonomic parity with Python; reduces repetitive CLI invocations for bulk cleanup.
- Slightly more complex CLI parsing and output handling; existing single-path usage remains valid.
- Need to decide on failure semantics (e.g., continue on error vs. abort); proposed default: continue, aggregate failures.

## Integration plan (Elixir)
1) Update CLI parser in `lib/tinkex/cli.ex` to collect multiple positional args for `checkpoint delete`.
2) Adjust `checkpoint_delete/3` to iterate over paths, validate `tinker://` prefix, and issue `delete_checkpoint/2` calls sequentially (or with bounded concurrency) while printing progress.
3) Return a summary map `{deleted: n, failed: m, failures: [...]}` for downstream automation and test assertions.
4) Add tests for multi-delete invocation, validation failures, and mixed success/failure cases.

## Viability
- No server changes required; the existing REST call can be repeated safely.
- Parsing change is localized to CLI code; other clients (ServiceClient/RestClient) remain untouched.
