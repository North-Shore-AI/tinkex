# Manifest Reimagining: Context and Goals

## Overview
Tinkex is being reimagined as a manifest-driven SDK where the entire public API surface is generated from a declarative manifest, and all reusable infrastructure lives in Pristine. The source of truth for behavior is the existing Tinker Python SDK and the Elixir examples. The end goal is not a thin compatibility shim; it is a generalized system where reusable features are modeled explicitly in the manifest and implemented once in Pristine.

The bar is high:
- Tinkex should expose a public surface that is materially the same as before.
- Examples should run with minimal to no changes.
- New functionality must be described in the manifest as composable features.
- Tinkex retains only domain-specific code that cannot be generalized.

## Required Reading
The following are required to understand the original behavior and current refactor state:

- Python SDK source of truth:
  - `tinker/src/tinker/_client.py`
  - `tinker/src/tinker/_base_client.py`
  - `tinker/src/tinker/_response.py`
  - `tinker/src/tinker/_streaming.py`
  - `tinker/src/tinker/resources/*.py`
  - `tinker/src/tinker/lib/*`
  - `tinker/src/tinker/types/*`
  - `tinker/docs/api/*.md`

- Elixir examples and expectations:
  - `examples/README.md`
  - `examples/*.exs`

- Existing refactor notes:
  - `docs/20260106/examples_parity_assessment.md`
  - `docs/20260106/hexagonal-refactor/plan.md`
  - `docs/20260106/hexagonal-refactor/REPLACEMENT_MAP.md`

- Historical Elixir update docs (features and examples):
  - `docs/20251121/tinker-updates/*`

## Goals
1. Manifest-driven API surface
   - The manifest is the single source of truth for endpoints, request/response types, and behavior flags.
   - The manifest supports composition of reusable features (futures, retries, streaming, telemetry, etc.).

2. Pristine as the generalization layer
   - All reusable infrastructure (transport, retry/backoff, telemetry, futures, streaming, rate limiting, multiplexing) lives in Pristine.
   - Tinkex owns only domain-specific logic (tokenization, byte estimation, model input helpers, custom loss helpers).

3. Parity in shape and behavior
   - The public API surface should remain intact (ServiceClient, TrainingClient, SamplingClient, RestClient, CLI, Telemetry, Metrics, Recovery, Regularizers, etc.).
   - Examples should run without modification (or minimal configuration changes only).

4. Explicit feature modeling
   - Every behavior knob is modeled explicitly as a manifest feature.
   - Features are granular but still reusable; do not create per-endpoint one-offs unless truly unique.

5. Test-driven delivery
   - Use TDD for each new feature (red-green-refactor).
   - Reintroduce or mirror tests that enforce surface parity.

## Non-Goals
- Changing server endpoints or server behavior.
- Inventing new SDK abstractions that break examples or change shapes.
- Hand-writing compatibility wrappers that bypass the manifest or Pristine.

## Constraints and Design Rules
- Manifest is declarative and must be expressive enough to encode all SDK behaviors.
- Features must be reusable and composable; avoid endpoint-specific hacks.
- Tinkex should be thin: minimal handwritten code, primarily domain-specific helpers.
- Environment handling must go through `Tinkex.Env` for Elixir, and must mirror the Python env knobs.

## Terminology
- Endpoint: A server API path + method + request/response types.
- Feature: A reusable cross-cutting behavior (retry, telemetry, future retrieval, streaming).
- Flow: A composite client operation composed of multiple endpoints plus local logic.
- Surface: The public API modules and functions exposed by Tinkex.
- Manifest: Declarative spec containing endpoints, types, features, and generation rules.

## High-Level Approach
1. Inventory the full surface of the Python SDK and Elixir examples.
2. Decompose behaviors into reusable features.
3. Design a manifest schema that can express the surface and features.
4. Implement features in Pristine with ports/adapters and shared pipelines.
5. Generate the Tinkex client surface from the manifest.
6. Reintroduce tests and validate parity with examples.

## Open Questions (to answer during design)
- How should composite flows (e.g., create training client from state) be expressed in the manifest?
- What is the minimal set of feature flags that still preserves full behavior?
- How will Tinkex expose legacy module names without handwritten wrappers?

