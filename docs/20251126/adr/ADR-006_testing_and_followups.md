# ADR-006: Testing Priorities and Follow-Ups

- **Status:** Accepted
- **Date:** 2025-11-26

## Context
- Large portions of the port run without coverage for newly identified gaps (sentinel handling, response wrappers, new endpoints/types).
- Prior gap doc listed broad tests but mixed false positives with real needs.

## Decision
- Focus tests on the corrected gap areas:
  - Sentinel/transform: `given?/1`, `strip_not_given/1`, and request-body omission vs `nil`.
  - Response wrappers: metadata exposure, typed parsing, strict mode failures, SSE decoding happy-path/error-path.
  - New API surfaces: capability/health endpoints, `compute_logprobs`, weight save/load typed responses, training run list/info types.
  - CLI management commands if added: checkpoint list/info/delete/download and run list/info happy/error paths.
- Keep existing custom-loss and heartbeat flows under regression tests only (they already exist).

## Consequences
- Test effort is aligned to real correctness gaps rather than already-implemented features.
- Reduces risk when adding the new layers (serialization, response handling, endpoints).

## Evidence
- Gap corrections in ADR-001 through ADR-004 define the validated missing areas that require coverage.
