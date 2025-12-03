# ADR 0004: Restore per-pool connection isolation

## Context
- Python uses distinct httpx pools per `ClientConnectionPoolType` and caps train requests per client, preventing sampling/telemetry from contending with training.
- Elixir builds a Finch pool key but discards `pool_type`; all traffic shares the same pool, losing isolation and training caps.

## Decision
- Reintroduce pool-type-aware routing: include `pool_type` in Finch pool keys (e.g., `{base_url, pool_type}`) and configure pool sizes per type (session, training, sampling, futures, telemetry) to mirror Python’s limits.
- Ensure retry/backpressure logic keeps working with the new pool mapping.

## Consequences
- Better resource isolation under load; aligns throughput/latency characteristics with Python.
- Requires supervision changes (multiple pools) and careful migration to avoid breaking existing deployments that rely on a single pool.
