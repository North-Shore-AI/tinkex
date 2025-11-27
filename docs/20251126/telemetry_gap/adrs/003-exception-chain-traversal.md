# ADR 003 – Exception Chain Traversal for User Errors

## Status
Proposed

## Context
- Reporter currently follows only `%{reason: %Exception{}}`; misses many wrapper patterns.  
- Python `_get_user_error` walks `__cause__`/`__context__` and classifies 4xx (excl. 408/429) and `RequestErrorCategory.User`.
- Missed user errors become `UNHANDLED_EXCEPTION`, skewing telemetry.

## Decision
Broaden traversal with cycle safety:
- Keep visited map (phash2 ids); early return on repeat.  
- Check current exception via `user_error_exception?/1` (status/status_code 400–499 minus 408/429, or category :user).  
- Candidate extraction order:
  1) `Exception.normalize/3` result for non-exception terms  
  2) `:cause` field (Elixir-style)  
  3) `:reason` (Erlang/Plug.Conn.WrapperError)  
  4) `:plug_status` 4xx (excl. 408/429)  
  5) `:__cause__`  
  6) `:__context__`
- Depth-first over candidates; first match wins.

## Consequences
**Positive:** Better user-error classification; Plug/Python interop supported; cycle-safe.  
**Negative:** Slightly more traversal work; more code paths to test.  
**Neutral:** Behaviour stays deterministic and conservative (excludes 408/429).

## Tests
- WrapperError with 400 -> user_error.  
- Map with `:cause` containing 422 -> user_error.  
- `:__cause__` / `:__context__` chains.  
- `:plug_status` 403 accepted; 408/429 ignored.  
- Cycle returns `:not_found`; deep non-user chain returns `:not_found`.

## Rollout
1) Implement `extract_exception_candidates/1` + updated traversal.  
2) Add tests to `telemetry_reporter_test.exs`.  
3) Document supported patterns in reporter moduledoc.***
