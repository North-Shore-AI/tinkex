<div align="center">
  <img src="assets/tinkex.svg" width="400" alt="Tinkex Logo" />
</div>

# Tinkex

**Elixir SDK for the Tinker ML Training and Inference API**

[![CI](https://github.com/North-Shore-AI/tinkex/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/North-Shore-AI/tinkex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tinkex.svg)](https://hex.pm/packages/tinkex)
[![Docs](https://img.shields.io/badge/docs-hexdocs.pm-blue.svg)](https://hexdocs.pm/tinkex)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Tinkex is an Elixir port of the [Tinker Python SDK](https://github.com/thinking-machines-lab/tinker), providing a functional, concurrent interface to the Tinker distributed machine learning platform. It enables fine-tuning large language models using LoRA (Low-Rank Adaptation) and performing high-performance text generation.

## 0.1.7 Highlights

- **Telemetry reporter to Tinker**: New `Tinkex.Telemetry.Reporter` batches client-side events (session start/end, HTTP telemetry, custom events, exceptions) with backoff, wait-until-drained semantics, fatal-exception flushing, and a `TINKER_TELEMETRY` kill switch. `ServiceClient` now boots one automatically and exposes it via `telemetry_reporter/1`.
- **End-to-end telemetry examples**: Added `examples/telemetry_live.exs` and `examples/telemetry_reporter_demo.exs` covering reporter lifecycle, custom events, retries, drain/wait, and graceful shutdown; both are runnable via `examples/run_all.sh`.
- **Telemetry attribution across APIs**: Sampling and training clients now propagate `session_id`, `sampling_session_id`, and `model_seq_id` metadata into HTTP telemetry so backend events are tagged with the active session and request identifiers; HTTP telemetry requests respect configurable timeouts.

## Features

- **TrainingClient**: Fine-tune models with forward/backward passes and gradient-based optimization
- **Custom Loss Composition**: `TrainingClient.forward_backward_custom/4` with regularizer pipelines and gradient tracking
- **Forward-Only Inference**: `TrainingClient.forward/4` returns logprobs without backward pass for custom loss computation
- **EXLA Backend**: Nx tensors use EXLA for GPU/CPU-accelerated operations out of the box
- **SamplingClient**: Generate text completions with customizable sampling parameters
- **ServiceClient**: Manage models, sessions, and service operations
- **RestClient**: List sessions, enumerate user checkpoints, fetch archive URLs, and delete checkpoints
- **CheckpointDownload**: Download and extract checkpoints with optional progress reporting
- **Async/Concurrent**: Built on Elixir's actor model for efficient concurrent operations
- **Type Safety**: Leverages Elixir typespecs and pattern matching
- **HTTP/2**: Modern HTTP client with connection pooling and streaming support
- **Retry Logic**: Configurable retry strategies with exponential backoff
- **Telemetry**: Comprehensive observability through Elixir's telemetry ecosystem
- **Metrics Aggregation**: Built-in `Tinkex.Metrics` for counters, gauges, and latency percentiles with snapshot/export helpers
- **Session lifecycle resilience**: `SessionManager.stop_session/2` now waits for heartbeat cleanup so clients never race with session removal, and heartbeat errors that stem from user-visible failures simply drop the stale session instead of raising.
- **REST metadata & inspection APIs**: New endpoints surface samplers, weights metadata, and training runs while the SDK exposes `GetSamplerResponse`, `WeightsInfoResponse`, `ImageChunk.expected_tokens`, `LoadWeightsRequest.load_optimizer_state`, and the `:cispo`/`:dro` `LossFnType` tags for richer load/save tooling.

## Installation

Add `tinkex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tinkex, "~> 0.1.7"}
  ]
end
```

## Quick Start

For a full walkthrough (installation, configuration, CLI), see `docs/guides/getting_started.md`.

```elixir
# Configure your API key
config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod"

# Create a training client for LoRA fine-tuning
{:ok, service_client} = Tinkex.ServiceClient.new()
{:ok, training_client} = Tinkex.ServiceClient.create_lora_training_client(
  service_client,
  base_model: "meta-llama/Llama-3.1-8B"
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

### Metrics snapshot

`Tinkex.Metrics` subscribes to HTTP telemetry automatically. Flush and snapshot after a run to grab counters and latency percentiles without extra scripting:

```elixir
:ok = Tinkex.Metrics.flush()
snapshot = Tinkex.Metrics.snapshot()

IO.inspect(snapshot.counters, label: "counters")
IO.inspect(snapshot.histograms[:tinkex_request_duration_ms], label: "latency (ms)")
```

See `examples/metrics_live.exs` for an end-to-end live sampling + metrics printout.

## Examples

Self-contained workflows live in the `examples/` directory. Browse `examples/README.md` for per-script docs or export `TINKER_API_KEY` and run `examples/run_all.sh` to execute the curated collection sequentially.

## Sessions & checkpoints (REST)

Use the `RestClient` for synchronous session and checkpoint management, and `CheckpointDownload` to pull artifacts locally:

```elixir
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, rest} = Tinkex.ServiceClient.create_rest_client(service)

{:ok, sessions} = Tinkex.RestClient.list_sessions(rest, limit: 10)
IO.inspect(sessions.sessions, label: "sessions")

{:ok, checkpoints} = Tinkex.RestClient.list_user_checkpoints(rest, limit: 20)
IO.inspect(Enum.map(checkpoints.checkpoints, & &1.tinker_path), label: "checkpoints")

{:ok, download} =
  Tinkex.CheckpointDownload.download(rest, "tinker://run-123/weights/0001",
    output_dir: "./models",
    force: true
  )

IO.puts("Extracted to #{download.destination}")
```

## Sampling Workflow

Create a `ServiceClient`, derive a `SamplingClient`, and issue sampling requests via Tasks so you can `Task.await/2` or orchestrate concurrency with `Task.await_many/2` or `Task.async_stream/3`.

```elixir
config = Tinkex.Config.new(api_key: "tenant-key")

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service, base_model: "meta-llama/Llama-3.1-8B")

prompt = Tinkex.Types.ModelInput.from_ints([1, 2, 3])
params = %Tinkex.Types.SamplingParams{max_tokens: 64, temperature: 0.7}

{:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt, params, num_samples: 2)
{:ok, response} = Task.await(task, 5_000)
```

- Sampling requests are lock-free reads from ETS; you can fan out 20–50 tasks safely.
- Rate limits are enforced per `{base_url, api_key}` bucket using a shared `Tinkex.RateLimiter`; a `429` sets a backoff window that later sampling calls will wait through before hitting the server again.
- Sampling uses `max_retries: 0` at the HTTP layer: server/user errors (e.g., 5xx, 400) surface immediately so callers can decide how to retry.
- Multi-tenant safety: different API keys or base URLs use separate rate limiters and stay isolated even when one tenant is backing off.
- Prefer asynchronous client creation for fan-out workflows: `Tinkex.ServiceClient.create_sampling_client_async/2`, `Tinkex.SamplingClient.create_async/2`, and `Tinkex.TrainingClient.create_sampling_client_async/3` return Tasks you can await or `Task.await_many/2`.

## Telemetry Quickstart

Tinkex emits telemetry for every HTTP request plus queue state changes during future polling. Attach a console logger while debugging a run:

```elixir
handler = Tinkex.Telemetry.attach_logger(level: :info)

# ... perform training and sampling operations ...

:ok = Tinkex.Telemetry.detach(handler)
```

Backend telemetry is enabled by default. When you start a `ServiceClient`, it boots a telemetry reporter and exposes it so you can add custom events without wiring anything else:

```elixir
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

with {:ok, reporter} <- Tinkex.ServiceClient.telemetry_reporter(service) do
  Tinkex.Telemetry.Reporter.log(reporter, "app.start", %{"hostname" => System.get_env("HOSTNAME")})
end
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

To ship telemetry back to Tinker, start a reporter with your session id and config (ServiceClient boots one for you):

```elixir
{:ok, reporter} = Tinkex.Telemetry.Reporter.start_link(
  session_id: session_id,
  config: config,
  # Optional configuration:
  flush_interval_ms: 10_000,      # periodic flush (default: 10s)
  flush_threshold: 100,           # flush when queue reaches this size
  http_timeout_ms: 5_000,         # HTTP request timeout
  max_retries: 3,                 # retry failed sends with backoff
  retry_base_delay_ms: 1_000      # base delay for exponential backoff
)

# add your own events with severity
Tinkex.Telemetry.Reporter.log(reporter, "checkpoint_saved", %{path: "/tmp/out.pt"}, :info)
Tinkex.Telemetry.Reporter.log_exception(reporter, RuntimeError.exception("boom"), :error)

# fatal exceptions emit SESSION_END and flush synchronously
Tinkex.Telemetry.Reporter.log_fatal_exception(reporter, exception, :critical)

# wait until all events are flushed (useful for graceful shutdown)
true = Tinkex.Telemetry.Reporter.wait_until_drained(reporter, 30_000)

# stop gracefully (emits SESSION_END if not already sent)
:ok = Tinkex.Telemetry.Reporter.stop(reporter)
```

The reporter emits `SESSION_START`/`SESSION_END` automatically and forwards HTTP/queue telemetry that carries `session_id` metadata (added by default when using `ServiceClient`). Disable backend telemetry entirely with `TINKER_TELEMETRY=0`.

**Reporter Features:**
- Retry with exponential backoff on failed sends
- Wait-until-drained semantics for reliable shutdown
- Stacktrace capture in exception events
- Exception cause chain traversal for user error detection
- Configurable HTTP timeout and flush parameters

See `examples/telemetry_live.exs` for a basic run and `examples/telemetry_reporter_demo.exs` for a comprehensive demonstration of all reporter features.

Sampling and training clients automatically tag HTTP telemetry with `session_id`, `sampling_session_id`, and `model_seq_id`, and you can inject your own tags per request:

```elixir
{:ok, task} =
  Tinkex.SamplingClient.sample(
    sampler,
    prompt,
    params,
    num_samples: 1,
    telemetry_metadata: %{request_id: "demo-123"}
  )
```

## Structured Regularizers

Tinkex supports custom loss computation with composable regularizers using `TrainingClient.forward_backward_custom/4`. This API enables research workflows where loss functions are computed in Elixir/Nx with full gradient tracking.

### Basic Usage

```elixir
alias Tinkex.Types.RegularizerSpec

# Define your base loss function
base_loss_fn = fn _data, logprobs ->
  loss = Nx.negate(Nx.mean(logprobs))
  {loss, %{"nll" => Nx.to_number(loss)}}
end

# Define regularizers with weights
regularizers = [
  %RegularizerSpec{
    fn: fn _data, logprobs ->
      l1 = Nx.sum(Nx.abs(logprobs))
      {l1, %{"l1_sum" => Nx.to_number(l1)}}
    end,
    weight: 0.01,
    name: "l1_sparsity"
  },
  %RegularizerSpec{
    fn: fn _data, logprobs ->
      entropy = Nx.negate(Nx.sum(Nx.multiply(Nx.exp(logprobs), logprobs)))
      {entropy, %{}}
    end,
    weight: 0.001,
    name: "entropy"
  }
]

# Compute composed loss with gradient tracking
{:ok, task} = Tinkex.TrainingClient.forward_backward_custom(
  training_client,
  data,
  base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true,
  parallel: true
)

{:ok, output} = Task.await(task)

# Access structured metrics
IO.puts("Total loss: #{output.loss_total}")
IO.puts("Base loss: #{output.base_loss.value}")
IO.puts("Regularizer total: #{output.regularizer_total}")

# Per-regularizer metrics
for {name, reg} <- output.regularizers do
  IO.puts("#{name}: value=#{reg.value} contribution=#{reg.contribution} grad_norm=#{reg.grad_norm}")
end
```

### Loss Composition Formula

The total loss is computed as:

```
loss_total = base_loss + Σ(weight_i × regularizer_i_loss)
```

### Telemetry Events

The regularizer pipeline emits telemetry for monitoring:

- `[:tinkex, :custom_loss, :start]` - When computation begins
- `[:tinkex, :custom_loss, :stop]` - With duration, loss_total, regularizer_total
- `[:tinkex, :regularizer, :compute, :start]` - Per regularizer
- `[:tinkex, :regularizer, :compute, :stop]` - With value, contribution, grad_norm

```elixir
handler = Tinkex.Regularizer.Telemetry.attach_logger(level: :debug)
# ... run computations ...
Tinkex.Regularizer.Telemetry.detach(handler)
```

### Async Regularizers

For I/O-bound operations (external APIs, database queries), regularizers can return Tasks:

```elixir
%RegularizerSpec{
  fn: fn data, _logprobs ->
    Task.async(fn ->
      result = external_validation_api(data)
      {Nx.tensor(result.penalty), %{"validated" => true}}
    end)
  end,
  weight: 0.1,
  name: "external_validation",
  async: true
}
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

# Run linting/formatting/type checks + escript build
make qa

# Generate documentation (dev-only; requires :ex_doc)
mix docs
```

## Quality & Verification

Continuous verification commands (also referenced in `docs/20251119/port_research/07_porting_strategy.md`). Run `mix docs` in CI or locally to ensure guides/ExDoc compile; it relies on dev-only deps and is not needed in production deployments.

```bash
make qa
# or individually:
mix format --check-formatted
mix credo
mix test
mix dialyzer
MIX_ENV=prod mix escript.build
mix docs
```

## Documentation

- HexDocs site (API reference + guides): https://hexdocs.pm/tinkex (generate locally with `mix docs`, dev-only).
- Getting started + CLI walkthrough: `docs/guides/getting_started.md`
- API overview & parity checklist: `docs/guides/api_reference.md`
- Troubleshooting playbook: `docs/guides/troubleshooting.md`
- Tokenization and end-to-end training slices: `docs/guides/tokenization.md`, `docs/guides/training_loop.md`
- End-to-end examples (sessions, checkpoints, downloads, async factories): see `examples/*.exs`

## Python parity checks

When comparing Elixir and Python responses, hold the base model, prompt text, sampling parameters, and (if supported) seed constant. Expect similar logprobs/stop reasons rather than bit-identical text. See `docs/guides/api_reference.md` for a template that runs both SDKs side by side.

## CLI

See `docs/guides/getting_started.md` for the full CLI walkthrough and `docs/guides/troubleshooting.md` for failure modes/backoff tips. Quick reference:

```bash
MIX_ENV=prod mix escript.build   # produces ./tinkex

./tinkex checkpoint \
  --base-model meta-llama/Llama-3.1-8B \
  --rank 32 \
  --output ./checkpoint.json \
  --api-key "$TINKER_API_KEY"
```

The command starts a ServiceClient, creates a LoRA training client, saves weights for sampling, and writes a metadata JSON to `--output` (including `model_id`, `weights_path` and timestamp). The raw weights are stored by the service; the CLI only writes metadata locally. See `./tinkex checkpoint --help` for the full option list.

Generate text with a sampling client:

```bash
./tinkex run \
  --base-model meta-llama/Llama-3.1-8B \
  --prompt "Hello there" \
  --max-tokens 64 \
  --temperature 0.7 \
  --num-samples 2 \
  --api-key "$TINKER_API_KEY"
```

Pass `--prompt-file` to load a prompt from disk (plain text or a JSON array of token IDs), `--json` to print the full sample response payload, and `--output <path>` to write the generation output to a file instead of stdout.

Check build metadata:

```bash
./tinkex version           # prints version (+ git short SHA when available)
./tinkex version --json    # structured payload {"version": "...", "commit": "..."}
```

Packaging options:

- `MIX_ENV=prod mix escript.build` (default) emits `./tinkex`
- `mix escript.install ./tinkex` installs it into `~/.mix/escripts` for PATH usage
- `MIX_ENV=prod mix release && _build/prod/rel/tinkex/bin/tinkex version` for an OTP release binary (optional)

## Examples

Run any of the sample scripts with `mix run examples/<name>.exs` (requires `TINKER_API_KEY`):

- `training_loop.exs` – minimal forward/backward + optim + save flow
- `forward_inference.exs` – forward-only pass with Nx/EXLA tensor conversion for custom loss
- `structured_regularizers.exs` – composable regularizer pipeline demo with mock data (runs offline)
- `structured_regularizers_live.exs` – custom loss with regularizers via live Tinker API
- `sampling_basic.exs` – create a sampling client and decode completions
- `sessions_management.exs` – explore REST-based session listing and lookup
- `checkpoints_management.exs` – list user checkpoints and inspect metadata
- `checkpoint_download.exs` – download, stream, and extract checkpoint archives
- `weights_inspection.exs` – inspect checkpoints, samplers, and training runs
- `async_client_creation.exs` – parallel sampling client initialization via tasks
- `cli_run_text.exs` – call `tinkex run` programmatically with a text prompt
- `cli_run_prompt_file.exs` – use a prompt file and JSON output with `tinkex run`
- `telemetry_live.exs` – live telemetry with custom events and sampling
- `telemetry_reporter_demo.exs` – comprehensive reporter demo with retry, drain, and shutdown
- `retry_and_capture.exs` – retry helper demo with telemetry events and capture macros (uses live session creation when `TINKER_API_KEY` is set)

Use `examples/run_all.sh` (requires `TINKER_API_KEY`) to run the curated set in sequence.

## Retry & Telemetry Capture (new)

Use the built-in retry helper with telemetry events, and wrap risky blocks with the capture macros so exceptions get logged to the reporter before being re-raised:

```elixir
alias Tinkex.{Retry, RetryHandler}
alias Tinkex.Telemetry.Capture

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, reporter} = Tinkex.ServiceClient.telemetry_reporter(service)

result =
  Capture.capture_exceptions reporter: reporter do
    Retry.with_retry(
      fn -> maybe_fails() end,
      handler: RetryHandler.new(max_retries: 2, base_delay_ms: 200),
      telemetry_metadata: %{operation: "demo"}
    )
  end
```

This emits `[:tinkex, :retry, :attempt, ...]` telemetry for start/stop/retry/failed, and fatal exceptions will be flushed to telemetry. See `examples/retry_and_capture.exs` for a runnable script (requires `TINKER_API_KEY`; auto-creates a session and reporter).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Apache License 2.0 - See LICENSE for details.

## Related Projects

- [Tinker Python SDK](https://github.com/thinking-machines-lab/tinker) - Original Python implementation
- [Thinking Machines AI](https://thinkingmachines.ai/) - The Tinker ML platform

---

Built with ❤️ by the North Shore AI community
