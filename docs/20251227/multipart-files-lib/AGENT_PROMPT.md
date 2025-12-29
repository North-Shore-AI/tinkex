# multipart_ex Build Prompt (Library-Only)

## Goal
Build the `multipart_ex` library described in the design doc. Use TDD, fix the
implicit path vulnerability, and add streaming support.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/multipart-files-lib/docs.md
- /home/home/p/g/n/multipart_ex/README.md
- /home/home/p/g/n/multipart_ex/mix.exs
- /home/home/p/g/n/multipart_ex/lib
- /home/home/p/g/n/multipart_ex/test
- /home/home/p/g/n/multipart_ex/CHANGELOG.md

## Instructions
- Work only in `/home/home/p/g/n/multipart_ex`.
- Do not modify any other repo (including Tinkex).
- Remove implicit path detection; require explicit `{:path, path}` inputs.
- Provide serialization strategies (`:bracket`, `:dot`, `:flat`) and nil handling.
- Add optional MIME inference via `mime` if available; default to octet-stream.
- Provide adapters for Finch and Req without coupling core to a client.
- Use TDD: add tests before major behavior changes.
- Update `README.md` and any docs/guides in the repo.
- Create the initial release `CHANGELOG.md` entry for 2025-12-27 targeting 0.1.0.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
