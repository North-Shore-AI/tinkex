# Tinkex Sinter Refactor Prompt (TDD)

## Goal
Refactor Tinkex to use Sinter 0.1.0 for schema definitions, validation, and
JSON encode/decode. Replace ad-hoc `from_json/1` and `Jason.Encoder` logic where
appropriate, while keeping public APIs stable. Use TDD.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/tinkex-sinter-refactor/docs.md
- /home/home/p/g/n/sinter/README.md
- /home/home/p/g/n/sinter/CHANGELOG.md
- /home/home/p/g/n/sinter/mix.exs
- /home/home/p/g/n/sinter/lib/sinter/schema.ex
- /home/home/p/g/n/sinter/lib/sinter/validator.ex
- /home/home/p/g/n/sinter/lib/sinter/json.ex
- /home/home/p/g/n/sinter/lib/sinter/transform.ex
- /home/home/p/g/n/sinter/lib/sinter/not_given.ex
- /home/home/p/g/n/sinter/lib/sinter/types.ex
- /home/home/p/g/n/sinter/lib/sinter/json_schema.ex
- /home/home/p/g/North-Shore-AI/tinkex/mix.exs
- /home/home/p/g/North-Shore-AI/tinkex/README.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/request.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/response.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/response_handler.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/transform.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/not_given.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types
- /home/home/p/g/North-Shore-AI/tinkex/test

## Instructions
- Work only in `/home/home/p/g/North-Shore-AI/tinkex`.
- Do not modify the Sinter repo.
- Use TDD: add failing tests before new behaviors, then implement.
- Introduce Sinter schemas for request/response types and centralize encode/decode.
- Replace `Tinkex.Transform`/`Tinkex.NotGiven` with `Sinter.Transform` and
  `Sinter.NotGiven`; remove local modules if unused.
- Ensure JSON serialization only strips `Sinter.NotGiven` sentinels by default;
  do not drop nil values unless explicitly required for a request.
- Maintain public API behavior (return structs where callers expect them).
- Update Tinkex docs/guides and README where JSON/serialization behavior changes.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.

## Verification
- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix test`
- `mix credo --strict`
- `mix dialyzer`
