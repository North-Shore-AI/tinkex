defmodule Tinkex.Examples.SaveWeightsAndSample do
  @moduledoc """
  Demonstrates the synchronous helper `TrainingClient.save_weights_and_get_sampling_client_sync/2`.

  Saves sampler weights (or performs an ephemeral sampler save), instantiates a
  `SamplingClient`, and performs a sample using the freshly saved weights.
  """

  alias Tinkex.{Config, Error, ServiceClient, Tokenizer, TrainingClient}
  alias Tinkex.Types.{ModelInput, SamplingParams}

  @default_model "Qwen/Qwen3-8B"
  @default_prompt "Hello from Tinkex!"
  @default_max_tokens 32

  def run do
    base_model = System.get_env("TINKER_BASE_MODEL") || @default_model
    prompt_text = System.get_env("TINKER_PROMPT") || @default_prompt
    max_tokens = parse_int(System.get_env("TINKER_MAX_TOKENS"), @default_max_tokens)
    lora_rank = parse_int(System.get_env("TINKER_LORA_RANK"), 8)

    IO.puts("[setup] base_model=#{base_model}")
    IO.puts("[setup] prompt=#{inspect(prompt_text)}")
    IO.puts("[setup] max_tokens=#{max_tokens} lora_rank=#{lora_rank}")

    config = Config.new()
    {:ok, service} = ServiceClient.start_link(config: config)

    {:ok, training} =
      ServiceClient.create_lora_training_client(service, base_model, rank: lora_rank)

    IO.puts("[save] saving weights and creating a SamplingClient (sync helper)...")

    case TrainingClient.save_weights_and_get_sampling_client_sync(training) do
      {:ok, sampler} ->
        do_sample(sampler, base_model, prompt_text, max_tokens)

      {:error, %Error{} = error} ->
        IO.puts(
          "[error] save_weights_and_get_sampling_client_sync failed: #{Error.format(error)} data=#{inspect(error.data)}"
        )

      {:error, other} ->
        IO.puts("[error] save_weights_and_get_sampling_client_sync failed: #{inspect(other)}")
    end
  end

  defp do_sample(sampler, base_model, prompt_text, max_tokens) do
    with {:ok, prompt} <- ModelInput.from_text(prompt_text, model_name: base_model),
         params <- %SamplingParams{max_tokens: max_tokens},
         {:ok, future} <- Tinkex.SamplingClient.sample(sampler, prompt, params),
         {:ok, resp} <- Task.await(future, :infinity) do
      Enum.each(resp.sequences, fn seq ->
        IO.puts("== SAMPLE ==")

        case Tokenizer.decode(seq.tokens, base_model) do
          {:ok, text} -> IO.puts(text)
          {:error, err} -> IO.puts("decode error: #{inspect(err)}")
        end
      end)
    else
      {:error, %Error{} = error} ->
        IO.puts("[error] sampling failed: #{Error.format(error)} data=#{inspect(error.data)}")

      {:error, other} ->
        IO.puts("[error] sampling failed: #{inspect(other)}")
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end
end

Tinkex.Examples.SaveWeightsAndSample.run()
