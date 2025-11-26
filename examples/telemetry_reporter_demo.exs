defmodule Tinkex.Examples.TelemetryReporterDemo do
  @moduledoc """
  Comprehensive demonstration of the Tinkex.Telemetry.Reporter module.

  This example showcases all the features of the telemetry reporter:

    * Session lifecycle events (SESSION_START, SESSION_END)
    * Generic event logging with custom data and severity levels
    * Exception logging (fatal and non-fatal)
    * Automatic HTTP telemetry capture
    * Retry with exponential backoff
    * Wait-until-drained semantics
    * Graceful shutdown with stop/1

  Run with:

      TINKER_API_KEY=your-key mix run examples/telemetry_reporter_demo.exs

  Environment variables:
    - TINKER_API_KEY (required)
    - TINKER_BASE_URL (optional, defaults to production)
    - TINKER_BASE_MODEL (optional, defaults to Llama-3.1-8B)
    - TINKER_PROMPT (optional)
  """

  alias Tinkex.Telemetry.Reporter
  alias Tinkex.Types.{ModelInput, SamplingParams}

  require Logger

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
    prompt_text = System.get_env("TINKER_PROMPT", "Explain telemetry in one sentence.")

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    IO.puts("""
    ==========================================
    Tinkex Telemetry Reporter Demo
    ==========================================
    Base URL: #{base_url}
    Model: #{base_model}
    """)

    # Start the reporter manually (usually ServiceClient does this)
    session_id = "demo-session-#{System.unique_integer([:positive])}"

    IO.puts("\n1. Starting reporter for session: #{session_id}")

    {:ok, reporter} =
      Reporter.start_link(
        session_id: session_id,
        config: config,
        # Demonstrate configurable options
        flush_interval_ms: 5_000,
        flush_threshold: 50,
        http_timeout_ms: 5_000,
        max_retries: 3,
        retry_base_delay_ms: 500,
        enabled: true
      )

    IO.puts("   Reporter started: #{inspect(reporter)}")

    # Log a generic event with custom data
    IO.puts("\n2. Logging generic events...")

    :ok =
      if Reporter.log(reporter, "demo.started", %{
           "base_model" => base_model,
           "prompt_length" => String.length(prompt_text),
           "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
         }) do
        :ok
      else
        :failed
      end

    IO.puts("   Logged: demo.started")

    # Log with different severity levels
    Reporter.log(reporter, "demo.info", %{"message" => "This is an info event"}, :info)
    Reporter.log(reporter, "demo.warning", %{"message" => "This is a warning event"}, :warning)
    Reporter.log(reporter, "demo.debug", %{"message" => "This is a debug event"}, :debug)
    IO.puts("   Logged events with different severity levels")

    # Demonstrate exception logging (non-fatal)
    IO.puts("\n3. Logging a non-fatal exception...")

    try do
      raise "Simulated non-fatal error for demonstration"
    rescue
      exception ->
        Reporter.log_exception(reporter, exception, :warning)
        IO.puts("   Logged non-fatal exception: #{Exception.message(exception)}")
    end

    # Perform actual sampling to generate HTTP telemetry
    IO.puts("\n4. Performing live sampling (generates HTTP telemetry)...")

    {:ok, service} = Tinkex.ServiceClient.start_link(config: config)

    try do
      {:ok, sampler} =
        Tinkex.ServiceClient.create_sampling_client(service, base_model: base_model)

      {:ok, prompt} = ModelInput.from_text(prompt_text, model_name: base_model)
      params = %SamplingParams{max_tokens: 32, temperature: 0.7}

      {:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt, params, num_samples: 1)
      {:ok, response} = Task.await(task, 30_000)

      IO.puts("   Sampling complete!")

      case List.first(response.sequences) do
        nil ->
          IO.puts("   (no sequences returned)")

        seq ->
          case Tinkex.Tokenizer.decode(seq.tokens, base_model) do
            {:ok, decoded} -> IO.puts("   Generated: #{String.slice(decoded, 0, 80)}...")
            {:error, _} -> IO.puts("   (decode failed)")
          end
      end

      Reporter.log(reporter, "demo.sampling_complete", %{
        "tokens_generated" => length(List.first(response.sequences, %{tokens: []}).tokens)
      })
    rescue
      exception ->
        IO.puts("   Sampling failed: #{Exception.message(exception)}")
        Reporter.log_exception(reporter, exception, :error)
    end

    # Demonstrate wait_until_drained
    IO.puts("\n5. Demonstrating wait_until_drained...")

    Reporter.log(reporter, "demo.before_drain", %{})
    :ok = Reporter.flush(reporter, sync?: true, wait_drained?: true)
    drained = Reporter.wait_until_drained(reporter, 5_000)
    IO.puts("   Queue drained: #{drained}")

    # Log more events to show the periodic flush
    IO.puts("\n6. Logging additional events...")

    for i <- 1..5 do
      Reporter.log(reporter, "demo.batch_event", %{"index" => i})
    end

    IO.puts("   Logged 5 batch events")

    # Demonstrate graceful shutdown with stop/1
    IO.puts("\n7. Stopping reporter gracefully...")

    Reporter.log(reporter, "demo.completing", %{"status" => "success"})
    :ok = Reporter.stop(reporter, 10_000)

    IO.puts("   Reporter stopped gracefully (SESSION_END event sent)")

    IO.puts("""

    ==========================================
    Demo Complete!
    ==========================================
    The following telemetry events were sent:
    - SESSION_START (automatic)
    - demo.started
    - demo.info, demo.warning, demo.debug (severity variants)
    - UNHANDLED_EXCEPTION (non-fatal)
    - HTTP request telemetry (from sampling)
    - demo.sampling_complete
    - demo.before_drain
    - demo.batch_event (x5)
    - demo.completing
    - SESSION_END (automatic on stop)

    Check your Tinker dashboard to verify telemetry was received.
    """)
  end
end

Tinkex.Examples.TelemetryReporterDemo.run()
