# Tinkex OTP Compliance Audit Report

## Executive Summary

Based on analysis of the codebase and the flake diagnosis, I've identified several OTP violations and anti-patterns that contribute to process lifecycle issues, orphaned processes, and incorrect supervision tree design.

---

## Critical Issues

### 1. **Unsupervised Task Spawns in Hot Paths**

**Location:** `tinkex/api/telemetry.ex:38-54`

```elixir
def send(request, opts) do
  # ...
  Task.start(fn ->
    try do
      # HTTP request
    rescue
      exception ->
        Logger.error(...)
    end
  end)
  :ok
end
```

**Violation:** `Task.start/1` creates an unlinked, unsupervised process. If the parent dies or the application shuts down, these tasks become orphaned and may continue executing or leak resources.

**Impact:** During shutdown, telemetry requests may be in-flight with no supervision. The `rescue` block masks failures that should propagate.

**Fix:** Use `Task.Supervisor.start_child/2` with a dedicated `Task.Supervisor` started in `Tinkex.Application`.

---

### 2. **Manual Process Spawning in Training/Sampling Clients**

**Location:** `tinkex/training_client.ex:204-235`, `tinkex/sampling_client.ex`

```elixir
Task.start(fn ->
  reply =
    try do
      # polling logic
    rescue
      e -> {:error, ...}
    end

  try do
    GenServer.reply(from, reply)
  rescue
    ArgumentError -> :ok
  end
end)
```

**Violations:**
1. `Task.start/1` creates unsupervised processes
2. The `rescue ArgumentError -> :ok` pattern silently swallows failures when the caller is gone
3. `unlink_task/1` explicitly unlinks polling tasks, breaking the supervision tree's failure propagation

**Impact:** If the GenServer crashes, orphaned tasks continue polling. If tasks crash, the GenServer doesn't know. This creates zombie processes and resource leaks.

**Fix:** 
- Use `Task.Supervisor` for polling tasks
- Consider `Task.async_nolink` with proper monitoring instead of manual unlinking
- Remove silent exception swallowing

---

### 3. **Incorrect Child Restart Strategy**

**Location:** `tinkex/service_client.ex:153-159`, `tinkex/application.ex`

```elixir
# In ServiceClient
case DynamicSupervisor.start_child(
       state.client_supervisor,
       {state.training_client_module, child_opts}
     ) do
```

**Violation:** Training and Sampling clients are started under a `DynamicSupervisor` with default `:permanent` restart strategy. These are user-initiated, transient operations that should NOT auto-restart.

**Impact:** As documented in the flake analysis, stopping clients triggers restart attempts, exceeding `max_restarts` and cascading failures.

**Fix:** Set child specs to `restart: :temporary`:

```elixir
def child_spec(opts) do
  %{
    id: __MODULE__,
    start: {__MODULE__, :start_link, [opts]},
    restart: :temporary,  # Not :permanent
    shutdown: 5000,
    type: :worker
  }
end
```

---

### 4. **Local DynamicSupervisor Creation Without Proper Lifecycle**

**Location:** `tinkex/service_client.ex:121-127`

```elixir
defp ensure_client_supervisor(:local) do
  DynamicSupervisor.start_link(strategy: :one_for_one)
end
```

**Violation:** Creates an orphaned supervisor not in the application supervision tree. When `ServiceClient` terminates, this supervisor and all its children become orphaned.

**Impact:** Resource leaks, orphaned processes, no graceful shutdown.

**Fix:** Either:
1. Link the supervisor to `ServiceClient` (fragile)
2. Use the global `Tinkex.ClientSupervisor` from the application tree
3. Make the local supervisor a child of `ServiceClient` (complex)

---

### 5. **Missing Supervisor in Application Tree for Dynamic Components**

**Location:** `tinkex/application.ex:57-61`

```elixir
defp base_children(heartbeat_interval_ms, heartbeat_warning_after_ms) do
  [
    Tinkex.Metrics,
    Tinkex.SamplingRegistry,
    {Tinkex.SessionManager, ...},
    {DynamicSupervisor, name: Tinkex.ClientSupervisor, strategy: :one_for_one}
  ]
end
```

**Issues:**
1. No `Task.Supervisor` for async operations
2. `Tinkex.ClientSupervisor` uses default `max_restarts: 3, max_seconds: 5` which is too aggressive for user-initiated operations

**Fix:** Add a `Task.Supervisor` and adjust restart intensity:

```elixir
defp base_children(...) do
  [
    Tinkex.Metrics,
    Tinkex.SamplingRegistry,
    {Task.Supervisor, name: Tinkex.TaskSupervisor},
    {Tinkex.SessionManager, ...},
    {DynamicSupervisor, 
     name: Tinkex.ClientSupervisor, 
     strategy: :one_for_one,
     max_restarts: 0}  # No auto-restart for user clients
  ]
end
```

