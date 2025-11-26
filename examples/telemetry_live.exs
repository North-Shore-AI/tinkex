defmodule Tinkex.Examples.TelemetryLive do
  @moduledoc false

  alias Tinkex.Types.{ModelInput, SamplingParams}

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
    prompt_text = System.get_env("TINKER_PROMPT", "Write a single sentence about telemetry.")

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    IO.puts("Starting service client against #{base_url} ...")
    {:ok, service} = Tinkex.ServiceClient.start_link(config: config)

    reporter =
      case Tinkex.ServiceClient.telemetry_reporter(service) do
        {:ok, pid} -> pid
        {:error, :disabled} -> raise "TINKER_TELEMETRY=0; enable telemetry to run this example"
      end

    logger_id = Tinkex.Telemetry.attach_logger(level: :info)

    :ok =
      Tinkex.Telemetry.Reporter.log(reporter, "example.start", %{
        "base_model" => base_model,
        "prompt" => prompt_text
      })

    IO.puts("Creating sampling client for #{base_model} ...")
    {:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service, base_model: base_model)

    {:ok, prompt} = ModelInput.from_text(prompt_text, model_name: base_model)
    params = %SamplingParams{max_tokens: 32, temperature: 0.7}

    IO.puts("Sending sample request ...")
    {:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt, params, num_samples: 1)
    {:ok, response} = Task.await(task, 15_000)

    IO.inspect(response.sequences, label: "Sampled sequences")

    :ok =
      Tinkex.Telemetry.Reporter.log(reporter, "example.complete", %{
        "model" => base_model,
        "tokens" => length(prompt.tokens)
      })

    :ok = Tinkex.Telemetry.Reporter.flush(reporter, sync?: true)

    IO.puts("Flushed telemetry; detach logger and exit.")
    :ok = Tinkex.Telemetry.detach(logger_id)
  end
end

Tinkex.Examples.TelemetryLive.run()
