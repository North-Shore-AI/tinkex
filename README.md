<div align="center">
  <img src="assets/tinkex.svg" width="400" alt="Tinkex Logo" />
</div>

# Tinkex

**Elixir SDK for the Tinker ML Training and Inference API**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Tinkex is an Elixir port of the [Tinker Python SDK](https://github.com/thinking-machines-lab/tinker), providing a functional, concurrent interface to the Tinker distributed machine learning platform. It enables fine-tuning large language models using LoRA (Low-Rank Adaptation) and performing high-performance text generation.

## Features

- **TrainingClient**: Fine-tune models with forward/backward passes and gradient-based optimization
- **SamplingClient**: Generate text completions with customizable sampling parameters
- **ServiceClient**: Manage models, sessions, and service operations
- **Async/Concurrent**: Built on Elixir's actor model for efficient concurrent operations
- **Type Safety**: Leverages Elixir typespecs and pattern matching
- **HTTP/2**: Modern HTTP client with connection pooling and streaming support
- **Retry Logic**: Configurable retry strategies with exponential backoff
- **Telemetry**: Comprehensive observability through Elixir's telemetry ecosystem

## Installation

Add `tinkex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tinkex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Configure your API key
config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod"

# Create a training client for LoRA fine-tuning
{:ok, service_client} = Tinkex.ServiceClient.new()
{:ok, training_client} = Tinkex.ServiceClient.create_lora_training_client(
  service_client,
  base_model: "Qwen/Qwen2.5-7B"
)

# Prepare training data
datum = %Tinkex.Types.Datum{
  model_input: Tinkex.Types.ModelInput.from_ints(token_ids),
  loss_fn_inputs: %{
    target_tokens: target_token_ids
  }
}

# Run forward-backward pass
{:ok, task} = Tinkex.TrainingClient.forward_backward(
  training_client,
  [datum],
  :cross_entropy
)
{:ok, result} = Task.await(task)

# Optimize model parameters
{:ok, optim_task} = Tinkex.TrainingClient.optim_step(
  training_client,
  %Tinkex.Types.AdamParams{learning_rate: 1.0e-4}
)

# Save weights and create sampling client
{:ok, sampling_client} = Tinkex.TrainingClient.save_weights_and_get_sampling_client(
  training_client
)

# Generate text
prompt = Tinkex.Types.ModelInput.from_ints(prompt_tokens)
params = %Tinkex.Types.SamplingParams{
  max_tokens: 100,
  temperature: 0.7
}

{:ok, sample_task} = Tinkex.SamplingClient.sample(
  sampling_client,
  prompt: prompt,
  sampling_params: params,
  num_samples: 1
)
{:ok, response} = Task.await(sample_task)
```

## Sampling Workflow

Create a `ServiceClient`, derive a `SamplingClient`, and issue sampling requests via Tasks so you can `Task.await/2` or orchestrate concurrency with `Task.await_many/2` or `Task.async_stream/3`.

```elixir
config = Tinkex.Config.new(api_key: "tenant-key")

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service, base_model: "Qwen/Qwen2.5-7B")

prompt = Tinkex.Types.ModelInput.from_ints([1, 2, 3])
params = %Tinkex.Types.SamplingParams{max_tokens: 64, temperature: 0.7}

{:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt, params, num_samples: 2)
{:ok, response} = Task.await(task, 5_000)
```

- Sampling requests are lock-free reads from ETS; you can fan out 20–50 tasks safely.
- Rate limits are enforced per `{base_url, api_key}` bucket using a shared `Tinkex.RateLimiter`; a `429` sets a backoff window that later sampling calls will wait through before hitting the server again.
- Sampling uses `max_retries: 0` at the HTTP layer: server/user errors (e.g., 5xx, 400) surface immediately so callers can decide how to retry.
- Multi-tenant safety: different API keys or base URLs use separate rate limiters and stay isolated even when one tenant is backing off.

## Telemetry Quickstart

Tinkex emits telemetry for every HTTP request plus queue state changes during future polling. Attach a console logger while debugging a run:

```elixir
handler = Tinkex.Telemetry.attach_logger(level: :info)

# ... perform training and sampling operations ...

:ok = Tinkex.Telemetry.detach(handler)
```

You can also attach your own handler to ship metrics to StatsD/OTLP:

```elixir
:telemetry.attach(
  "tinkex-metrics",
  [[:tinkex, :http, :request, :stop]],
  fn _event, measurements, metadata, _ ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    IO.puts("HTTP #{metadata.path} took #{duration_ms}ms (retries=#{metadata.retry_count})")
  end,
  nil
)
```

## HTTP Connection Pools

Tinkex uses Finch for HTTP/2 with dedicated pools per operation type (training, sampling, telemetry, etc.). The application supervisor boots these pools automatically when `config :tinkex, :enable_http_pools, true` (the default in `config/config.exs`). For most apps you should keep this enabled so requests reuse the tuned pools. If you need to run in a lightweight environment (e.g., unit tests or host applications that manage their own pools), you can temporarily disable them with:

```elixir
# config/test.exs
import Config
config :tinkex, :enable_http_pools, false
```

When you disable the pools, Finch falls back to its default pool configuration. Re-enable them in dev/prod configs to match the retry and pool-routing behavior expected by the SDK.

## Architecture

Tinkex follows Elixir conventions and leverages OTP for fault tolerance:

- **GenServer-based Clients**: Each client type is backed by a GenServer for state management
- **Task-based Futures**: Asynchronous operations return Elixir Tasks
- **Supervisor Trees**: Automatic process supervision and restart strategies
- **Connection Pooling**: Finch-based HTTP/2 connection pools
- **Telemetry Events**: Standard `:telemetry` integration for metrics and tracing

## Project Status

🚧 **Work in Progress** - This is an active port of the Python Tinker SDK to Elixir.

Current focus areas:
- Core client implementations (TrainingClient, SamplingClient, ServiceClient)
- Type definitions and validation
- HTTP client integration with Finch
- Async operation handling with Tasks and GenServers
- Comprehensive test suite

## Development

```bash
# Clone the repository
git clone https://github.com/North-Shore-AI/tinkex.git
cd tinkex

# Install dependencies
mix deps.get

# Run tests
mix test

# Generate documentation
mix docs
```

## Documentation

- [API Reference](https://hexdocs.pm/tinkex) (Coming soon)
- [Porting Guide](docs/20251118/port_research/) - Technical deep dive on the Python to Elixir port
- [Python SDK Documentation](https://tinker-docs.thinkingmachines.ai/)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

## Related Projects

- [Tinker Python SDK](https://github.com/thinking-machines-lab/tinker) - Original Python implementation
- [Thinking Machines AI](https://thinkingmachines.ai/) - The Tinker ML platform

---

Built with ❤️ by the North Shore AI community
