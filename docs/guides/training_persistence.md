# Training Persistence

Save, load, and resume training checkpoints with or without optimizer state. This guide covers the TrainingClient and ServiceClient helpers that mirror the Python SDK.

## Saving Checkpoints

Save a named checkpoint; the server returns a `tinker://` path you can store.

```elixir
{:ok, task} = Tinkex.TrainingClient.save_state(training_client, "checkpoint-001")
{:ok, %Tinkex.Types.SaveWeightsResponse{path: path}} = Task.await(task)
IO.puts("Saved to: #{path}")
```

Tips:
- Use descriptive names (e.g., `"epoch-3-loss-1.23"`).
- Call periodically (every N steps or minutes) to bound loss of progress.

## Loading Checkpoints

### Weights Only

Use when transferring weights or changing optimizer/hparams:

```elixir
{:ok, task} = Tinkex.TrainingClient.load_state(
  training_client,
  "tinker://run-id/weights/checkpoint-001"
)
{:ok, _} = Task.await(task)
```

### Weights + Optimizer

Use to resume training exactly where it left off:

```elixir
{:ok, task} = Tinkex.TrainingClient.load_state_with_optimizer(
  training_client,
  "tinker://run-id/weights/checkpoint-001"
)
{:ok, _} = Task.await(task)
```

## Create a Training Client From a Checkpoint

Let the ServiceClient derive model config from checkpoint metadata and load it:

```elixir
{:ok, training_client} =
  Tinkex.ServiceClient.create_training_client_from_state(
    service_client,
    "tinker://run-id/weights/checkpoint-001",
    load_optimizer: true
  )
```

What happens:
1) Fetch checkpoint metadata (`base_model`, LoRA rank).
2) Start a new TrainingClient with matching config.
3) Load weights (and optimizer if requested).

## Failure Handling

- Requests are sequentially ordered via `seq_id`; the GenServer will reply with `{:error, %Tinkex.Error{}}` on transport or server failures.
- `load_state*` background polling is unbounded by default; pass `await_timeout:` if you want a cap.
- If `create_training_client_from_state/3` fails to load, the temporary client is killed to avoid leaks.

## Compatibility Notes

- Wire protocol uses `optimizer: boolean()` (not `load_optimizer_state`).
- Checkpoints are referenced with the `tinker://run-id/weights/checkpoint-id` scheme.
- Cross-language parity: checkpoints created in Python can be loaded in Elixir and vice versa.
