# Endpoint and paging mismatches

**Gap:** Minor but user-visible differences in endpoint paths and defaults between Python and Elixir.

- **Heartbeat path**
  - Python: `/api/v1/session_heartbeat` via `SessionHeartbeatRequest`.
  - Elixir: `/api/v1/heartbeat` (`lib/tinkex/api/session.ex`). README claims “behavior is equivalent”, but path differs.
- **List user checkpoints paging**
  - Python: default limit 100 (`RestClient.list_user_checkpoints`); batch fetches 1000 in CLI list.
  - Elixir: default limit 50 (`Rest.list_user_checkpoints/3`), different pagination defaults.
- **Potential effects**
  - Heartbeat path divergence could break compatibility if server only supports the Python path or expects session_heartbeat semantics (idempotency, metrics).
  - Paging defaults lead to different counts and more requests in Elixir for the same call.
- **Suggested alignment**
  1) Consider aliasing `/api/v1/session_heartbeat` in Elixir or documenting server expectation; optionally add compatibility toggle.
  2) Match default `limit` with Python (100) for list_user_checkpoints, or document the discrepancy.
  3) Add tests/docs to confirm behavior parity for these endpoints.
