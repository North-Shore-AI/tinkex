# Custom Loss Training

Tinkex supports custom loss training that mirrors the Python SDK’s `forward_backward_custom_async`: it performs a forward pass to obtain per-datum logprobs, runs your Nx loss function, computes gradients, sends them back as synthetic weights, and returns a `ForwardBackwardOutput` that can be passed directly into `optim_step/2`.

## Prerequisites

- `TINKER_API_KEY` exported
- Optional: `TINKER_BASE_URL`, `TINKER_BASE_MODEL`
- A training client (e.g., `ServiceClient.create_lora_training_client/3`)

## Loss Function Signature

```elixir
loss_fn :: (list(Datum.t()), [Nx.Tensor.t()] -> {Nx.Tensor.t(), map()})
```

- The second argument is a **list of logprob tensors, one per datum** (no flattening).
- Return a scalar loss tensor and a metrics map. Tensor metrics are converted via `Nx.to_number/1`.

## Minimal Workflow

```elixir
loss_fn = fn _data, [logprobs] ->
  nll = Nx.negate(Nx.mean(logprobs))
  {nll, %{"custom_perplexity" => Nx.exp(nll) |> Nx.to_number()}}
end

{:ok, task} = Tinkex.TrainingClient.forward_backward_custom(training_client, data, loss_fn)
{:ok, %Tinkex.Types.ForwardBackwardOutput{} = out} = Task.await(task)
IO.inspect(out.metrics) # includes "loss" plus your custom metrics

{:ok, adam} = Tinkex.Types.AdamParams.new(learning_rate: 1.0e-4)
{:ok, step_task} = Tinkex.TrainingClient.optim_step(training_client, adam)
{:ok, _resp} = Task.await(step_task)
```

The backend receives gradients as `weights` in a synthetic cross-entropy pass, so training actually occurs. The returned output is compatible with `optim_step/2` and any downstream metric reducers.

## End-to-End Example

Run the live example with your API key:

```bash
TINKER_API_KEY=... mix run examples/custom_loss_training.exs
```

This script:
1. Builds a LoRA training client
2. Prepares a datum with `target_tokens`
3. Runs `forward_backward_custom/4` with a user-defined loss
4. Executes `optim_step/2` on the resulting gradients

## Tips

- Keep losses scalar; wrap non-scalar returns with `Nx.sum/1` or `Nx.mean/1`.
- Gradients are computed per datum; ensure the returned list matches the input data order.
- Metrics merge into the server-provided metrics map (keys are stringified).
