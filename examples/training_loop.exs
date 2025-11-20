{:ok, _} = Application.ensure_all_started(:tinkex)

config =
  Tinkex.Config.new(
    api_key: System.get_env("TINKER_API_KEY"),
    base_url:
      System.get_env(
        "TINKER_BASE_URL",
        "https://tinker.thinkingmachines.dev/services/tinker-prod"
      )
  )

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

{:ok, training} =
  Tinkex.ServiceClient.create_lora_training_client(service,
    base_model: System.get_env("TINKER_BASE_MODEL", "meta-llama/Meta-Llama-3-8B"),
    lora_config: %Tinkex.Types.LoraConfig{rank: 16}
  )

{:ok, model_input} =
  Tinkex.Types.ModelInput.from_text(
    "Fine-tuning sample prompt",
    model_name: "meta-llama/Meta-Llama-3-8B",
    training_client: training
  )

datum = %Tinkex.Types.Datum{
  model_input: model_input,
  loss_fn_inputs: %{"target_tokens" => [1, 2, 3]}
}

loop_start = System.monotonic_time(:millisecond)

{:ok, fb_task} = Tinkex.TrainingClient.forward_backward(training, [datum], :cross_entropy)
{:ok, fb_output} = Task.await(fb_task, 60_000)
IO.inspect(fb_output.metrics, label: "forward_backward metrics")

{:ok, optim_task} = Tinkex.TrainingClient.optim_step(training, %Tinkex.Types.AdamParams{})
{:ok, optim_output} = Task.await(optim_task, 60_000)
IO.inspect(optim_output.metrics, label: "optim_step metrics")

{:ok, save_task} = Tinkex.TrainingClient.save_weights_for_sampler(training)
{:ok, save_result} = Task.await(save_task, 60_000)
IO.inspect(save_result, label: "save_weights_for_sampler response")

duration_ms = System.monotonic_time(:millisecond) - loop_start
IO.puts("Training loop finished in #{duration_ms} ms")
