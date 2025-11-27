# User-error detection via cause/context traversal

Goal: reach parity with tinker's  that walks  /  to classify wrapped user errors.

## Gaps today
-  only follows  (Erlang-style) and misses Elixir wrappers that store causes in , , or .

## Implementation plan
1. Normalize exceptions into a traversal struct:
   - Extract next candidates from:
     -  output (for catch exits).
     -  if present.
     -  only if 4xx (user) / exclude 408/429.
     -  -> check .
     -  / .
2. Maintain visited set (ids) to break cycles.
3. Evaluate  against each candidate.
4. Update  to pass the found user error.

## Tests
- New cases in :
  - Wrapped Plug errors -> logs user_error.
  - Custom  map -> user_error.
  - Cycle detection returns :not_found without blowing stack.
