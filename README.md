<div align="center">
  <img src="assets/tinkex.svg" width="400" alt="Tinkex Logo" />
</div>

# Tinkex

**Elixir SDK for the Tinker ML Training and Inference API**

[![CI](https://github.com/North-Shore-AI/tinkex/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/North-Shore-AI/tinkex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/tinkex.svg)](https://hex.pm/packages/tinkex)
[![Docs](https://img.shields.io/badge/docs-hexdocs.pm-blue.svg)](https://hexdocs.pm/tinkex)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Tinkex is an Elixir port of the [Tinker Python SDK](https://github.com/thinking-machines-lab/tinker), providing a functional, concurrent interface to the [Tinker](https://tinker-docs.thinkingmachines.ai/) distributed machine learning platform by [Thinking Machines Lab](https://thinkingmachines.ai/). It enables fine-tuning large language models using LoRA (Low-Rank Adaptation) and performing high-performance text generation.

## 0.2.0 Highlights

- Opt-in recovery automation layer (Policy + Monitor + Executor) to restart corrupted training runs from checkpoints with telemetry hooks and bounded concurrency (defaults off).
- Checkpoint timestamps now normalize to `DateTime` when ISO-8601 values are returned (strings are preserved on parse failure).
- Added NxPenalties-backed regularizer adapters (L1/L2/ElasticNet/Entropy/KL/Consistency/Orthogonality/GradientPenalty) with offline and live structured regularizer examples exercising the full set.
- Structured regularizer examples include reference/pair data wiring patterns for KL/Consistency and a gradient-penalty demo.
- Dependency note: uses `{:nx_penalties, "~> 0.1.2"}` for tensor primitives.

## Features

- **TrainingClient**: Fine-tune models with forward/backward passes and gradient-based optimization
- **Custom Loss Training**: `TrainingClient.forward_backward_custom/4` computes gradients from per-datum logprobs, sends them to the backend, and returns `ForwardBackwardOutput` (regularizer terms can be folded into your loss_fn)
- **Forward-Only Inference**: `TrainingClient.forward/4` returns logprobs without backward pass for evaluation or for custom loss functions you run locally
- **EXLA Backend**: Nx tensors use EXLA for GPU/CPU-accelerated operations out of the box
- **SamplingClient**: Generate text completions with customizable sampling parameters
- **ServiceClient**: Manage models, sessions, and service operations
- **RestClient**: List sessions, enumerate user checkpoints, fetch archive URLs, and delete checkpoints
- **CheckpointDownload**: Memory-efficient streaming downloads with O(1) memory usage and optional progress reporting
- **Async/Concurrent**: Built on Elixir's actor model for efficient concurrent operations
- **Type Safety**: Leverages Elixir typespecs and pattern matching
- **HTTP/2**: Modern HTTP client with connection pooling and streaming support
- **Retry Logic**: Configurable retry strategies with exponential backoff
- **Telemetry**: Comprehensive observability through Elixir's telemetry ecosystem
- **Metrics Aggregation**: Built-in `Tinkex.Metrics` for counters, gauges, and latency percentiles with snapshot/export helpers
- **Session lifecycle resilience**: `SessionManager.stop_session/2` waits for heartbeat cleanup, heartbeats use the canonical `/api/v1/session_heartbeat` path, and sustained heartbeat failures now surface as warnings (after ~2 minutes by default) instead of silently dropping sessions.
- **Queue observability**: Sampling and training clients expose queue observers that feed `Future.poll/2`, emitting debounced warnings with human-readable rate limit or capacity reasons.
- **REST metadata & inspection APIs**: New endpoints surface samplers, weights metadata, and training runs while the SDK exposes `GetSamplerResponse`, `WeightsInfoResponse`, `ImageChunk.expected_tokens`, `LoadWeightsRequest.optimizer`, and the `:cispo`/`:dro` `LossFnType` tags for richer load/save tooling.
- **Checkpoint persistence**: `TrainingClient.save_state/3`, `TrainingClient.load_state/3`, `TrainingClient.load_state_with_optimizer/3`, and `ServiceClient.create_training_client_from_state/3` enable saving checkpoints and resuming training with optimizer state.
- **Recovery automation (opt-in)**: `Tinkex.Recovery.Policy` + `Monitor` + `Executor` restart corrupted runs from checkpoints with callbacks, telemetry, and bounded concurrency; defaults off.
- **Multipart uploads**: The `:files` option builds multipart/form-data bodies automatically (path and tuple normalization, bracketed form fields, boundary generation, and tuple metadata) while preserving JSON requests when no files are present; includes a runnable multipart example and path-based helpers.
- **Proxy-aware HTTP**: Finch pools pick up proxies from `Tinkex.Config` (or `TINKEX_PROXY`/`TINKEX_PROXY_HEADERS`) while masking credentials in logs and inspect output.
- **ModelInput builders**: `empty/0`, `append/2`, `append_int/2` for incremental prompt construction; `append_int` extends the last text chunk or creates a new one after images.

## Disclaimer

Tinkex is an independent, community-maintained Elixir SDK for the Tinker API. It is not affiliated with, endorsed by, or supported by Thinking Machines Lab or the official Tinker team. Please refer to the [official Tinker documentation](https://tinker-docs.thinkingmachines.ai/) for canonical behavior, SLAs, and support.

## Guides

- Getting started & configuration: `docs/guides/getting_started.md`, `docs/guides/environment_configuration.md`
- Custom loss training (per-datum logprobs, backend gradients): `docs/guides/custom_loss_training.md` and `mix run examples/custom_loss_training.exs`
- Training persistence: `docs/guides/training_persistence.md` (live example: `examples/training_persistence_live.exs`)
- Recovery automation (opt-in restarts): `docs/guides/recovery.md`
- Save-and-sample convenience: `mix run examples/save_weights_and_sample.exs` demonstrates `TrainingClient.save_weights_and_get_sampling_client_sync/2` (requires `TINKER_API_KEY`)
- Multipart uploads: `docs/guides/file_uploads.md` (live helper: `mix run examples/file_upload_multipart.exs`; uploads `examples/uploads/sample_upload.bin` by default, override via `TINKER_UPLOAD_FILE`)

## Installation

Add `tinkex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tinkex, "~> 0.2.0"}
  ]
end
```

## Quick Start

For a full walkthrough (installation, configuration, CLI), see `docs/guides/getting_started.md`. For environment flags and precedence, see `docs/guides/environment_configuration.md`. For advanced tuning knobs (HTTP pools, retries, telemetry), see `docs/guides/advanced_configuration.md`.

```elixir
# Configure your API key
config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod"

# Optional: Cloudflare Access service tokens (ADR-002)
# export CLOUDFLARE_ACCESS_CLIENT_ID=...
# export CLOUDFLARE_ACCESS_CLIENT_SECRET=...
# Tinkex will forward them on every request.

# Create a training client for LoRA fine-tuning
{:ok, service_client} = Tinkex.ServiceClient.new()
{:ok, training_client} = Tinkex.ServiceClient.create_lora_training_client(
  service_client,
  "meta-llama/Llama-3.1-8B"
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

# Custom loss training (per-datum logprobs list)
loss_fn = fn _data, [logprobs] ->
  loss = Nx.negate(Nx.mean(logprobs))
  {loss, %{"custom_perplexity" => Nx.to_number(Nx.exp(loss))}}
end

{:ok, custom_task} =
  Tinkex.TrainingClient.forward_backward_custom(
    training_client,
    [datum],
    loss_fn
  )
{:ok, _custom_output} = Task.await(custom_task)

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

## Recovery (opt-in)

Automatic restart is **off by default**. The recovery layer is composed of a
policy (configuration only), a monitor (polls `Rest.get_training_run/2`), and an
executor (bounded concurrency restart worker). You must start and wire these
processes explicitly:

```elixir
policy =
  Tinkex.Recovery.Policy.new(
    enabled: true,
    poll_interval_ms: 15_000,
    checkpoint_strategy: :latest,
    restore_optimizer: true,
    on_recovery: fn _old_pid, new_pid, cp ->
      Logger.info("Recovered #{cp.tinker_path} -> #{inspect(new_pid)}")
      :ok
    end,
    on_failure: fn run_id, reason ->
      Logger.warning("Recovery failed for #{run_id}: #{inspect(reason)}")
      :ok
    end
  )

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)

{:ok, executor} =
  Tinkex.Recovery.Executor.start_link(
    max_concurrent: 2
  )

{:ok, monitor} =
  Tinkex.Recovery.Monitor.start_link(
    executor: executor,
    policy: policy
  )

:ok = Tinkex.Recovery.Monitor.monitor_run(monitor, "run-123", service)
```

What to know:
- Strategies: `:latest` (uses `TrainingRun.last_checkpoint`) and `{:specific, path}` are supported today; `:best` is reserved for future work.
- Optimizer restore defaults to `true`; set `restore_optimizer: false` for weights-only restarts.
- Telemetry: `[:tinkex, :recovery, :detected | :started | :checkpoint_selected | :client_created | :completed | :failed | :exhausted]` emits run/attempt metadata. Attach handlers to trace the loop.
- Concurrency guard: `Executor.start_link/1` accepts `max_concurrent` (default: 1) to prevent runaway restart storms.
- Config: `Tinkex.Config.new(recovery: %{...})` stores a policy alongside other client settings for reuse in supervisors.
- Examples: offline `mix run examples/recovery_simulated.exs` and live `mix run examples/recovery_live_injected.exs` (injects a single `corrupted: true` poll; requires `TINKER_API_KEY`).

## Multipart file uploads

Use the `:files` option on Tinkex.API.post/3 to build multipart/form-data bodies automatically. File paths are read into memory, filenames are inferred from the path (or tuple), and nested maps/lists are flattened with bracket notation.

```elixir
config = Tinkex.Config.new(api_key: System.fetch_env!("TINKER_API_KEY"))

files = %{
  "upload" => "/tmp/data.bin",
  "extra" => {"notes.txt", "hello", "text/plain"}
}

body = %{note: "multipart demo"}

path = "/"

case Tinkex.API.post(path, body, config: config, files: files) do
  {:ok, response} -> IO.inspect(response, label: "upload response")
  {:error, error} -> IO.puts("Upload failed: #{inspect(error)}")
end
```

For a runnable walkthrough, see `docs/guides/file_uploads.md` and `examples/file_upload_multipart.exs` (the example uploads the bundled `examples/uploads/sample_upload.bin` by default; override via `TINKER_UPLOAD_FILE`).

### Sampling retries & backpressure

Sampling clients now accept a `retry_config` to tune high-level retries and limit concurrent attempts:

```elixir
retry_config =
  Tinkex.RetryConfig.new(
    base_delay_ms: 750,
    max_delay_ms: 15_000,
    jitter_pct: 0.25,
    max_connections: 25,
    progress_timeout_ms: 120_000
  )

{:ok, sampling_client} =
  Tinkex.ServiceClient.create_sampling_client(service_client,
    base_model: "meta-llama/Llama-3.1-8B",
    retry_config: retry_config
  )

# Disable retries for a client
{:ok, sampling_client} =
  Tinkex.ServiceClient.create_sampling_client(service_client,
    base_model: "meta-llama/Llama-3.1-8B",
    retry_config: [enable_retry_logic: false]
  )
```

Defaults mirror the Python SDK (0.5s base, 10s cap, 25% jitter, 120m progress timeout, unbounded retries until the timeout, 100 max connections). Retries run at the SamplingClient layer; HTTP sampling still defaults to 0 low-level retries.

### Environment configuration

`Tinkex.Config.new/1` now defaults from `Tinkex.Env` (precedence: opts > `config :tinkex` > env vars > built-ins). Supported env vars:

- `TINKER_API_KEY` (required) and `TINKER_BASE_URL` (defaults to `https://tinker.thinkingmachines.dev/services/tinker-prod`).
- `TINKER_TAGS`, `TINKER_FEATURE_GATES` (comma-separated lists), `TINKER_TELEMETRY` (on by default), and `TINKER_LOG` (`debug`/`info`/`warn`/`error`).
- `TINKEX_DUMP_HEADERS` (debug logging; secrets redacted) and Cloudflare Access tokens `CLOUDFLARE_ACCESS_CLIENT_ID` / `CLOUDFLARE_ACCESS_CLIENT_SECRET` per ADR-002 (added to every request when set).
- `TINKEX_PROXY` (proxy URL like `http://proxy.company.com:8080` or `http://user:pass@proxy.company.com:8080`) and `TINKEX_PROXY_HEADERS` (JSON array of headers).

App config defaults are also honored:

```elixir
config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  base_url: System.get_env("TINKER_BASE_URL"),
  cf_access_client_id: System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID"),
  cf_access_client_secret: System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET"),
  telemetry_enabled?: true,
  log_level: :info,
  proxy: {:http, "proxy.company.com", 8080, []},
  proxy_headers: [{"proxy-authorization", "Basic " <> Base.encode64("user:pass")}]
```

See `docs/guides/environment_configuration.md` for the full matrix and precedence rules (including detailed proxy configuration).

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

Highlighted live flows:
- `mix run examples/multimodal_resume_and_cleanup.exs` (multimodal with `expected_tokens`, optimizer resume helper, default checkpoint cache)
- `mix run examples/checkpoint_multi_delete_live.exs` (create two checkpoints then delete both with a single CLI call)
- `mix run examples/llama3_tokenizer_override_live.exs` (Llama-3 tokenizer override via live encode/decode)
- Recovery walkthroughs: `mix run examples/recovery_simulated.exs` (offline) and `mix run examples/recovery_live_injected.exs` (live API with injected corruption flag)

### Live example

To verify connectivity against a real Tinker deployment, export `TINKER_API_KEY` (and optionally `TINKER_BASE_URL`, `TINKER_BASE_MODEL`, `TINKER_PROMPT`) and run:

```bash
mix run examples/live_capabilities_and_logprobs.exs
# Or run all curated examples (includes the live demo last):
examples/run_all.sh
```

The demo performs a capabilities + health probe and computes prompt logprobs via a live sampling client.

## Sessions & checkpoints (REST)

Use the `RestClient` for synchronous session and checkpoint management, and `CheckpointDownload` to pull artifacts locally:

> Note: the heartbeat endpoint is `/api/v1/session_heartbeat` (aligned with the Python SDK). Heartbeats keep retrying on failure and emit a warning if consecutive failures exceed the warning window (default: 120s). For a live check, run `mix run examples/heartbeat_probe.exs` (requires `TINKER_API_KEY`).

```elixir
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, rest} = Tinkex.ServiceClient.create_rest_client(service)

{:ok, sessions} = Tinkex.RestClient.list_sessions(rest, limit: 10)
IO.inspect(sessions.sessions, label: "sessions")

{:ok, checkpoints} = Tinkex.RestClient.list_user_checkpoints(rest, limit: 20)
IO.inspect(Enum.map(checkpoints.checkpoints, & &1.tinker_path), label: "checkpoints")

# Download with streaming (O(1) memory usage)
{:ok, download} =
  Tinkex.CheckpointDownload.download(rest, "tinker://run-123/weights/0001",
    output_dir: "./models",
    force: true,
    progress: fn downloaded, total ->
      percent = if total > 0, do: Float.round(downloaded / total * 100, 1), else: 0
      IO.write("\rProgress: #{percent}%")
    end
  )

IO.puts("\nExtracted to #{download.destination}")
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
- Prefer asynchronous client creation for fan-out workflows: `Tinkex.ServiceClient.create_sampling_client_async/2`, `Tinkex.ServiceClient.create_lora_training_client_async/3`, `Tinkex.ServiceClient.create_training_client_from_state_async/3`, `Tinkex.SamplingClient.create_async/2`, and `Tinkex.TrainingClient.create_sampling_client_async/3` return Tasks you can await or `Task.await_many/2`.

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

## Custom Loss Training

`TrainingClient.forward_backward_custom/4` now mirrors the Python SDK: it runs a forward pass, hands **per-datum logprobs** to your loss function, computes gradients in Nx, sends them back to the backend as synthetic weights, and returns a `ForwardBackwardOutput` ready for `optim_step/2`.

### Basic Usage

```elixir
# loss_fn receives the original data and a list of logprob tensors (one per datum)
loss_fn = fn _data, [logprobs] ->
  base = Nx.negate(Nx.mean(logprobs))
  l1 = Nx.multiply(0.01, Nx.sum(Nx.abs(logprobs)))
  total = base + l1

  metrics = %{
    "base_nll" => Nx.to_number(base),
    "l1" => Nx.to_number(l1),
    "custom_perplexity" => Nx.to_number(Nx.exp(base))
  }

  {total, metrics}
end

{:ok, task} = Tinkex.TrainingClient.forward_backward_custom(training_client, data, loss_fn)
{:ok, %Tinkex.Types.ForwardBackwardOutput{} = output} = Task.await(task)

IO.inspect(output.metrics, label: "metrics (merged with server loss)")

# Apply gradients
{:ok, adam} = Tinkex.Types.AdamParams.new(learning_rate: 1.0e-4)
{:ok, optim_task} = Tinkex.TrainingClient.optim_step(training_client, adam)
{:ok, _resp} = Task.await(optim_task)
```

Regularizer-style terms can be folded directly into your loss function (as shown with `l1`). For a full script that hits the live API, see `examples/custom_loss_training.exs`.

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
- Environment & advanced config: `docs/guides/environment_configuration.md`, `docs/guides/advanced_configuration.md`
- API overview & parity checklist: `docs/guides/api_reference.md`
- Futures/retries: `docs/guides/futures_and_async.md`, `docs/guides/retry_and_error_handling.md`
- Recovery automation (opt-in restarts): `docs/guides/recovery.md`
- Tokenization and end-to-end training: `docs/guides/tokenization.md`, `docs/guides/training_loop.md`
- Custom loss/regularizers: `docs/guides/regularizers.md`, `docs/guides/forward_inference.md`
- Checkpoints & persistence: `docs/guides/checkpoint_management.md`, `docs/guides/training_persistence.md`
- Model info/unload: `docs/guides/model_info_unload.md`
- CLI reference: `docs/guides/cli_guide.md`
- Observability: `docs/guides/telemetry.md`, `docs/guides/metrics.md`, `docs/guides/streaming.md`
- Troubleshooting playbook: `docs/guides/troubleshooting.md`
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
- `custom_loss_training.exs` – live custom loss training that sends gradients via `forward_backward_custom/4`
- `forward_inference.exs` – forward-only pass with Nx/EXLA tensor conversion for custom loss or evaluation
- `structured_regularizers.exs` – composable regularizer pipeline demo with mock data (runs offline)
- `structured_regularizers_live.exs` – custom loss with inline regularizer terms via live Tinker API
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
- `model_info_and_unload.exs` – fetch model metadata (including tokenizer id) and unload the model session (unload currently returns 404 on prod; see docs/guides/model_info_unload.md)

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
