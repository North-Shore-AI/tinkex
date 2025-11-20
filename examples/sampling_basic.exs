defmodule Tinkex.Examples.SamplingBasic do
  @moduledoc false

  alias Tinkex.Error

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key =
      System.get_env("TINKER_API_KEY") ||
        raise "Set TINKER_API_KEY to run this example"

    base_url =
      System.get_env(
        "TINKER_BASE_URL",
        "https://tinker.thinkingmachines.dev/services/tinker-prod"
      )

    base_model = System.get_env("TINKER_BASE_MODEL", "meta-llama/Llama-3.1-8B")
    prompt_text = System.get_env("TINKER_PROMPT", "Hello from Tinkex!")

    max_tokens = env_integer("TINKER_MAX_TOKENS", 64)
    temperature = env_float("TINKER_TEMPERATURE", 0.7)
    num_samples = env_integer("TINKER_NUM_SAMPLES", 1)
    await_timeout = env_integer("TINKER_SAMPLE_TIMEOUT", 30_000)

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)
    {:ok, service} = Tinkex.ServiceClient.start_link(config: config)
    {:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service, base_model: base_model)

    {:ok, prompt} = Tinkex.Types.ModelInput.from_text(prompt_text, model_name: base_model)
    params = %Tinkex.Types.SamplingParams{max_tokens: max_tokens, temperature: temperature}

    IO.puts("Sampling #{num_samples} sequence(s) from #{base_model} ...")

    {:ok, task} =
      Tinkex.SamplingClient.sample(sampler, prompt, params,
        num_samples: num_samples,
        prompt_logprobs: false
      )

    case Task.await(task, await_timeout) do
      {:ok, response} ->
        IO.puts("Received #{length(response.sequences)} sequence(s):")

        Enum.with_index(response.sequences, 1)
        |> Enum.each(fn {seq, idx} ->
          text = decode(seq.tokens, base_model)
          IO.puts("Sample #{idx}: #{text}")
        end)

      {:error, error} ->
        IO.puts(:stderr, "Sampling failed: #{format_error(error)}")
    end
  end

  defp decode(tokens, model_name) do
    case Tinkex.Tokenizer.decode(tokens, model_name) do
      {:ok, text} -> text
      {:error, reason} -> "[decode failed: #{inspect(reason)}]"
    end
  end

  defp env_integer(var, default) do
    case System.get_env(var) do
      nil ->
        default

      value ->
        try do
          String.to_integer(value)
        rescue
          _ -> default
        end
    end
  end

  defp env_float(var, default) do
    case System.get_env(var) do
      nil ->
        default

      value ->
        try do
          String.to_float(value)
        rescue
          _ -> default
        end
    end
  end

  defp format_error(%Error{} = error), do: Error.format(error)
  defp format_error(other), do: inspect(other)
end

Tinkex.Examples.SamplingBasic.run()
