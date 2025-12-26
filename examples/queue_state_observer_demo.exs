# Queue State Observer Demo
#
# This example demonstrates the automatic queue state observer feature in Tinkex.
# When the API returns queue state information (rate limits, capacity issues),
# the SamplingClient and TrainingClient automatically log human-readable warnings.
#
# Run with:
#   mix run examples/queue_state_observer_demo.exs
#
# Environment variables:
#   TINKER_API_KEY        - Required API key
#   TINKER_BASE_URL       - API base URL (default: production)
#   TINKER_BASE_MODEL     - Model to use (default: meta-llama/Llama-3.1-8B)
#   OBSERVER_MODE         - "builtin" (default), "custom", or "telemetry"
#
# The queue state observer automatically logs messages like:
#   [warning] Sampling is paused for session-123. Reason: concurrent LoRA rate limit hit
#   [warning] Training is paused for model-xyz. Reason: out of capacity

defmodule Tinkex.Examples.QueueStateObserverDemo do
  @moduledoc """
  Demonstrates the Queue State Observer feature (Gap #4 implementation).

  Both SamplingClient and TrainingClient implement the QueueStateObserver behaviour
  and automatically log human-readable warnings when queue state changes indicate
  rate limiting or capacity issues.

  ## Features Demonstrated

  1. **Built-in Observer** (default) - Automatic logging with 60-second debouncing
  2. **Custom Observer** - User-provided observer module for custom handling
  3. **Telemetry Events** - Queue state telemetry under `[:tinkex, :queue, :state_change]`

  ## Queue States

  - `:active` - Normal operation (no logging)
  - `:paused_rate_limit` - Rate limit hit ("concurrent LoRA/models rate limit hit")
  - `:paused_capacity` - Capacity limit hit ("out of capacity")
  - `:unknown` - Unknown state ("unknown")
  """

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout :infinity

  alias Tinkex.Error

  # Custom observer implementation for demonstration
  defmodule CustomObserver do
    @moduledoc false
    @behaviour Tinkex.QueueStateObserver

    @impl true
    def on_queue_state_change(queue_state, metadata \\ %{}) do
      context = Map.get(metadata, :model_id) || Map.get(metadata, :sampling_session_id) || "?"

      case queue_state do
        :active ->
          IO.puts("[CustomObserver] Queue is active for #{context}")

        :paused_rate_limit ->
          IO.puts(
            IO.ANSI.yellow() <>
              "[CustomObserver] RATE LIMITED for #{context}!" <>
              IO.ANSI.reset()
          )

        :paused_capacity ->
          IO.puts(
            IO.ANSI.red() <>
              "[CustomObserver] OUT OF CAPACITY for #{context}!" <>
              IO.ANSI.reset()
          )

        other ->
          IO.puts("[CustomObserver] Unknown state #{inspect(other)} for #{context}")
      end

      :ok
    end
  end

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)
    observer_mode = System.get_env("OBSERVER_MODE", "builtin")

    IO.puts("""
    ====================================================
    Queue State Observer Demo
    ====================================================
    Base URL: #{base_url}
    Base model: #{base_model}
    Observer mode: #{observer_mode}

    This demo shows how queue state observers work.
    When rate limits or capacity issues occur, you'll see
    automatic log warnings from the built-in observer.

    """)

    # Optionally attach telemetry handler
    if observer_mode == "telemetry" do
      attach_telemetry_handler()
    end

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- create_service(config),
         :ok <- demonstrate_sampling_observer(service, base_model, observer_mode),
         :ok <- demonstrate_training_observer(service, base_model, observer_mode) do
      IO.puts("\n[success] Demo completed successfully!")
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "\n[error] #{Error.format(error)}")

      {:error, other} ->
        IO.puts(:stderr, "\n[error] #{inspect(other)}")
    end
  end

  defp create_service(config) do
    IO.puts("[step] Creating ServiceClient...")
    Tinkex.ServiceClient.start_link(config: config)
  end

  defp demonstrate_sampling_observer(service, base_model, observer_mode) do
    IO.puts("""

    ----------------------------------------------------
    Part 1: SamplingClient Queue State Observer
    ----------------------------------------------------
    The SamplingClient automatically logs warnings when
    queue state changes. Watch for messages like:

      [warning] Sampling is paused for session-xyz.
                Reason: concurrent LoRA rate limit hit

    """)

    # Create sampling client
    IO.puts("[step] Creating SamplingClient...")

    case Tinkex.ServiceClient.create_sampling_client(service, base_model: base_model) do
      {:ok, sampler} ->
        IO.puts("[step] SamplingClient created successfully")

        # Build a simple prompt
        {:ok, prompt} =
          Tinkex.Types.ModelInput.from_text("Hello, world!", model_name: base_model)

        params = %Tinkex.Types.SamplingParams{max_tokens: 16, temperature: 0.7}

        # Determine observer option based on mode
        sample_opts =
          case observer_mode do
            "custom" ->
              IO.puts("[info] Using custom observer module")
              [queue_state_observer: CustomObserver]

            "telemetry" ->
              IO.puts("[info] Observer disabled; using telemetry events only")
              [queue_state_observer: nil]

            _ ->
              IO.puts("[info] Using built-in observer (automatic logging)")
              # Default - SamplingClient uses itself as observer
              []
          end

        IO.puts("[step] Submitting sample request...")
        IO.puts("[note] If rate limited, you'll see queue state warnings here\n")

        {:ok, task} =
          Tinkex.SamplingClient.sample(sampler, prompt, params, sample_opts ++ [num_samples: 1])

        case Task.await(task, @await_timeout) do
          {:ok, response} ->
            IO.puts("[success] Got #{length(response.sequences)} sample(s)")
            :ok

          {:error, error} ->
            IO.puts("[warning] Sampling failed (this is expected if rate limited)")
            IO.puts("[warning] Error: #{format_error(error)}")
            :ok
        end

      {:error, error} ->
        IO.puts("[error] Failed to create SamplingClient: #{format_error(error)}")
        {:error, error}
    end
  end

  defp demonstrate_training_observer(service, base_model, observer_mode) do
    IO.puts("""

    ----------------------------------------------------
    Part 2: TrainingClient Queue State Observer
    ----------------------------------------------------
    The TrainingClient uses "concurrent models rate limit hit"
    instead of "concurrent LoRA rate limit hit" for rate limits.

      [warning] Training is paused for model-abc.
                Reason: concurrent models rate limit hit

    """)

    IO.puts("[step] Creating TrainingClient with LoRA (rank=8)...")
    IO.puts("[note] This may take 30-120s on first run (model loading)...\n")

    case Tinkex.ServiceClient.create_lora_training_client(service, base_model,
           lora_config: %Tinkex.Types.LoraConfig{rank: 8}
         ) do
      {:ok, training} ->
        IO.puts("[step] TrainingClient created successfully")

        # Build training data
        {:ok, model_input} =
          Tinkex.Types.ModelInput.from_text("Training sample text",
            model_name: base_model,
            training_client: training
          )

        tokens = get_tokens(model_input)

        datum =
          Tinkex.Types.Datum.new(%{
            model_input: model_input,
            loss_fn_inputs: %{
              "target_tokens" => Tinkex.Types.TensorData.from_nx(Nx.tensor(tokens))
            }
          })

        # Determine observer option based on mode
        fb_opts =
          case observer_mode do
            "custom" ->
              IO.puts("[info] Using custom observer module")
              [queue_state_observer: CustomObserver]

            "telemetry" ->
              IO.puts("[info] Observer disabled; using telemetry events only")
              [queue_state_observer: nil]

            _ ->
              IO.puts("[info] Using built-in observer (automatic logging)")
              []
          end

        IO.puts("[step] Submitting forward_backward request...")
        IO.puts("[note] If rate limited, you'll see queue state warnings here\n")

        {:ok, task} =
          Tinkex.TrainingClient.forward_backward(training, [datum], :cross_entropy, fb_opts)

        case Task.await(task, @await_timeout) do
          {:ok, output} ->
            loss = Map.get(output.metrics, "loss", "N/A")
            IO.puts("[success] Forward-backward completed, loss: #{loss}")
            :ok

          {:error, error} ->
            IO.puts("[warning] Training failed (this is expected if rate limited)")
            IO.puts("[warning] Error: #{format_error(error)}")
            :ok
        end

      {:error, error} ->
        IO.puts("[error] Failed to create TrainingClient: #{format_error(error)}")
        {:error, error}
    end
  end

  defp attach_telemetry_handler do
    IO.puts("[info] Attaching telemetry handler for [:tinkex, :queue, :state_change]")

    :telemetry.attach(
      "queue-state-demo-handler",
      [:tinkex, :queue, :state_change],
      fn _event, _measurements, metadata, _config ->
        queue_state = metadata[:queue_state]
        request_id = metadata[:request_id] || "?"

        IO.puts(
          IO.ANSI.cyan() <>
            "[telemetry] Queue state: #{inspect(queue_state)} (request: #{request_id})" <>
            IO.ANSI.reset()
        )
      end,
      nil
    )

    IO.puts("")
  end

  defp get_tokens(%{chunks: [%{tokens: tokens} | _]}), do: tokens
  defp get_tokens(%{chunks: _}), do: []
  defp get_tokens(_), do: []

  defp fetch_env!(var) do
    System.get_env(var) ||
      raise "Missing required environment variable: #{var}"
  end

  defp format_error(%Error{} = error), do: Error.format(error)
  defp format_error(other), do: inspect(other)
end

# Run the demo
Tinkex.Examples.QueueStateObserverDemo.run()
