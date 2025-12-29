# Tinkex Integration Prompt (telemetry_reporter)

## Goal
Refactor Tinkex to use the completed `telemetry_reporter` library and remove
local reporter plumbing. Use TDD and preserve behavior.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/telemetry-reporter-lib/docs.md
- /home/home/p/g/n/telemetry_reporter/README.md
- /home/home/p/g/n/telemetry_reporter/lib
- /home/home/p/g/North-Shore-AI/tinkex/mix.exs
- /home/home/p/g/North-Shore-AI/tinkex/README.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides/telemetry.md
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/reporter.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/reporter/backoff.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/telemetry.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/telemetry_event.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/telemetry_send_request.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/session_start_event.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/session_end_event.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/generic_event.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/unhandled_exception_event.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/telemetry_batch.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/severity.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/telemetry/event_type.ex

## Instructions
- Work only in `/home/home/p/g/North-Shore-AI/tinkex`.
- Do not modify the `telemetry_reporter` repo.
- Replace Tinkex telemetry reporter internals with `telemetry_reporter`.
- Keep Tinkex public API behavior stable; remove unused backoff module.
- Update `mix.exs` dependency and docs to reference the new library.
- Use TDD: add tests before major behavior changes.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
