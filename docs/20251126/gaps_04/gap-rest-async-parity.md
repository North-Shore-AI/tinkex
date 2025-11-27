# GAP: RestClient Async Parity

## Status
- **Python**: Every RestClient method has async + sync variants (`get_training_run_async`, `list_training_runs_async`, `list_checkpoints_async`, `get_checkpoint_archive_url_async`, `delete_checkpoint_async`, `publish/unpublish *_async`, `list_sessions_async`, `get_session_async`, `get_sampler_async`, etc.) implemented in `tinker/src/tinker/lib/public_interfaces/rest_client.py` (see e.g., lines ~98-134, 187-200, 250-278, 334-360, 404-432, 514-548, 574-604, 620-648).
- **Elixir**: `lib/tinkex/rest_client.ex` exposes only synchronous functions returning `{:ok, struct} | {:error, error}`; there are no Task-wrapped async helpers.

## Why It Matters
- **API Surface Parity**: Elixir callers cannot mirror Python’s async ergonomics; they must wrap sync calls in `Task.async` manually. This breaks “API surface parity” claims.
- **Throughput & Latency**: Async variants allow issuing concurrent requests (e.g., list sessions while fetching sampler info) without blocking a GenServer or process.
- **Migration Friction**: Users porting Python code that awaits async methods need to hand-roll wrappers.

## Evidence
- Elixir: `lib/tinkex/rest_client.ex` has no `*_async` functions (see lines 1-220).
- Python: `rest_client.py` shows paired async implementations for every method.

## Proposed Solution (Elixir)
1. **Add Async Helpers**: For each sync function, add a `*_async/1` (or `/2`) that wraps the sync call in `Task.async(fn -> ... end)` and returns `Task.t()`. Preserve the same arguments/arity as sync.
2. **Return Shape**: Async should resolve to the same `{:ok, struct} | {:error, error}` tuples to match the rest of the SDK.
3. **Docs**: Extend moduledoc with async examples mirroring Python usage.
4. **Tests**: Add `test/tinkex/rest_client_async_test.exs` that:
   - Uses a Bypass server to stub REST endpoints.
   - Verifies `Task.await/2` returns the same data as sync.
   - Asserts tasks exit cleanly on errors.

## Effort
- Estimated ~1–1.5 hours (code + tests + docs).
