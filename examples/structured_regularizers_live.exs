# Structured Regularizers - Live API Example
#
# Demonstrates custom loss computation with composable regularizers
# using the live Tinker API.
#
# Run with: TINKER_API_KEY=your-key mix run examples/structured_regularizers_live.exs
#
# Environment Variables:
#   TINKER_API_KEY (required) - API authentication key
#   TINKER_BASE_URL (optional) - API endpoint URL
#   TINKER_BASE_MODEL (optional) - Model identifier, defaults to Llama-3.1-8B

defmodule Tinkex.Examples.StructuredRegularizersLive do
  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout 120_000

  alias Tinkex.Error
  alias Tinkex.Types.TensorData

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)

    IO.puts("""
    ================================================================================
    Structured Regularizers - Live API Example
    ================================================================================

    Base URL: #{base_url}
    Model: #{base_model}
    """)

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, training} <- create_training_client(service, base_model),
         {:ok, datum} <- build_training_datum(training, base_model) do
      run_custom_loss_with_regularizers(training, datum)
    else
      {:error, %Error{} = error} ->
        halt_with_error("Initialization failed", error)

      {:error, other} ->
        halt("Initialization failed: #{inspect(other)}")
    end
  end

  defp create_training_client(service, base_model) do
    IO.puts("Creating training client...")

    Tinkex.ServiceClient.create_lora_training_client(service, base_model,
      lora_config: %Tinkex.Types.LoraConfig{rank: 16}
    )
  end

  defp build_training_datum(training, base_model) do
    prompt = "The quick brown fox jumps over the lazy dog."
    IO.puts("Building training datum from prompt: #{prompt}")

    case Tinkex.Types.ModelInput.from_text(prompt,
           model_name: base_model,
           training_client: training
         ) do
      {:ok, model_input} ->
        target_tokens = first_chunk_tokens(model_input)
        IO.puts("Token count: #{length(target_tokens)}")

        datum =
          Tinkex.Types.Datum.new(%{
            model_input: model_input,
            loss_fn_inputs: %{
              target_tokens: to_tensor(target_tokens, :int64),
              weights: to_tensor(List.duplicate(1.0, length(target_tokens)), :float32)
            }
          })

        {:ok, datum}

      {:error, _} = error ->
        error
    end
  end

  defp run_custom_loss_with_regularizers(training, datum) do
    IO.puts("\n--- Defining Custom Loss + Regularizers ---\n")

    loss_fn = fn _data, [logprobs] ->
      base = Nx.negate(Nx.mean(logprobs))
      l1 = Nx.multiply(0.01, Nx.sum(Nx.abs(logprobs)))
      probs = Nx.exp(logprobs)
      entropy = Nx.sum(Nx.multiply(probs, logprobs))
      entropy_term = Nx.multiply(0.001, entropy)

      total =
        base
        |> Nx.add(l1)
        |> Nx.add(entropy_term)

      metrics = %{
        "base_nll" => base,
        "l1" => l1,
        "entropy" => entropy_term,
        "custom_perplexity" => Nx.exp(base)
      }

      {total, metrics}
    end

    IO.puts("\n--- Running forward_backward_custom (Live API) ---\n")
    start_time = System.monotonic_time(:millisecond)

    {:ok, task} = Tinkex.TrainingClient.forward_backward_custom(training, [datum], loss_fn)

    case Task.await(task, @await_timeout) do
      {:ok, output} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        display_results(output, duration_ms)

      {:error, %Error{} = error} ->
        halt_with_error("Custom loss computation failed", error)

      {:error, other} ->
        halt("Custom loss computation failed: #{inspect(other)}")
    end
  end

  defp display_results(output, duration_ms) do
    IO.puts("Completed in #{duration_ms}ms\n")

    IO.puts("=== Metrics ===")
    Enum.each(output.metrics, fn {k, v} -> IO.puts("#{k}: #{Float.round(v, 6)}") end)

    IO.puts("\n================================================================================")
    IO.puts("Success! Custom loss with regularizer terms computed via live Tinker API.")
    IO.puts("================================================================================")
  end

  # Helpers

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

  defp first_chunk_tokens(%Tinkex.Types.ModelInput{chunks: [chunk | _]}) do
    Map.get(chunk, :tokens) || Map.get(chunk, "tokens") || []
  end

  defp first_chunk_tokens(_), do: []

  defp to_tensor(tokens, dtype) when is_list(tokens) do
    %TensorData{data: tokens, dtype: dtype, shape: [length(tokens)]}
  end

  defp to_tensor(_, dtype), do: %TensorData{data: [], dtype: dtype, shape: [0]}
end

Tinkex.Examples.StructuredRegularizersLive.run()
