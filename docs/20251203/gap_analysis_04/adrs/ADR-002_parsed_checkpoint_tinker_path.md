# ADR-002: Public `ParsedCheckpointTinkerPath` helper

Status: Proposed  
Date: 2025-12-03  
Owners: Elixir SDK parity

## Context
- Python exposes `ParsedCheckpointTinkerPath` (fields: `tinker_path`, `training_run_id`, `checkpoint_type`, `checkpoint_id`) with a `from_tinker_path` parser and uses it across REST helpers and CLI validation.
- Tinkex currently has only a private `parse_tinker_path/1` inside `Tinkex.API.Rest`; consumers (CLI, examples, future helpers) cannot reuse a typed parser or struct. We also lack the public type parity that Python’s SDK documents.
- We already model checkpoint metadata (`Tinkex.Types.Checkpoint`) and expose REST helpers for publish/unpublish/delete by tinker path, so adding the parser/type aligns surface area without changing wire formats.

## Decision
- Introduce `Tinkex.Types.ParsedCheckpointTinkerPath` with:
  - Fields: `tinker_path`, `training_run_id`, `checkpoint_type` (`"training"` | `"sampler"`), `checkpoint_id`.
  - `from_tinker_path/1` returning `{:ok, struct}` or `{:error, %Tinkex.Error{category: :user}}` on invalid input.
- Refactor internal users to rely on the helper instead of bespoke string splitting where practical (REST helpers, CLI checkpoint commands, examples), while keeping wire behavior unchanged.

## Consequences
- Parity with Python’s public type surface; callers get a reusable validator/parser.
- Slight refactor risk in CLI/REST code paths; covered via existing checkpoint tests and new unit tests for the parser.

## Action Items
1) Add `lib/tinkex/types/parsed_checkpoint_tinker_path.ex` implementing the struct and `from_tinker_path/1` parser with user-facing error categories.  
2) Update `Tinkex.API.Rest.parse_tinker_path/1` (or replace) and CLI checkpoint delete/info paths to use the new helper.  
3) Add unit tests for valid/invalid paths and integration coverage where used (REST/CLI).  
4) Document the new helper in the API reference and changelog; avoid direct `System.get_env/1` usages while implementing.
