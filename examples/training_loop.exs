defmodule Tinkex.Examples.TrainingLoop do
  @moduledoc false

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout 60_000

  alias Tinkex.Error
  alias Tinkex.Types.TensorData

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)
    prompt = System.get_env("TINKER_PROMPT", "Fine-tuning sample prompt")
    sample_after? = System.get_env("TINKER_SAMPLE_AFTER_TRAIN", "0") not in ["0", "false", nil]
    sample_prompt = System.get_env("TINKER_SAMPLE_PROMPT", "Hello from fine-tuned weights!")

    IO.puts("Base URL: #{base_url}")
    IO.puts("Base model: #{base_model}")

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, training} <- create_training_client(service, base_model),
         {:ok, model_input} <- build_model_input(prompt, base_model, training) do
      run_training_steps(service, training, model_input, base_model, sample_after?, sample_prompt)
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

  defp run_training_steps(
         service,
         training,
         model_input,
         base_model,
         sample_after?,
         sample_prompt
       ) do
    target_tokens = first_chunk_tokens(model_input)

    datum =
      Tinkex.Types.Datum.new(%{
        model_input: model_input,
        # Server expects loss_fn_inputs values as tensors with dtype/shape.
        loss_fn_inputs: %{
          target_tokens: to_tensor(target_tokens, :int64),
          weights: to_tensor(List.duplicate(1.0, length(target_tokens)), :float32)
        }
      })

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

    if sample_after? do
      sample_with_saved_weights(service, save_result, base_model, sample_prompt)
    end

    duration_ms = System.monotonic_time(:millisecond) - loop_start
    IO.puts("Training loop finished in #{duration_ms} ms")
  end

  defp start_task(result, label) do
    case result do
      {:ok, task} ->
        task

      {:error, %Error{} = error} ->
        halt_with_error("#{label} failed", error)

      other ->
        halt("#{label} failed: #{inspect(other)}")
    end
  end

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

  defp sample_with_saved_weights(service, save_result, base_model, sample_prompt)
       when is_map(save_result) do
    model_path = save_result["path"] || save_result[:path]
    sampling_session_id = save_result["sampling_session_id"] || save_result[:sampling_session_id]

    case create_sampler(service, model_path, sampling_session_id, base_model) do
      {:ok, sampler} ->
        do_sample(sampler, base_model, sample_prompt)

      {:error, reason} ->
        IO.puts(:stderr, "Skipping sampling; failed to create sampler: #{inspect(reason)}")
    end
  end

  defp sample_with_saved_weights(_service, _save_result, _base_model, _prompt), do: :ok

  defp create_sampler(service, model_path, _sampling_session_id, base_model) do
    opts =
      if model_path do
        [model_path: model_path, base_model: base_model]
      else
        # Fall back to base_model-only sampler if no path returned.
        [base_model: base_model]
      end
      |> maybe_put_sampling_session_seq_id()

    case Tinkex.ServiceClient.create_sampling_client(service, opts) do
      {:ok, sampler} -> {:ok, sampler}
      {:error, _} = error -> error
    end
  end

  defp maybe_put_sampling_session_seq_id(opts) do
    # Use first sampler seq_id for simplicity.
    Keyword.put_new(opts, :sampling_session_seq_id, 0)
  end

  defp do_sample(sampler, base_model, prompt) do
    {:ok, model_input} = Tinkex.Types.ModelInput.from_text(prompt, model_name: base_model)
    params = %Tinkex.Types.SamplingParams{max_tokens: 32, temperature: 0.7}

    with {:ok, task} <-
           Tinkex.SamplingClient.sample(sampler, model_input, params,
             num_samples: 1,
             prompt_logprobs: false
           ),
         {:ok, response} <- Task.await(task, 30_000) do
      [seq | _] = response.sequences
      text = decode(seq.tokens, base_model)
      IO.puts("Sample from saved weights: #{text}")
    else
      {:error, error} ->
        IO.puts(:stderr, "Sampling after train failed: #{inspect(error)}")
    end
  end

  defp decode(tokens, model_name) do
    case Tinkex.Tokenizer.decode(tokens, model_name) do
      {:ok, text} -> text
      {:error, reason} -> "[decode failed: #{inspect(reason)}]"
    end
  end
end

Tinkex.Examples.TrainingLoop.run()
