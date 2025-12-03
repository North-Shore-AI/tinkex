# ADR 0003: Align sampling retry concurrency defaults with Python

Status: Proposed  
Date: 2025-12-03

## Context
- Python `RetryConfig` defaults to `max_connections` equal to `DEFAULT_CONNECTION_LIMITS.max_connections = 1000` (`tinker/src/tinker/_constants.py:6-9`, `tinker/src/tinker/lib/retry_handler.py:38-45`).
- Elixir `Tinkex.RetryConfig` defaults `max_connections` to 100 (`lib/tinkex/retry_config.ex:31-55`).
- Lower concurrency in Elixir serializes sampling retries far more than Python, reducing throughput and diverging from expected parity.

## Decision
- Raise Elixir `RetryConfig` default `max_connections` to match Python’s effective default (1000) while preserving validation semantics.
- Document the change and allow users to override via opts/env as today.
- Consider capping by HTTP pool size in future, but prioritize parity now.

## Consequences
- Higher retry concurrency brings Elixir sampling performance closer to Python expectations.
- Potentially higher pressure on pools; users relying on the lower default may need to tune down explicitly.

## Alternatives considered
- Keep lower default and add a “parity” flag: rejected for complexity; direct parity is clearer.
