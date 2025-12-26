defmodule Tinkex.Examples.ForwardInference do
  @moduledoc """
  Demonstrates the forward-only API for inference without backward pass.

  The `forward/4` function runs a forward pass and returns logprobs that can be
  converted to Nx tensors via `TensorData.to_nx/1`. This is useful for:

  - Custom loss computation where gradients are computed in Elixir/Nx
  - Inference-only workflows that need logprobs
  - Building custom training loops with EXLA-accelerated gradient computation

  ## Configuration

  - `TINKER_API_KEY` (required) - API authentication key
  - `TINKER_BASE_URL` (optional) - API endpoint URL
  - `TINKER_BASE_MODEL` (optional) - Model identifier, defaults to Llama-3.1-8B
  - `TINKER_PROMPT` (optional) - Prompt text for forward pass
  """

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout :infinity

  alias Tinkex.Error
  alias Tinkex.Types.TensorData

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)
    prompt = System.get_env("TINKER_PROMPT", "Hello from forward inference!")

    IO.puts("=== Forward Inference Example ===")
    IO.puts("Base URL: #{base_url}")
    IO.puts("Base model: #{base_model}")
    IO.puts("Prompt: #{prompt}")
    IO.puts("")

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, training} <- create_training_client(service, base_model),
         {:ok, model_input} <- build_model_input(prompt, base_model, training) do
      run_forward_pass(training, model_input)
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

  defp build_model_input(prompt, base_model, training) do
    IO.puts("Building model input from prompt...")
    Tinkex.Types.ModelInput.from_text(prompt, model_name: base_model, training_client: training)
  end

  defp run_forward_pass(training, model_input) do
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

    IO.puts("")
    IO.puts("Running forward pass (inference only, no backward)...")
    start_time = System.monotonic_time(:millisecond)

    # Use forward/4 instead of forward_backward/4 for inference-only
    # forward/4 always returns {:ok, task}
    {:ok, forward_task} = Tinkex.TrainingClient.forward(training, [datum], :cross_entropy)

    forward_output = await_task(forward_task, "forward")
    duration_ms = System.monotonic_time(:millisecond) - start_time

    IO.puts("")
    IO.puts("Forward pass completed in #{duration_ms}ms")
    IO.puts("Output type: #{forward_output.loss_fn_output_type}")
    IO.puts("Metrics: #{inspect(forward_output.metrics)}")
    IO.puts("Number of loss_fn_outputs: #{length(forward_output.loss_fn_outputs)}")

    # Demonstrate converting logprobs to Nx tensors
    demonstrate_nx_conversion(forward_output)
  end

  defp demonstrate_nx_conversion(forward_output) do
    IO.puts("")
    IO.puts("=== Nx Tensor Conversion Demo ===")
    IO.puts("Nx default backend: #{inspect(Nx.default_backend())}")

    case forward_output.loss_fn_outputs do
      [first_output | _] when is_map(first_output) ->
        # Check if logprobs data is available
        case first_output do
          %{"logprobs" => logprobs} when is_map(logprobs) ->
            convert_and_display_tensor(logprobs)

          %{logprobs: logprobs} when is_map(logprobs) ->
            convert_and_display_tensor(logprobs)

          _ ->
            IO.puts("First output keys: #{inspect(Map.keys(first_output))}")
            IO.puts("(Logprobs structure varies by loss function)")
        end

      [] ->
        IO.puts("No loss_fn_outputs returned")

      other ->
        IO.puts("Unexpected output format: #{inspect(other)}")
    end
  end

  defp convert_and_display_tensor(logprobs) do
    data = logprobs["data"] || logprobs[:data] || []
    dtype = parse_dtype(logprobs["dtype"] || logprobs[:dtype])
    shape = logprobs["shape"] || logprobs[:shape]

    if data != [] do
      tensor_data = %TensorData{
        data: data,
        dtype: dtype,
        shape: shape
      }

      nx_tensor = TensorData.to_nx(tensor_data)

      IO.puts("Converted to Nx tensor:")
      IO.puts("  Shape: #{inspect(Nx.shape(nx_tensor))}")
      IO.puts("  Type: #{inspect(Nx.type(nx_tensor))}")
      IO.puts("  First 5 values: #{inspect(Enum.take(Nx.to_flat_list(nx_tensor), 5))}")

      # Demonstrate EXLA operations on the tensor
      IO.puts("")
      IO.puts("EXLA-accelerated operations:")
      IO.puts("  Mean: #{Nx.mean(nx_tensor) |> Nx.to_number()}")
      IO.puts("  Min: #{Nx.reduce_min(nx_tensor) |> Nx.to_number()}")
      IO.puts("  Max: #{Nx.reduce_max(nx_tensor) |> Nx.to_number()}")
    else
      IO.puts("No logprobs data to convert")
    end
  end

  defp parse_dtype("float32"), do: :float32
  defp parse_dtype("float64"), do: :float32
  defp parse_dtype("int64"), do: :int64
  defp parse_dtype("int32"), do: :int64
  defp parse_dtype(atom) when is_atom(atom), do: atom
  defp parse_dtype(_), do: :float32

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

  defp first_chunk_tokens(%Tinkex.Types.ModelInput{chunks: [chunk | _]}) do
    Map.get(chunk, :tokens) || Map.get(chunk, "tokens") || []
  end

  defp first_chunk_tokens(_), do: []

  defp to_tensor(tokens, dtype) when is_list(tokens) do
    seq_len = length(tokens)
    %TensorData{data: tokens, dtype: dtype, shape: [seq_len]}
  end

  defp to_tensor(_, dtype), do: %TensorData{data: [], dtype: dtype, shape: [0]}
end

Tinkex.Examples.ForwardInference.run()
