# Tinkex ↔ Sinter Refactor Plan (0.1.0)

## Status
- Draft: 2025-12-27
- Sinter repo: `/home/home/p/g/n/sinter` (v0.1.0)

## Context
Sinter 0.1.0 now provides:
- String-keyed schemas by default (safe for untrusted input).
- Nested object schemas via `Schema.object/1` and `{:object, ...}`.
- JSON encode/decode helpers (`Sinter.JSON`) and transform pipeline (`Sinter.Transform`).
- `Sinter.NotGiven` sentinels for omit vs nil.
- JSON Schema generation and validation via JSV (Draft 2020-12 default, Draft 7 for providers).

Tinkex currently has bespoke `Jason.Encoder` implementations and many
`from_json/1` parsers that duplicate schema/validation logic. This refactor
moves request/response validation and JSON shaping to Sinter to reduce code
and align with Python SDK parity.

## Goals
- Replace manual request/response schema handling with Sinter schemas.
- Centralize JSON encode/decode and NotGiven semantics.
- Keep public Tinkex APIs stable.
- Maintain or improve test coverage using TDD.

## Scope (Primary Files)
- `lib/tinkex/types/*` (request/response structs, `from_json/1` helpers)
- `lib/tinkex/api/request.ex` (JSON encoding path)
- `lib/tinkex/api/response.ex` and call sites (response parsing)
- `lib/tinkex/transform.ex` and `lib/tinkex/not_given.ex` (replace with Sinter)
- Tinkex tests covering types, API, and HTTP paths

## Design Decisions
### 1) String Keys Everywhere
Sinter normalizes schema fields to string keys and validates maps as
string-keyed data. Tinkex should treat JSON-facing maps as string-keyed.
Struct conversion must map known string keys to existing struct fields without
creating new atoms.

### 2) NotGiven vs Nil
Only `Sinter.NotGiven` (and `omit/0`) should be stripped from outgoing JSON.
Nil should be preserved by default to allow explicit `null` where required.
Use `drop_nil?: true` only when a specific request requires nil omission.

### 3) Nested Objects
Use `Schema.object/1` and `{:object, schema}` for nested shapes instead of
manual parsing. Use `{:nullable, type}` for optional nullable fields.

## Proposed Architecture
### A) Schema Definitions
Each type module should expose a `schema/0` using `Sinter.Schema`.
Example:
```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:profile, {:object, [
    {:joined_at, :datetime, [optional: true]}
  ]}, [optional: true]}
], strict: true)
```

### B) Shared Encoding/Decoding Helpers
Add a small internal module (e.g., `Tinkex.SchemaCodec`) to centralize:
- `decode(schema, json_map, into: Module)` using `Sinter.Validator.validate/3`
- `encode(struct_or_map, opts)` using `Sinter.JSON.encode/2`
- `to_struct(Module, string_map)` with safe field mapping

### C) Safe Struct Conversion
Map string keys to existing struct fields only:
- Use `struct_fields = Map.keys(struct(module))`
- Build atom-keyed map by matching strings to known fields
- Avoid `String.to_atom/1` on dynamic keys

## Implementation Plan
1. **Dependency**: add `{:sinter, "~> 0.1.0"}` to `mix.exs`.
2. **Transform / NotGiven**: replace `Tinkex.Transform` and `Tinkex.NotGiven`
   with `Sinter.Transform` and `Sinter.NotGiven`; remove local modules if no
   longer needed.
3. **Schema Layer**: introduce `schema/0` for key request/response types
   (start with high-traffic types: SampleRequest/Response, ForwardBackward,
   OptimStep, CreateSession, etc.).
4. **Request Encoding**: update `Tinkex.API.Request` to use
   `Sinter.JSON.encode` (or `Sinter.Transform` + `Jason.encode!`) so JSON payload
   is shaped by schema/transform pipeline.
5. **Response Parsing**: update `from_json/1` implementations to validate via
   Sinter and then convert to structs. Retain module APIs but remove manual
   parsing logic where possible.
6. **Tests**: add tests for schema validation, NotGiven handling, and
   request/response parity using TDD. Ensure existing tests remain green.
7. **Docs**: update README and relevant guides where JSON/serialization is
   described.

## Risks
- **Output key shape**: Sinter returns string keys; must not leak new atoms.
- **Nil semantics**: do not globally drop nil, or parity with Python may break.
- **Performance**: avoid unnecessary conversions in hot paths.

## Verification
- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
