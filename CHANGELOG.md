# Changelog

All notable changes to this project will be documented in this file.

## [0.1.6] - 2025-11-25

### Added

- **Metrics aggregation** via `Tinkex.Metrics`: counters for total/success/failure HTTP requests, latency histograms with p50/p95/p99, `snapshot/0`, `reset/0`, and `flush/0`.
- **Automatic telemetry wiring**: the metrics server starts under `Tinkex.Application` and subscribes to `[:tinkex, :http, :request, :stop]` by default.
- **Live metrics example**: `examples/metrics_live.exs` runs a sampling call against the live API and prints the metrics snapshot; added to `examples/run_all.sh` and documented in `examples/README.md`.

### Changed

- **Docs**: README now highlights metrics and shows a quick snapshot snippet; installation version bumped to `~> 0.1.6`.

## [0.1.5] - 2025-11-25

### Added

- **Structured Regularizer Composition**: New `TrainingClient.forward_backward_custom/4` API for computing custom loss functions with composable regularizers in Elixir/Nx.
- **RegularizerSpec type** (`lib/tinkex/types/regularizer_spec.ex`): Typed configuration struct for regularizers with validation, supporting:
  - `fn` - Regularizer function of arity 2 returning `{loss_tensor, metrics_map}`
  - `weight` - Non-negative float multiplier for loss contribution
  - `name` - String identifier for telemetry and metrics
  - `async` - Boolean flag for Task-returning regularizers
- **RegularizerOutput type** (`lib/tinkex/types/regularizer_output.ex`): Metrics struct for individual regularizer results including value, weight, contribution, and optional gradient norms.
- **CustomLossOutput type** (`lib/tinkex/types/custom_loss_output.ex`): Structured output from composed loss computation with base loss metrics, per-regularizer outputs, and totals. Implements `Jason.Encoder` for serialization.
- **Regularizer behaviour** (`lib/tinkex/regularizer/regularizer.ex`): Formal interface with `@callback compute/3` and optional `@callback name/0` for module-based regularizers.
- **GradientTracker** (`lib/tinkex/regularizer/gradient_tracker.ex`): Nx-based gradient norm computation using `Nx.Defn.grad` for monitoring training dynamics:
  - `compute_grad_norm/2` - L2 norm for arbitrary loss functions
  - `grad_norm_for_regularizer/3` - Per-regularizer gradient norms
  - `total_grad_norm/4` - Combined gradient norm for full loss composition
- **Executor** (`lib/tinkex/regularizer/executor.ex`): Parallel/sequential regularizer execution using `Task.async_stream/3`:
  - Configurable parallelism with `max_concurrency` option
  - Timeout handling with task cleanup
  - Support for async (Task-returning) regularizers
  - Telemetry emission for start/stop/exception events
- **Pipeline** (`lib/tinkex/regularizer/pipeline.ex`): Orchestration module coordinating base loss and regularizer execution:
  - Input validation and duplicate name detection
  - Parallel execution by default
  - Optional gradient norm tracking
  - Comprehensive telemetry events
- **Regularizer Telemetry** (`lib/tinkex/regularizer/telemetry.ex`): Convenience helpers for attaching telemetry handlers to regularizer events:
  - `[:tinkex, :custom_loss, :start | :stop | :exception]`
  - `[:tinkex, :regularizer, :compute, :start | :stop | :exception]`

### Changed

- **TrainingClient**: Added `forward_backward_custom/4` public function and corresponding `handle_call` clause for custom loss computation with regularizers.

## [0.1.4] - 2025-11-25

- Added EXLA dependency (`{:exla, "~> 0.7"}`) and configured Nx to use `EXLA.Backend` by default, enabling GPU/CPU-accelerated tensor operations for custom loss computation in Elixir.
- Introduced `TrainingClient.forward/4` for forward-only inference without backward pass, returning logprobs that can be converted to Nx tensors via `TensorData.to_nx/1`.
- Added `Training.forward_future/2` API endpoint for server-side future-based forward pass requests.
- Created `forward_inference.exs` example demonstrating the forward-only API, Nx tensor conversion, and EXLA-accelerated operations.
- Foundation for structured regularizer pipelines where custom loss functions and gradients are computed in Elixir/Nx rather than on the server.

## [0.1.3] - 2025-11-25

- Made `SessionManager.stop_session/2` a synchronous GenServer call so heartbeat removal finishes before the client returns and refined heartbeat error handling to drop sessions silently on client-visible errors (e.g., 404) just like the Python SDK.
- Added REST endpoints for fetching samplers, weights metadata, and training runs along with the new `GetSamplerResponse` and `WeightsInfoResponse` structs, `ImageChunk.expected_tokens`, `LoadWeightsRequest.load_optimizer_state`, and the `:cispo`/`:dro` `LossFnType` variants; expanded tests, serialization rounds, and `.gitignore` coverage to match the higher API parity.
- Introduced the `weightsinspection.exs` example showing how to query checkpoint metadata, LoRA ranks, and sampler state via REST plus published detailed architectural documentation and a Structured Regularizers design doc that outlines custom loss/telemetry workflows requiring Nx/EXLA gradient computation support.

## [0.1.2] - 2025-11-22

- Fixed future polling to handle direct `ForwardBackwardOutput` payloads (no `status`/`type` wrapper) by normalizing them into completed responses, unblocking `TrainingClient.forward_backward/3` result parsing.

## [0.1.1] - 2025-11-21

- Added `Tinkex.RestClient` for synchronous session and checkpoint management (list/get/delete and archive URL retrieval) with typed response structs.
- Added `Tinkex.CheckpointDownload` to fetch and extract checkpoint archives with overwrite and progress callback options.
- Added async client factories (`ServiceClient.create_sampling_client_async/2`, `SamplingClient.create_async/2`, `TrainingClient.create_sampling_client_async/3`) to parallelize client creation.
- Expanded docs and examples to cover sessions, checkpoint management, downloads, and async workflows; included the changelog in HexDocs extras for publishing.
- Fixed REST URL construction so query parameters (e.g., checkpoint archive URLs) are sent correctly, resolving 404s when fetching checkpoint downloads.
- Avoided over-encoding `tinker://` paths in checkpoint archive/delete endpoints so sampler checkpoints resolve correctly.

## [0.1.0]

- Initial release.
