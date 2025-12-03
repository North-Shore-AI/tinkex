# ADR 0003: Align session heartbeat timeouts/retries with Python

## Context
- Python heartbeats use a tight timeout (10s) and `max_retries=0` to avoid blocking and retry storms (`session_heartbeat(timeout=10, max_retries=0)`).
- Elixir heartbeats reuse global HTTP defaults (120s timeout, retries=2 or parity=10), so heartbeat cycles can block longer and retry when Python would not.
- Divergence affects liveness detection and warning cadence in `SessionManager`.

## Decision
- Override heartbeat HTTP options to `timeout=10_000` ms and `max_retries=0` (or parity-consistent) when issuing session heartbeats, independent of global defaults.
- Keep warning/debounce semantics unchanged.

## Consequences
- Faster detection of dropped connections and fewer long-lived heartbeat waits; matches Python expectations.
- Slight increase in heartbeat failures on slow networks; acceptable for parity and can be feature-gated if needed.
