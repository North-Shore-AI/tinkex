# Tinkex Integration Prompt (foundation)

## Goal
Refactor Tinkex to use the completed `foundation` resilience primitives and remove
local duplicates. Use TDD and preserve behavior.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/foundation-resilience/docs.md
- /home/home/p/g/n/foundation/README.md
- /home/home/p/g/n/foundation/docs
- /home/home/p/g/n/foundation/lib
- /home/home/p/g/North-Shore-AI/tinkex/mix.exs
- /home/home/p/g/North-Shore-AI/tinkex/README.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides/retry_and_error_handling.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides/futures_and_async.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/guides/recovery.md
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/retry.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/retry_config.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry_handler.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry_config.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/rate_limiter.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/circuit_breaker.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/circuit_breaker/registry.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/bytes_semaphore.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/retry_semaphore.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/sampling_dispatch.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/recovery/policy.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/recovery/executor.ex
- /home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/reporter.ex

## Instructions
- Work only in `/home/home/p/g/North-Shore-AI/tinkex`.
- Do not modify the `foundation` repo.
- Replace Tinkex retry/backoff/rate-limit/circuit-breaker/semaphore code with
  the completed `foundation` equivalents.
- Remove duplicated modules where appropriate; keep public APIs stable.
- Update `mix.exs` dependencies and documentation to reference `foundation`.
- Use TDD: add tests before major behavior changes.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
