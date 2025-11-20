# TODO: Session lifecycle & heartbeat cleanup

## Context
- During end-to-end runs (training loop, CLI sampling), we see warnings like:
  - `Session <id> expired: [api_status (404)] HTTP 404`
- This is emitted by `SessionManager` when a heartbeat gets a 404.
- All core operations (forward_backward, optim_step, save_weights_for_sampler, sampling) already succeed before the warning.

## Likely root cause
- The server expires/garbage-collects sessions quickly once work is done.
- The client keeps heartbeating after the workflow finishes, so the next heartbeat hits a 404 and we log a warning.
- We never explicitly stop the session at the end of a one-shot workflow (examples/CLI), so SessionManager continues until it learns the session is gone.

## Risks
- No functional impact for the completed workflow, but noisy logs and potential confusion for users/operators.
- If the server enforces strict session lifetimes, heartbeats after completion don’t add value and just generate 404s.

## Candidate fixes (client-side)
1) Explicit session teardown in one-shot flows
   - Examples/CLI: call `SessionManager.stop_session(session_id)` (or stop the service client) once the workflow completes.
   - Training loop example: stop/cleanup after save + optional sampling.
2) Heartbeat handling
   - Treat a heartbeat 404 as “session already gone; drop quietly” (log at info/debug, not warning) and stop further heartbeats for that session.
   - Optionally shorten heartbeat interval or send a final heartbeat immediately after creation if we need to keep it warm.
3) Session scoping
   - Use per-workflow sessions by default; avoid long-lived sessions in examples so tear-down is deterministic.
4) Optional server-side ask
   - If the server intends to keep sessions alive during work, consider slightly longer TTL or a “finalize” endpoint instead of heartbeating post-completion.

## Suggested next steps
- Update examples/CLI to explicitly stop sessions or stop the service client at the end.
- Adjust SessionManager heartbeat handling to downgrade 404 to info + drop session without warning.
- Verify with server expectations: is session expiry immediate after work? If yes, prefer explicit teardown and quieter logs; if not, align client heartbeat interval/stop conditions with server TTL.
