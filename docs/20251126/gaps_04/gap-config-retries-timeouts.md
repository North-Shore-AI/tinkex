# GAP: Default Retries & Timeouts Diverge

## Status
- **Python defaults**: `DEFAULT_TIMEOUT = httpx.Timeout(60s overall, 5s connect)`, `DEFAULT_MAX_RETRIES = 10` (tinker/src/tinker/_constants.py:6-10). Connection limits: `max_connections=1000`, `max_keepalive_connections=20`.
- **Elixir defaults**: `timeout: 120_000 ms`, `max_retries: 2`, Finch pool defaults are much smaller (see `lib/tinkex/config.ex:48-86`; application pools configured in `lib/tinkex/application.ex`).

## Why It Matters
- **Parity & Expectations**: Users porting code expect similar retry behavior and timeouts. With only 2 retries, the Elixir client gives up far earlier on transient 5xx/429/408 errors.
- **Reliability Under Load**: Python’s 10 retries with exponential backoff tolerate longer backpressure; Elixir may surface errors sooner, especially when paired with tighter pool limits.
- **Doc Accuracy**: The prior gap report called this an “intentional difference,” but it is a substantive behavior delta that should be explicit and configurable.

## Evidence
- Elixir config defaults: `@default_timeout 120_000`, `@default_max_retries 2` (`lib/tinkex/config.ex:48-50`).
- Python constants: `_constants.py` shows 60s timeout and 10 retries.
- Retry semantics differ: Elixir `max_retries` is HTTP-level retries; Python `DEFAULT_MAX_RETRIES` applies across resources.

## Proposed Solutions
1. **Config Parity Option**:
   - Add a `:parity_mode` opt/env (e.g., `TINKEX_PARITY=python`) that sets defaults to match Python: timeout 60s, max_retries 10, and optionally bump pool limits.
   - Or, change hard defaults to match Python and allow opting into “BEAM conservative” values via config/env.
2. **Docs & Warnings**:
   - Update README/config docs to call out the divergence and how to override via `Config.new/1`.
   - Log a warning when using non-Python defaults if parity is requested.
3. **Tests**:
   - Config construction tests ensuring `parity_mode: :python` yields 60s/10.
   - Integration test that retries are attempted the expected number of times.
4. **Pool Consideration**:
   - Review Finch pool sizes to ensure they can sustain the higher retry volume if defaults are raised.

## Effort
- Estimated ~1–2 hours (config + docs + tests); additional time if pools are adjusted.
