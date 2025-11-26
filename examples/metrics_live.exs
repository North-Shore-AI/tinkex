defmodule Tinkex.Examples.MetricsLive do
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
    prompt_text = System.get_env("TINKER_PROMPT", "Quick metrics check from Tinkex")

    max_tokens = env_integer("TINKER_MAX_TOKENS", 32)
    temperature = env_float("TINKER_TEMPERATURE", 0.7)
    num_samples = env_integer("TINKER_NUM_SAMPLES", 1)
    await_timeout = env_integer("TINKER_SAMPLE_TIMEOUT", 30_000)

    :ok = Tinkex.Metrics.reset()

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

    result =
      task
      |> Task.await(await_timeout)
      |> format_result(base_model)

    IO.puts(result)

    :ok = Tinkex.Metrics.flush()
    snapshot = Tinkex.Metrics.snapshot()

    render_snapshot(snapshot)
  end

  defp format_result({:ok, response}, model) do
    text =
      case List.first(response.sequences) do
        nil ->
          "[no sequences returned]"

        seq ->
          case Tinkex.Tokenizer.decode(seq.tokens, model) do
            {:ok, decoded} -> decoded
            {:error, reason} -> "[decode failed: #{inspect(reason)}]"
          end
      end

    "Sampled text: #{text}"
  end

  defp format_result({:error, %Error{} = error}, _model), do: Error.format(error)
  defp format_result({:error, other}, _model), do: inspect(other)

  defp render_snapshot(snapshot) do
    IO.puts("\n=== Metrics Snapshot ===")

    IO.puts("Counters:")

    snapshot.counters
    |> Enum.sort()
    |> Enum.each(fn {name, value} ->
      IO.puts("  #{name}: #{value}")
    end)

    IO.puts("\nLatency (ms):")

    case Map.get(snapshot.histograms, :tinkex_request_duration_ms) do
      nil ->
        IO.puts("  no data yet")

      hist ->
        IO.puts("  count: #{hist.count}")
        IO.puts("  mean: #{format_float(hist.mean)}")
        IO.puts("  p50:  #{format_float(hist.p50)}")
        IO.puts("  p95:  #{format_float(hist.p95)}")
        IO.puts("  p99:  #{format_float(hist.p99)}")
    end
  end

  defp format_float(nil), do: "n/a"
  defp format_float(value), do: :erlang.float_to_binary(value, decimals: 2)

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
end

Tinkex.Examples.MetricsLive.run()
