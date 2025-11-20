defmodule Tinkex.Examples.TrainingLoop do
  @moduledoc false

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout 60_000

  alias Tinkex.Error

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)
    prompt = System.get_env("TINKER_PROMPT", "Fine-tuning sample prompt")

    IO.puts("Base URL: #{base_url}")
    IO.puts("Base model: #{base_model}")

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, training} <- create_training_client(service, base_model),
         {:ok, model_input} <- build_model_input(prompt, base_model, training) do
      run_training_steps(training, model_input)
    else
      {:error, %Error{} = error} ->
        halt_with_error("Initialization failed", error)

      {:error, other} ->
        halt("Initialization failed: #{inspect(other)}")
    end
  end

  defp create_training_client(service, base_model) do
    Tinkex.ServiceClient.create_lora_training_client(service,
      base_model: base_model,
      lora_config: %Tinkex.Types.LoraConfig{rank: 16}
    )
  end

  defp build_model_input(prompt, base_model, training) do
    Tinkex.Types.ModelInput.from_text(prompt, model_name: base_model, training_client: training)
  end

  defp run_training_steps(training, model_input) do
    datum = %Tinkex.Types.Datum{
      model_input: model_input,
      # Server expects string keys for loss_fn_inputs.
      loss_fn_inputs: %{"target_tokens" => [1, 2, 3]}
    }

    loop_start = System.monotonic_time(:millisecond)

    fb_task =
      start_task(
        Tinkex.TrainingClient.forward_backward(training, [datum], :cross_entropy),
        "forward_backward"
      )

    fb_output = await_task(fb_task, "forward_backward")
    IO.inspect(fb_output.metrics, label: "forward_backward metrics")

    optim_task =
      start_task(
        Tinkex.TrainingClient.optim_step(training, %Tinkex.Types.AdamParams{}),
        "optim_step"
      )

    optim_output = await_task(optim_task, "optim_step")
    IO.inspect(optim_output.metrics, label: "optim_step metrics")

    save_task =
      start_task(
        Tinkex.TrainingClient.save_weights_for_sampler(training),
        "save_weights_for_sampler"
      )

    save_result = await_task(save_task, "save_weights_for_sampler")
    IO.inspect(save_result, label: "save_weights_for_sampler response")

    duration_ms = System.monotonic_time(:millisecond) - loop_start
    IO.puts("Training loop finished in #{duration_ms} ms")
  end

  defp start_task({:ok, task}, _label), do: task

  defp start_task({:error, %Error{} = error}, label),
    do: halt_with_error("#{label} failed", error)

  defp start_task(other, label), do: halt("#{label} failed: #{inspect(other)}")

  defp await_task(task, label) do
    try do
      case Task.await(task, @await_timeout) do
        {:ok, result} ->
          result

        {:error, %Error{} = error} ->
          halt_with_error("#{label} error", error)

        other ->
          halt("#{label} returned unexpected response: #{inspect(other)}")
      end
    catch
      :exit, reason ->
        halt("#{label} task exited: #{inspect(reason)}")
    end
  end

  defp fetch_env!(var) do
    case System.get_env(var) do
      nil -> halt("Set #{var} to run this example")
      value -> value
    end
  end

  defp halt_with_error(prefix, %Error{} = error) do
    IO.puts(:stderr, "#{prefix}: #{Error.format(error)}")
    if error.data, do: IO.puts(:stderr, "Error data: #{inspect(error.data)}")
    System.halt(1)
  end

  defp halt(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end

Tinkex.Examples.TrainingLoop.run()
