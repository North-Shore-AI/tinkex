# Custom Loss Training (Live API)
#
# Demonstrates `forward_backward_custom/4` training with user-defined loss and
# gradients that are sent back to the Tinker backend. Shows compatibility with
# `optim_step/2` after the custom loss pass.
#
# Run with:
#   TINKER_API_KEY=your-key mix run examples/custom_loss_training.exs
#
# Optional environment:
#   TINKER_BASE_URL   - API endpoint (default: production)
#   TINKER_BASE_MODEL - Base model id (default: Llama-3.1-8B)

defmodule Tinkex.Examples.CustomLossTraining do
  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout 120_000

  alias Tinkex.Error
  alias Tinkex.Types.{AdamParams, Datum, ModelInput, TensorData}

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)

    IO.puts("""
    ================================================================================
    Custom Loss Training (Live)
    ================================================================================

    Base URL : #{base_url}
    Base model : #{base_model}
    """)

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, training} <- create_training_client(service, base_model),
         {:ok, datum} <- build_datum(training, base_model),
         {:ok, output} <- run_custom_loss(training, datum),
         :ok <- maybe_run_optim_step(training) do
      display_results(output)
    else
      {:error, %Error{} = error} ->
        halt_with_error("Failed to run custom loss training", error)

      {:error, other} ->
        halt("Failed to run custom loss training: #{inspect(other)}")
    end
  end

  defp create_training_client(service, base_model) do
    IO.puts("Creating training client...")

    Tinkex.ServiceClient.create_lora_training_client(
      service,
      base_model,
      lora_config: %Tinkex.Types.LoraConfig{rank: 16},
      call_timeout: @await_timeout
    )
  end

  defp build_datum(training, base_model) do
    prompt = "Name three planets in the solar system."
    IO.puts("Preparing training datum for prompt: #{prompt}")

    with {:ok, model_input} <-
           ModelInput.from_text(prompt, model_name: base_model, training_client: training) do
      tokens = first_chunk_tokens(model_input)

      datum =
        Datum.new(%{
          model_input: model_input,
          loss_fn_inputs: %{
            target_tokens: TensorData.from_nx(Nx.tensor(tokens, type: {:s, 64})),
            weights:
              TensorData.from_nx(Nx.tensor(List.duplicate(1.0, length(tokens)), type: {:f, 32}))
          }
        })

      {:ok, datum}
    end
  end

  defp run_custom_loss(training, datum) do
    IO.puts("\nRunning forward_backward_custom...")
    start_ms = System.monotonic_time(:millisecond)

    loss_fn = fn _data, [logprobs] ->
      # Simple negative log-likelihood; metrics include perplexity
      nll = Nx.negate(Nx.mean(logprobs))
      ppl = Nx.exp(nll)
      {nll, %{"custom_perplexity" => ppl}}
    end

    {:ok, task} = Tinkex.TrainingClient.forward_backward_custom(training, [datum], loss_fn)

    case Task.await(task, @await_timeout) do
      {:ok, output} ->
        duration = System.monotonic_time(:millisecond) - start_ms
        IO.puts("Custom loss completed in #{duration} ms")
        {:ok, output}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, other} ->
        {:error, Error.new(:request_failed, "Custom loss failed: #{inspect(other)}")}
    end
  end

  defp maybe_run_optim_step(training) do
    IO.puts("\nRunning optim_step...")

    with {:ok, adam} <- AdamParams.new(learning_rate: 1.0e-4),
         {:ok, task} <- Tinkex.TrainingClient.optim_step(training, adam),
         {:ok, _resp} <- Task.await(task, @await_timeout) do
      IO.puts("optim_step succeeded.")
      :ok
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, other} ->
        {:error, Error.new(:request_failed, "optim_step failed: #{inspect(other)}")}
    end
  end

  defp display_results(%Tinkex.Types.ForwardBackwardOutput{} = output) do
    IO.puts("\n=== ForwardBackwardOutput ===")
    IO.puts("loss_fn_output_type: #{output.loss_fn_output_type}")
    IO.puts("metrics: #{inspect(output.metrics)}")

    if output.loss_fn_outputs != [] do
      IO.puts("loss_fn_outputs (truncated):")
      IO.inspect(Enum.take(output.loss_fn_outputs, 1))
    end

    IO.puts("\nSuccess! Gradients were sent to the backend and optim_step is ready.")
  end

  defp first_chunk_tokens(%ModelInput{} = model_input), do: ModelInput.to_ints(model_input)

  defp fetch_env!(var) do
    case System.get_env(var) do
      nil -> halt("Set #{var} environment variable to run this example")
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

Tinkex.Examples.CustomLossTraining.run()
