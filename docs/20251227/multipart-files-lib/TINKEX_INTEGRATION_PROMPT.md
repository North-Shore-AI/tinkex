# Tinkex Integration Prompt (multipart_ex)

## Goal
Refactor Tinkex multipart handling to use the completed `multipart_ex` library
and remove legacy multipart/files modules. Use TDD and preserve behavior.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/multipart-files-lib/docs.md
- /home/home/p/g/n/multipart_ex/README.md
- /home/home/p/g/n/multipart_ex/lib
- /home/home/p/g/North-Shore-AI/tinkex/mix.exs
- /home/home/p/g/North-Shore-AI/tinkex/README.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides/file_uploads.md
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/multipart/encoder.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/multipart/form_serializer.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/types.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/reader.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/files/transform.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/request.ex

## Instructions
- Work only in `/home/home/p/g/North-Shore-AI/tinkex`.
- Do not modify the `multipart_ex` repo.
- Replace Tinkex multipart/files internals with `multipart_ex`.
- Remove implicit path detection; update callsites to explicit `{:path, path}`.
- Update `mix.exs` dependency and docs to reference the new library.
- Use TDD: add tests before major behavior changes.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
