# Training Loop Vertical Slice

Use this flow to exercise the full training pipeline against staging or local mocks. All calls go through the public clients (`ServiceClient` → `TrainingClient`), so sequencing and chunking match production behavior.

```elixir
{:ok, _} = Application.ensure_all_started(:tinkex)

config =
  Tinkex.Config.new(
    api_key: System.get_env("TINKER_API_KEY"),
    base_url: System.get_env("TINKER_BASE_URL", "https://tinker.thinkingmachines.dev/services/tinker-prod")
  )

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service, base_model: "meta-llama/Meta-Llama-3-8B")

{:ok, prompt} =
  Tinkex.Types.ModelInput.from_text(
    "Fine-tuning sample prompt",
    model_name: "meta-llama/Meta-Llama-3-8B",
    training_client: training
  )

datum = %Tinkex.Types.Datum{model_input: prompt}
started_ms = System.monotonic_time(:millisecond)

{:ok, fb_task} = Tinkex.TrainingClient.forward_backward(training, [datum], :cross_entropy)
{:ok, fb} = Task.await(fb_task, 60_000)

{:ok, optim_task} = Tinkex.TrainingClient.optim_step(training, %Tinkex.Types.AdamParams{})
{:ok, optim} = Task.await(optim_task, 60_000)

{:ok, save_task} = Tinkex.TrainingClient.save_weights_for_sampler(training)
{:ok, save} = Task.await(save_task, 60_000)

IO.inspect({fb.metrics, optim.metrics, save}, label: "training loop outputs")
IO.puts("end-to-end loop finished in #{System.monotonic_time(:millisecond) - started_ms} ms")
```

- `forward_backward/4` automatically chunks large batches (128 examples or 500k tokens) and reduces metrics with weighted means/sums.
- Every training action shares the same sequence counter; the example above yields sequential `seq_id` values for forward/backward chunks, optim, and save-weights.
- `save_weights_for_sampler/2` accepts optional `:path` / `:sampling_session_seq_id` values if you need deterministic artifact names. The call will poll futures when the server responds with a `request_id`.
