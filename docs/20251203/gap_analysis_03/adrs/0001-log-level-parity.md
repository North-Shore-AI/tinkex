# ADR 0001: Apply TINKER_LOG to Elixir logging

## Context
- Python SDK runs `_setup_logging()` on import and respects `TINKER_LOG=debug|info`, also downgrading `httpx` noise by default.
- Elixir port reads `TINKER_LOG` via `Tinkex.Env.log_level/1` and carries it in `Tinkex.Config`, but never applies it to `Logger` or HTTP logging.
- Result: users cannot dial verbosity in Elixir as they can in Python, and noisy HTTP logs may surface.

## Decision
- Honor `config.log_level` (env → app config → opts) at startup by setting the root `Logger` level and aligning HTTP client logging defaults to Python (suppress noisy HTTP client logs unless explicitly enabled).
- Keep defaults silent (no level set) to avoid altering host apps unless `TINKER_LOG`/config is present.

## Consequences
- Parity with Python for the `TINKER_LOG` knob and clearer guidance for users.
- Slight behavior change when `TINKER_LOG` is set: Logger level will now change; document in CHANGELOG.
- Implementation will need a centralized hook (likely in `Tinkex.Application` or `Tinkex.Config.new/1`).