---

### 6. **Process Linking Without Proper Error Handling**

**Location:** `tinkex/sampling_registry.ex:29-33`

```elixir
def handle_call({:register, pid, config}, _from, state) do
  ref = Process.monitor(pid)
  :ets.insert(:tinkex_sampling_clients, {{:config, pid}, config})
  {:reply, :ok, %{state | monitors: Map.put(state.monitors, ref, pid)}}
end
```

**Issue:** Uses monitoring correctly, but the ETS cleanup in `:DOWN` handler doesn't handle race conditions where the process dies before registration completes.

---

### 7. **Telemetry Reporter Process Lifecycle Issues**

**Location:** `tinkex/telemetry/reporter.ex`

```elixir
def stop(pid, timeout \\ 5_000)
def stop(nil, _timeout), do: false
def stop(pid, timeout) do
  GenServer.stop(pid, :normal, timeout)
catch
  :exit, _ -> false
end
```

**Issue:** The `catch :exit` silently swallows all exit reasons, including ones that should propagate (e.g., brutal kills during testing).

---

### 8. **ETS Table Creation Race Conditions**

**Location:** `tinkex/application.ex:27-44`, `tinkex/service_client.ex:108-119`

```elixir
defp create_table(name, options) do
  case :ets.whereis(name) do
    :undefined -> :ets.new(name, options)
    _ -> name
  end
end
```

**Violation:** TOCTOU (time-of-check-time-of-use) race. Between `whereis` and `new`, another process could create the table.

**Fix:** Use try/rescue pattern:

```elixir
defp create_table(name, options) do
  try do
    :ets.new(name, options)
  rescue
    ArgumentError -> name  # Already exists
  end
end
```

---

### 9. **Heartbeat Timer Not Canceled on Terminate**

**Location:** `tinkex/session_manager.ex`

```elixir
defp schedule_heartbeat(interval_ms) do
  Process.send_after(self(), :heartbeat, interval_ms)
end
```

**Issue:** Timer reference stored but never canceled in `terminate/2`. Stale messages could arrive at a restarted process.

**Fix:** Cancel timer in terminate:

```elixir
def terminate(_reason, %{timer_ref: ref}) when is_reference(ref) do
  Process.cancel_timer(ref)
  :ok
end
```

---

### 10. **Incorrect Recovery Strategy for Session-Based Operations**

**Location:** `tinkex/session_manager.ex`

The `SessionManager` continues heartbeating failed sessions indefinitely with only warnings. Sessions that persistently fail should eventually be dropped or escalated.

---

## Supervision Tree Issues

### Current Structure (Problematic)

```
Tinkex.Supervisor (one_for_one)
├── Finch pool (if enabled)
├── Tinkex.Metrics
├── Tinkex.SamplingRegistry
├── Tinkex.SessionManager
└── Tinkex.ClientSupervisor (DynamicSupervisor, permanent children)
    ├── TrainingClient (permanent - WRONG)
    └── SamplingClient (permanent - WRONG)

ServiceClient (not supervised by Application!)
└── Local DynamicSupervisor (orphaned!)
    ├── TrainingClient
    └── SamplingClient
```

### Recommended Structure

```
Tinkex.Supervisor (one_for_one)
├── Finch pool (if enabled)
├── Tinkex.Metrics
├── Tinkex.SamplingRegistry
├── Tinkex.SessionManager
├── Tinkex.TaskSupervisor (Task.Supervisor for async work)
└── Tinkex.ClientSupervisor (DynamicSupervisor)
    ├── ServiceClient (temporary, user-initiated)
    │   └── (uses Tinkex.ClientSupervisor for children)
    ├── TrainingClient (temporary)
    └── SamplingClient (temporary)
```

---

## Summary of Required Fixes

| Priority | Issue | Fix |
|----------|-------|-----|
| P0 | Child restart strategy | Set `restart: :temporary` for all client GenServers |
| P0 | Unsupervised Task.start | Add `Task.Supervisor`, use `Task.Supervisor.start_child` |
| P1 | Orphaned local supervisors | Use shared `Tinkex.ClientSupervisor` |
| P1 | Manual process unlinking | Remove `unlink_task/1`, use proper supervision |
| P2 | ETS table races | Use try/rescue pattern |
| P2 | Timer cleanup | Cancel timers in terminate callbacks |
| P3 | Silent exception swallowing | Log or propagate errors properly |

---

## Test Fix (Immediate)

To fix the flake without larger refactoring:

```elixir
# In test helpers
def stop_sampling_client(service_pid, client_pid) do
  # Get supervisor from service state
  %{client_supervisor: sup} = :sys.get_state(service_pid)
  DynamicSupervisor.terminate_child(sup, client_pid)
end
```

Or set temporary restart in child specs (recommended for production correctness anyway).
