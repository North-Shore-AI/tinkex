# telemetry_reporter Build Prompt (Library-Only)

## Goal
Build the `telemetry_reporter` library described in the design doc, using Pachka
for batching. Use TDD and preserve behavior.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/telemetry-reporter-lib/docs.md
- /home/home/p/g/n/telemetry_reporter/README.md
- /home/home/p/g/n/telemetry_reporter/mix.exs
- /home/home/p/g/n/telemetry_reporter/lib
- /home/home/p/g/n/telemetry_reporter/test
- /home/home/p/g/n/telemetry_reporter/CHANGELOG.md

## Instructions
- Work only in `/home/home/p/g/n/telemetry_reporter`.
- Do not modify any other repo (including Tinkex).
- Use `pachka` ~> 1.0.0 for batching and retries.
- Keep core library transport-agnostic; implement a Pachka Sink + Transport behavior.
- Use TDD: add tests before major behavior changes.
- Update `README.md` and any docs/guides in the repo.
- Create the initial release `CHANGELOG.md` entry for 2025-12-27 targeting 0.1.0.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
