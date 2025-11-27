# OTP Compliance Follow-Up (Codex 5.1 Heavy)

## Scope
Validity check of the prior audit items against the current `tinkex` codebase, plus consolidated next-step recommendations. Focused on correctness rather than risk scoring.

## Findings and Accuracy

### A. Restart strategy on dynamic clients (flake root cause)
- **Code reality:** `SamplingClient` and `TrainingClient` use `use GenServer` and do not override `child_spec/1`, so they default to `restart: :permanent`.
- **Effect:** Stopping children via `GenServer.stop/1` causes the `DynamicSupervisor` to restart them; repeated stops hit restart intensity and kill the supervisor and `ServiceClient`, yielding the observed `:noproc/:shutdown` flake.
- **Status:** Prior analysis is **correct**. Fix: set `restart: :temporary` (or `:transient` if you want abnormal-only restarts) or terminate via supervisor in tests.

### B. Unsupervised background tasks in TrainingClient
- **Code reality:** Multiple `Task.start/1` usages with manual `GenServer.reply/2`, plus `unlink_task/1` helpers to drop links (e.g., in save-weights and forward/backward handlers). Failures in these tasks are not supervised and can leave callers hanging until timeout.
- **Status:** Prior concern is **correct**. To harden, run through a `Task.Supervisor` or use `Task.async_nolink` with monitoring/backpressure and ensure the caller receives failure.

### C. Telemetry fire-and-forget tasks
- **Code reality:** `Tinkex.API.Telemetry.send/2` uses `Task.start/1` intentionally for non-blocking telemetry, with try/rescue and a docstring that states tasks are not supervised.
- **Status:** The stated risk exists (unsupervised, no graceful drain) but it is intentional and not a flake cause. You can move to a `Task.Supervisor` for lifecycle tracking if desired.

### D. SessionManager soft state
- **Code reality:** State (sessions + heartbeat metadata) lives in the GenServer process. A crash would drop it; `init/1` does not reload from durable storage.
- **Status:** The observation is **correct**; it is a durability/continuity concern, not tied to the flake. Mitigation would be ETS-backed state with reload on init.

### E. Future/poll implementation
- **Code reality:** `Tinkex.Future.poll/2` uses `Task.async` and `Process.sleep` in a loop. It is linked to the caller (so crashes propagate). Not an OTP violation, but it is a blocking sleep rather than timer-based scheduling.
- **Status:** Prior note is **accurate**, but this is acceptable for short-lived tasks; only change if you want a timer-driven worker.

### F. “Orphaned local supervisor” claim
- **Code reality:** `ensure_client_supervisor(:local)` calls `DynamicSupervisor.start_link`, so it is linked to the `ServiceClient` process. It is not orphaned; the key issue is the child restart policy (A), not linkage.
- **Status:** The earlier “orphaned” wording was **incorrect**; linkage is fine, restart semantics are the real problem.

### G. ETS race note
- **Code reality:** `ServiceClient.ensure_table/2` already rescues `ArgumentError` when `:ets.new/2` races. `Tinkex.Application.create_table/2` is check-then-new; a race would raise, but can be hardened with try/rescue.
- **Status:** Race is theoretical; mitigation is straightforward if desired.

## Recommended Actions (ordered)
1) **Deflake core issue:** Make `SamplingClient` and `TrainingClient` child specs `restart: :temporary` (or ensure tests terminate via `DynamicSupervisor.terminate_child/2`). This prevents restart storms and supervisor death.
2) **Supervise training background tasks:** Replace `Task.start` + unlink with `Task.Supervisor` or `Task.async_nolink` + monitor/backpressure; ensure callers get failure signals promptly.
3) **Optional telemetry hardening:** Route telemetry tasks through a dedicated `Task.Supervisor` if you want graceful draining and visibility; otherwise leave as-is (intentional fire-and-forget).
4) **Optional session durability:** Back `SessionManager` state with ETS and reload on init to survive a crash without losing heartbeat tracking.
5) **Optional poll refinement:** Consider timer-driven polling instead of `Process.sleep` if you want more OTP-friendly scheduling.
6) **Harden ETS creation (if desired):** Change `create_table/2` in `Tinkex.Application` to a try/rescue `:ets.new/2` to eliminate the check-then-new race window.

## Notes for implementers
- Changing restart policy is the direct, validated fix for the async client flake.
- Task supervision changes will alter failure propagation; ensure callers handle task crashes and timeouts appropriately.
- None of the optional items block current tests, but they improve OTP hygiene and observability.***
