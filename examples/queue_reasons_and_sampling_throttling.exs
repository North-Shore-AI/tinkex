defmodule Tinkex.Examples.QueueReasonsAndSamplingThrottling do
  @moduledoc false

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout 60_000

  alias Tinkex.{ByteEstimator, SamplingDispatch}
  alias Tinkex.Types.ModelInput

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)
    prompt_text = System.get_env("TINKER_PROMPT", "Hello from throttling + queue reasons!")

    IO.puts("""
    ----------------------------------------
    Base URL: #{base_url}
    Base model: #{base_model}
    Prompt: #{prompt_text}
    ----------------------------------------
    """)

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, sampling} <-
           Tinkex.ServiceClient.create_sampling_client(service, base_model: base_model) do
      telemetry_ref = attach_queue_telemetry()
      entry = sampling_entry!(sampling)

      log_manual_reason(entry)
      demo_dispatch_throttling(entry)
      run_live_sample(entry, prompt_text, base_model)

      :telemetry.detach(telemetry_ref)
      IO.puts("[done] queue reasons + throttling demo complete")
    end
  end

  defp run_live_sample(entry, prompt_text, base_model) do
    {:ok, model_input} =
      ModelInput.from_text(prompt_text, model_name: base_model, training_client: nil)

    estimated_bytes = ByteEstimator.estimate_model_input_bytes(model_input)
    IO.puts("[info] estimated prompt bytes: #{estimated_bytes}")

    params = %Tinkex.Types.SamplingParams{max_tokens: 32, temperature: 0.7}

    IO.puts("[step] running live sample...")
    {:ok, task} = Tinkex.SamplingClient.sample(entry.client, model_input, params)

    case Task.await(task, @await_timeout) do
      {:ok, response} ->
        IO.puts("[ok] sample returned #{length(response.sequences)} sequence(s)")

      {:error, error} ->
        IO.puts(:stderr, "[warn] sample failed: #{inspect(error)}")
    end
  end

  defp sampling_entry!(client) do
    [{_, entry}] = :ets.lookup(:tinkex_sampling_clients, {:config, client})
    Map.put(entry, :client, client)
  end

  defp log_manual_reason(entry) do
    IO.puts("[info] demonstrating server-preferred reason via QueueStateLogger")

    Tinkex.QueueStateLogger.log_state_change(
      :paused_capacity,
      :sampling,
      entry.sampling_session_id,
      "server says: running short on capacity (demo)"
    )
  end

  defp demo_dispatch_throttling(entry) do
    IO.puts("[info] simulating backoff to exercise throttled dispatch + byte penalty")

    # Force a recent backoff window so throttled semaphores + 20x byte penalty apply.
    SamplingDispatch.set_backoff(entry.dispatch, 1_000)

    heavy_bytes = 6_000_000
    parent = self()

    task_fun = fn label ->
      SamplingDispatch.with_rate_limit(entry.dispatch, heavy_bytes, fn ->
        send(parent, {:acquired, label, System.monotonic_time(:millisecond)})
        Process.sleep(200)
      end)
    end

    t1 = Task.async(fn -> task_fun.("one") end)
    t2 = Task.async(fn -> task_fun.("two") end)

    await_times(t1, t2)
  end

  defp await_times(t1, t2) do
    times = collect_times(%{})
    Task.await(t1, @await_timeout)
    Task.await(t2, @await_timeout)

    sorted =
      times
      |> Enum.sort_by(fn {_label, ts} -> ts end)
      |> Enum.map(fn {label, ts} -> "#{label} at #{ts}" end)

    IO.puts("[info] dispatch acquisition order (penalized bytes): #{Enum.join(sorted, ", ")}")
  end

  defp collect_times(acc) do
    receive do
      {:acquired, label, ts} ->
        collect_times(Map.put(acc, label, ts))
    after
      50 ->
        acc
    end
  end

  defp attach_queue_telemetry do
    handler_id = "queue-reasons-demo-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:tinkex, :queue, :state_change],
      fn _event, _measurements, metadata, _config ->
        IO.puts(
          "[queue] state=#{metadata.queue_state}, reason=#{metadata[:queue_state_reason] || "n/a"}, request_id=#{metadata.request_id}"
        )
      end,
      nil
    )

    handler_id
  end

  defp fetch_env!(key) do
    System.get_env(key) || halt("Missing required env #{key}")
  end

  defp halt(message) do
    IO.puts(:stderr, "[error] #{message}")
    System.halt(1)
  end
end

Tinkex.Examples.QueueReasonsAndSamplingThrottling.run()
