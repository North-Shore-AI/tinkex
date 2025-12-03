# ADR-005: Retry progress timeout to 120 minutes

- **Status:** Draft
- **Date:** 2025-12-02

## Context
- Python `RetryConfig.progress_timeout` increased from 30 minutes to 120 minutes to tolerate long-running operations before declaring a progress timeout.
- Elixir defaults remain at 30 minutes:
  - `@default_progress_timeout_ms 1_800_000` in `lib/tinkex/retry_handler.ex`.
  - `@default_progress_timeout_ms 1_800_000` in `lib/tinkex/retry_config.ex`.
- Operations like checkpoint save/load or long trainings can legitimately exceed 30 minutes, so Elixir clients may time out earlier than Python.

## Decision
- Raise the default progress timeout to 120 minutes (7_200_000 ms) in both `RetryHandler` and `RetryConfig` to match Python.
- Keep configurability intact (env/opts can still override).

## Consequences
- Fewer premature timeouts for long operations; aligns user expectations across SDKs.
- Longer waits before giving up when there is truly no progress; callers that want shorter bounds should set `progress_timeout_ms` explicitly.

## Integration plan (Elixir)
1) Update default constants in `lib/tinkex/retry_handler.ex` and `lib/tinkex/retry_config.ex` to `7_200_000`.
2) Review any config surfaces (`Tinkex.Config.new/1`, CLI) to ensure they either inherit the new default or document how to override.
3) Add a regression test that `RetryHandler.new/1` and `RetryConfig.new/1` default to the new value.
4) Update docs (`docs/guides/retry_and_error_handling.md`) to reflect the new default and rationale.

## Viability
- Purely client-side default change; no server impact.
- Existing override paths remain valid; low risk aside from longer waits on genuine hangs.
