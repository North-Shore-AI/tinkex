# Multi-agent deep dive prompt (run from repo root)

You are the coordinator. You will spawn multiple sub-agents to perform an exhaustive review of both codebases:
- Python SDK: `./tinker` (from repo root `..`)
- Elixir SDK: `./` (same root)

The goals are to:
1) Review ALL recent changes (see ADRs and docs) and the current state of both SDKs.
2) Identify gaps, regressions, integration risks, and parity issues, especially around multimodal, checkpoint resume, retry defaults, tokenizer overrides, and CLI behaviors.
3) Produce agent-specific findings and a consolidated conclusion.

## Constraints and locations
- Run from repo root (`..`); paths:
  - Python code/docs: `./tinker/...`
  - Elixir code/docs: `./...`
- Existing docs to read:
  - `./tinker/UPSTREAM_CHANGES_0622760.md`
  - `./docs/20251202/00_INDEX.md`
  - `./docs/20251202/ADR-001_optimizer_resume.md`
  - `./docs/20251202/ADR-002_image_chunks_expected_tokens.md`
  - `./docs/20251202/ADR-003_chunk_counting.md`
  - `./docs/20251202/ADR-004_cli_multi_delete.md`
  - `./docs/20251202/ADR-005_retry_timeout.md`
  - `./docs/20251202/ADR-006_llama3_tokenizer.md`
  - `./docs/20251202/multimodal_viability.md`
- Output directory: create `./docs/20251202/multi_agent_deep_dive/`
  - Each agent writes one findings file: `agent-<id>-findings.md`
  - Coordinator writes `conclusion.md` after collecting agent results.

## Agent plan
1) Spawn at least 3 sub-agents with distinct focuses:
   - Agent A: Python SDK deep dive (recent changes + overall readiness, multimodal wiring).
   - Agent B: Elixir SDK deep dive (parity vs Python, multimodal gaps, retry/tokenizer defaults, CLI delete parity).
   - Agent C: Cross-cutting parity/risk (compare interfaces, schemas, defaults; check docs alignment).
   - Optional Agent D: Testing/operational risks (timeouts, progress, telemetry, session lifecycle).
2) Each agent must:
   - Read the ADRs and viability docs listed above.
   - Inspect relevant code paths in BOTH codebases (Python + Elixir) for their focus area.
   - Capture concrete file/line references, behaviors, and any missing/blocked work.
   - Write findings to `./docs/20251202/multi_agent_deep_dive/agent-<id>-findings.md` (markdown).
   - Include: Scope, Evidence (file refs), Findings (issues/gaps/risks), Suggested actions, Confidence.
3) Coordinator:
   - Dispatch agents with their scopes and shared constraints.
   - Wait for all agents, read their findings files, and produce `conclusion.md` summarizing:
     - Highest-risk gaps (with file refs).
     - Parity status summary.
     - Recommended next steps (prioritized).
   - Do NOT delete or overwrite agent files; add conclusion separately.

## Focus areas / hints
- Multimodal: Python’s `expected_tokens` schema and counting heuristics vs Elixir’s `height/width/tokens` and `ModelInput.length`. Identify what must change for parity.
- Checkpoint resume: Optimizer-state helpers added in Python; Elixir ergonomics/docs parity and defaults.
- CLI: Python multi-delete checkpoint flow vs Elixir single-delete.
- Retry/timeouts: Python 120m progress timeout vs Elixir 30m defaults.
- Tokenizer override: Llama-3 repo name change.
- Docs parity: Ensure ADRs/viability docs are reflected or contradicted by code.

## Deliverables
- `./docs/20251202/multi_agent_deep_dive/agent-<id>-findings.md` for each agent.
- `./docs/20251202/multi_agent_deep_dive/conclusion.md` from coordinator.

## Quality bar
- Findings must be specific (file:line, behavior, risk).
- Avoid hand-waving; verify by reading code.
- Call out unknowns and needed experiments, if any.
