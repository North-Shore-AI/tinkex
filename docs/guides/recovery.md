# Recovery and Checkpoint Restart (Opt-in)

The recovery layer is **disabled by default**. It lets you detect corrupted training runs and restart from checkpoints automatically using explicit, user-controlled processes.

## Components

- `Tinkex.Recovery.Policy` – configuration (defaults off, conservative backoff, optimizer restore on)
- `Tinkex.Recovery.Monitor` – polls `Rest.get_training_run/2` for `corrupted: true`
- `Tinkex.Recovery.Executor` – bounded worker that restarts runs from checkpoints

Telemetry events: `:detected`, `:started`, `:checkpoint_selected`, `:client_created`, `:completed`, `:failed`, `:exhausted`, `:poll_error` (all under `[:tinkex, :recovery, ...]`).

## Quickstart

```elixir
config = Tinkex.Config.new(api_key: api_key, recovery: %{enabled: true})

policy =
  Tinkex.Recovery.Policy.new(
    enabled: true,
    checkpoint_strategy: :latest,        # or {:specific, "tinker://..."}
    restore_optimizer: true,             # false for weights-only
    poll_interval_ms: 15_000,
    max_attempts: 3,
    backoff_ms: 5_000,
    max_backoff_ms: 60_000,
    on_recovery: fn old_pid, new_pid, cp ->
      Logger.info("Recovered #{cp.tinker_path} -> #{inspect(new_pid)} (old=#{inspect(old_pid)})")
      :ok
    end,
    on_failure: fn run_id, reason ->
      Logger.warning("Recovery failed for #{run_id}: #{inspect(reason)}")
      :ok
    end
  )

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

{:ok, executor} =
  Tinkex.Recovery.Executor.start_link(
    max_concurrent: 2
  )

{:ok, monitor} =
  Tinkex.Recovery.Monitor.start_link(
    executor: executor,
    policy: policy
  )

:ok = Tinkex.Recovery.Monitor.monitor_run(monitor, "run-123", service, %{training_pid: training_pid})
```

## Checkpoint Strategy

- `:latest` (default): uses `TrainingRun.last_checkpoint`
- `{:specific, path}`: explicit checkpoint path
- `:best`: reserved for future support

If `last_checkpoint` is missing, the executor will fetch the run via REST (requires passing `config`).

## Optimizer Restore

`restore_optimizer: true` uses `ServiceClient.create_training_client_from_state_with_optimizer/3`. Set to `false` for weights-only restarts (fresh optimizer).

## Concurrency and Backoff

- `max_concurrent` (executor option) caps simultaneous recoveries (default: 1).
- `max_attempts`, `backoff_ms`, `max_backoff_ms` control retry behavior; `:exhausted` is emitted when attempts are spent.

## Telemetry and Observability

Attach handlers to `[:tinkex, :recovery, *]` for tracing. `:poll_error` indicates REST polling issues (monitor keeps state).

## Safety Notes

- Nothing runs automatically; you must start monitor/executor and set `policy.enabled: true`.
- Callbacks should be cheap and resilient; errors are swallowed to avoid cascading failures.
- Ensure `config` is available for REST lookups when monitor/executor are used outside the original process.

## Offline Example

Run `mix run examples/recovery_simulated.exs` to see a fully offline flow that seeds a checkpoint, flips a run to `corrupted: true`, and exercises the monitor + executor with stubbed REST/service modules. No network or API key is required.

## Live Example with Injected Corruption

Run `mix run examples/recovery_live_injected.exs` to create a training run, save a real checkpoint, inject a single `corrupted: true` poll response (no server change), and let the monitor + executor restore from that checkpoint. The example then saves a second checkpoint from the recovered client to prove the restart path. Requires `TINKER_API_KEY` (and optional `TINKER_BASE_URL`/`TINKER_BASE_MODEL`).
