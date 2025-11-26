# User-error detection via cause/context traversal

Goal: reach parity with tinker’s `_get_user_error` that walks `__cause__` / `__context__` to classify wrapped user errors; ensure Elixir reporter finds user errors in nested exceptions (e.g., Plug wrapper errors).

## Gaps today
- `find_user_error_in_chain/2` only follows `%{reason: %Exception{}}` (Erlang-style) and misses Elixir wrappers that store causes in `:plug_status`, `:conn`, or `:cause`/`cause/2` accessors.

## Implementation plan
1. Normalize exceptions into a traversal struct:
   - Extract next candidates from:
     - `Exception.normalize/3` output (for catch exits).
     - `Map.get(exception, :cause)` if present.
     - `Map.get(exception, :plug_status)` only if 4xx (user) / exclude 408/429.
     - `Map.get(exception, :conn)` -> check `%Plug.Conn.WrapperError{reason: reason}`.
     - `Map.get(exception, :__cause__)` / `Map.get(exception, :__context__)` if set (some Erlang wrappers).
2. Maintain visited set (ids) to break cycles; the map approach is fine since Dialyzer dislikes opaque MapSet.
3. Evaluate `user_error_exception?/1` against each candidate; stop at first match.
4. Update `build_exception_event/3` to pass the found user error (already wired).

## Tests
- New cases in `telemetry_reporter_test.exs`:
  - Wrapped `%Plug.Conn.WrapperError{reason: %RequestFailedError{status: 400}}` -> logs user_error.
  - Custom `%{cause: %Tinkex.Error{status: 422}}` map -> user_error.
  - Cycle detection (cause references parent) returns :not_found without blowing stack.
