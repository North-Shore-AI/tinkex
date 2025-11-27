# Tinkex Async Client Flake: GenServer/Supervisor Audit

## Symptom
- Intermittent failures in `test/tinkex/async_client_test.exs`, e.g.:
  - `** (exit) no process: the process is not alive or there's no process currently associated with the given name`
  - `** (EXIT) shutdown` from `Task.await/2` wrapping `ServiceClient.create_sampling_client_async/2`.
- Failures appear after a few iterations; most runs are green.

## Repro Findings
- Tests start sampling/training clients under `ServiceClient`’s `DynamicSupervisor` (defaults: strategy `:one_for_one`, restart `:permanent`, `max_restarts: 3` per 5s).
- Tests call `GenServer.stop(pid)` on the sampling clients. That triggers automatic restart attempts by the supervisor.
- After ~4–5 stops the supervisor exceeds restart intensity, dies with `:shutdown`, and the linked `ServiceClient` dies. The waiting task crashes with `:noproc` or `:shutdown`.
- If clients are **not** stopped, loops of 20+ async creations run cleanly, confirming the restart-intensity trigger.

## Root Cause
- Stopping supervised children directly (`GenServer.stop/1`) causes the supervisor to treat exits as failures and restart them. Repeated stops exceed restart limits, cascading into supervisor and parent shutdown. The async tasks then observe dead processes.

## Fix Options (choose one)
1) **Terminate via supervisor**  
   - Fetch client supervisor from service state (e.g., `:sys.get_state(service_pid).client_supervisor` or add a helper).  
   - Use `DynamicSupervisor.terminate_child/2` (and optionally `delete_child/2`) instead of `GenServer.stop/1` in tests/cleanup to avoid restart attempts.

2) **Make children temporary**  
   - Set sampling/training client child specs to `restart: :temporary` so user-managed clients do not restart. This removes restart storms even if `GenServer.stop/1` is used.

## Log Oddity Explained
- `config/test.exs` sets `Logger` level to `:warning`. The noisy run with `Retrying request...` and Telemetry attach warnings happened because `test/tinkex/api/api_test.exs` temporarily sets `Logger.configure(level: :debug)` inside a redaction test. Concurrent scheduling let other tests emit debug/info logs once; later runs reset to `:warning`, so logs disappeared.

## Next Steps for Fix
- Decide between supervisor-terminate approach vs. `restart: :temporary`.
- Update async client tests (and helpers) to use the chosen shutdown path.
- If adjusting child specs, ensure production intent matches (sampling/training clients likely should not be auto-restarted).
- Optionally confine the redaction test’s `Logger.configure` impact (run serially or tighten scope) to prevent surprise debug logs.
