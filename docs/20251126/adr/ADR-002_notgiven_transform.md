# ADR-002: NotGiven Sentinel and Transform System

- **Status:** Accepted
- **Date:** 2025-11-26

## Context
- Python uses a `NotGiven` sentinel (request options) plus transform utilities (`_utils/_transform.py`) to omit unset fields while allowing `None` to pass through.
- Elixir port currently has no sentinel, no guards, and no transform pipeline; `Jason.encode!` on maps can mis-send `nil` vs omitted fields and offers no alias/format handling.

## Decision
- Introduce a lightweight sentinel module (atom-based) with guards: `not_given/0`, `given?/1`, `strip_not_given/1`.
- Add a minimal transform layer for request building (aliases, discriminator/type defaults, optional field omission) before JSON encoding; keep manual per-request functions small and explicit.
- Scope sentinel usage to request options and optional fields where omission matters; do not globally strip `nil`.

## Consequences
- Restores Python semantics for optional parameters and timeouts.
- Reduces accidental `null` emission where the server expects omission.
- Requires targeted updates to request builders and tests to cover omission vs explicit null.

## Evidence
- Python source: `tinker/src/tinker/_types.py` (`NotGiven`) and `_utils/_transform.py`.
- Elixir absence: no `NotGiven` in `lib/`, request bodies are raw maps in `lib/tinkex/api/api.ex`.
