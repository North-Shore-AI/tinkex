defmodule Tinkex.Examples.KimiK2SamplingLive do
  @moduledoc false

  alias Tinkex.{Config, Error, ServiceClient, Tokenizer}
  alias Tinkex.Types.{ModelInput, SamplingParams}

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_base_model "moonshotai/Kimi-K2-Thinking"

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key =
      System.get_env("TINKER_API_KEY") ||
        raise "Set TINKER_API_KEY to run this example"

    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_base_model)
    prompt_text = System.get_env("TINKER_PROMPT", "Say hi")

    max_tokens = env_integer("TINKER_MAX_TOKENS", 32)
    temperature = env_float("TINKER_TEMPERATURE", 0.7)
    num_samples = env_integer("TINKER_NUM_SAMPLES", 1)
    await_timeout = env_integer("TINKER_SAMPLE_TIMEOUT", 60_000)

    config = Config.new(api_key: api_key, base_url: base_url)
    {:ok, service} = ServiceClient.start_link(config: config)

    if base_model == @default_base_model and not advertised_model?(service, base_model) do
      IO.puts(
        "Kimi K2 model (#{base_model}) is not advertised by this server; skipping. Set TINKER_BASE_MODEL to override."
      )

      return(:ok)
    end

    IO.puts("== Kimi K2 tokenization (tiktoken_ex)")
    IO.puts("Model: #{base_model}")

    case Tokenizer.encode(prompt_text, base_model) do
      {:ok, ids} ->
        IO.puts("Prompt: #{inspect(prompt_text)}")
        IO.puts("Token IDs (first 32): #{inspect(Enum.take(ids, 32))} (#{length(ids)} total)")

        case Tokenizer.decode(ids, base_model) do
          {:ok, decoded} ->
            IO.puts("Round-trip decode: #{inspect(decoded)}")

          {:error, reason} ->
            IO.puts(:stderr, "Decode failed: #{format_error(reason)}")
        end

      {:error, reason} ->
        IO.puts(:stderr, "Tokenizer failed: #{format_error(reason)}")
        return(:ok)
    end

    IO.puts("\n== Live sampling")

    {:ok, sampler} = ServiceClient.create_sampling_client(service, base_model: base_model)
    {:ok, prompt} = ModelInput.from_text(prompt_text, model_name: base_model)
    params = %SamplingParams{max_tokens: max_tokens, temperature: temperature}

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
          text =
            case Tokenizer.decode(seq.tokens, base_model) do
              {:ok, text} -> text
              {:error, reason} -> "[decode failed: #{format_error(reason)}]"
            end

          IO.puts("Sample #{idx}: #{text}")
        end)

      {:error, reason} ->
        IO.puts(:stderr, "Sampling failed: #{format_error(reason)}")
    end
  end

  defp advertised_model?(service, model_name) do
    case ServiceClient.get_server_capabilities(service) do
      {:ok, caps} ->
        names =
          caps
          |> Map.get(:supported_models, [])
          |> Enum.map(&((&1 && &1.model_name) || &1))
          |> Enum.filter(&is_binary/1)

        model_name in names

      {:error, reason} ->
        IO.puts(
          :stderr,
          "Warning: failed to fetch capabilities (#{format_error(reason)}); attempting anyway."
        )

        true
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

  defp return(value), do: value
end

Tinkex.Examples.KimiK2SamplingLive.run()
