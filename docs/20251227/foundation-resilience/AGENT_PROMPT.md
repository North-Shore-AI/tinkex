# Foundation Resilience Library Prompt (Library-Only)

## Goal
Implement the resilience primitives described in the design doc inside the existing
`foundation` repo, replacing legacy `:fuse`/`:hammer`/`:poolboy` wrappers. Use TDD,
keep behavior parity, and eliminate duplicated backoff logic.

## Required Reading (absolute paths)
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/foundation-resilience/docs.md
- /home/home/p/g/North-Shore-AI/tinkex/docs/20251227/foundation-resilience-v2/docs.md
- /home/home/p/g/n/foundation/README.md
- /home/home/p/g/n/foundation/mix.exs
- /home/home/p/g/n/foundation/lib
- /home/home/p/g/n/foundation/test
- /home/home/p/g/n/foundation/semaphore/README.md
- /home/home/p/g/n/foundation/semaphore/lib/semaphore.ex

## Instructions
- Work only in `/home/home/p/g/n/foundation`.
- Do not modify any other repo (including Tinkex).
- Follow the design doc exactly; document any deliberate deviations.
- Use TDD: add tests before major behavior changes.
- Update `README.md` and any relevant docs/guides in the foundation repo.
- Remove outdated `docs/*` references from `mix.exs` (docs will be rebuilt).
- Remove legacy infrastructure wrappers and dependencies (`:fuse`, `:hammer`, `:poolboy`) with no deprecation shims.
- Base counting semaphores on an internal ETS implementation inspired by the `./semaphore` clone; implement weighted semaphores in Foundation; defer linksafe/sweeper mode for now.
- Bump version to `0.2.0` in `mix.exs` and `README.md`.
- Ensure `CHANGELOG.md` includes a `0.2.0 - 2025-12-27` entry.
- Ensure all tests pass and there are no warnings, no errors, no dialyzer warnings,
  and no `credo --strict` issues.
