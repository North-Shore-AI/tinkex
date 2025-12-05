# Tinkex Examples

This directory contains examples demonstrating the core functionality of the Tinkex SDK. Each example is a self-contained script that illustrates specific features and workflows, from basic sampling operations to advanced checkpoint management and training loops.

## Overview

The examples are organized by functionality and complexity, ranging from simple single-operation demonstrations to complete end-to-end workflows. Most examples require a valid Tinker API key and can be configured through environment variables to customize their behavior; offline-only scripts are noted below.

## Example Index

- `sampling_basic.exs` – basic sampling client creation and prompt decoding
- `training_loop.exs` – forward/backward pass, optim step, save weights, and optional sampling
- `custom_loss_training.exs` – live custom loss training that sends gradients to the backend via `forward_backward_custom/4`
- `forward_inference.exs` – forward-only pass returning logprobs for custom loss computation/evaluation with Nx/EXLA
- `structured_regularizers.exs` – composable regularizer pipeline demo with all NxPenalties-backed adapters (offline)
- `structured_regularizers_live.exs` – live custom loss run applying all adapters against the API
- `recovery_live_injected.exs` – live recovery demo that injects a single `corrupted: true` poll, restores from the latest checkpoint, and writes a new checkpoint from the recovered client (requires API key)
- `live_capabilities_and_logprobs.exs` – live health/capabilities check plus prompt logprobs (requires API key)
- `model_info_and_unload.exs` – fetch active model metadata (tokenizer id, arch) and unload the session (requires API key)
- `sessions_management.exs` – REST session listing and detail queries
- `checkpoints_management.exs` – user checkpoint listing with metadata inspection
- `checkpoint_download.exs` – streaming checkpoint download (O(1) memory) with progress callbacks and extraction
- `recovery_simulated.exs` – offline recovery demo that marks a run as corrupted, triggers `Monitor` + `Executor`, and advances to the next checkpoint (no API key required)
- `weights_inspection.exs` – sampler/weights metadata inspection for LoRA+training run validation
- `async_client_creation.exs` – parallel sampling client creation via Task-based flows
- `cli_run_text.exs` – programmatic `tinkex run` invocation with inline prompts
- `cli_run_prompt_file.exs` – CLI sampling with prompt files and JSON output capture
- `tinkex checkpoint list --limit 0 --format json --api-key "$TINKER_API_KEY"` – fetch all checkpoints via the CLI with progress to stderr and JSON totals/shown counts for automation
- `tinkex run list --limit 0 --format json --api-key "$TINKER_API_KEY"` – emit JSON run listings (owner/LoRA/status/checkpoints/user_metadata) with pagination progress for scripting
- `metrics_live.exs` – live sampling + metrics snapshot (counters and latency percentiles)
- `telemetry_live.exs` – live telemetry with custom events and sampling
- `telemetry_reporter_demo.exs` – comprehensive telemetry reporter demo with all features
- `retry_and_capture.exs` – retry helper + capture macros with telemetry events
- `heartbeat_probe.exs` – guarded live probe that asserts `/api/v1/session_heartbeat` returns 200 and `/api/v1/heartbeat` returns 404 (opt-in via env)
- `training_persistence_live.exs` – save a checkpoint, reload it with optimizer state, and spin up a fresh training client from the saved weights (requires only `TINKER_API_KEY`)
- `save_weights_and_sample.exs` – use the synchronous helper to save sampler weights and immediately create a SamplingClient, then run a sample with the freshly saved weights (requires `TINKER_API_KEY`)
- `file_upload_multipart.exs` – demonstrates multipart/form-data encoding capability (file transformation, form serialization, boundary generation); uses `examples/uploads/sample_upload.bin` by default (override via `TINKER_UPLOAD_FILE`). Note: runs without API key to demo encoding; set `TINKER_API_KEY` and `TINKER_UPLOAD_ENDPOINT` to test live uploads
- `multimodal_resume_and_cleanup.exs` – builds a multimodal payload with `expected_tokens`, tries to pick a vision-capable model from live capabilities (override via `TINKER_BASE_MODEL`), runs a live sampling request when a vision model is available (otherwise logs and skips), then restores a training client with optimizer state (uses `TINKER_CHECKPOINT_PATH` override or caches the first checkpoint at `tmp/checkpoints/default.path`; only `TINKER_API_KEY` is required) and prints the CLI multi-delete usage
- `checkpoint_multi_delete_live.exs` – creates two live checkpoints, caches their `tinker://` paths under `tmp/checkpoints/default.path`, and deletes both with a single CLI invocation (one confirmation via `--yes`; only `TINKER_API_KEY` is required)
- `llama3_tokenizer_override_live.exs` – runs a live sample on Llama-3 and demonstrates the tokenizer override (`thinkingmachineslabinc/meta-llama-3-tokenizer`) via encode/decode around the live output (only `TINKER_API_KEY` is required)
- Sampling retry tuning is supported in any sampling example via `retry_config` (e.g., pass
  `retry_config: [max_connections: 20, progress_timeout_ms: 120_000]` to
  `ServiceClient.create_sampling_client/2` inside `sampling_basic.exs` if you want to see the
  time-bounded retries and semaphore-based limiter in action).
- `examples/run_all.sh` – helper script that runs each example sequentially

## Prerequisites

Before running any example, ensure you have:

- Elixir 1.14 or later installed
- A valid Tinker API key
- Network access to the Tinker API endpoints
- The Tinkex application dependencies installed via `mix deps.get`

## Configuration

All examples use environment variables for configuration. The following variables are commonly used across multiple examples:

**Required Variables:**
- `TINKER_API_KEY` - Your Tinker API authentication key

**Optional Variables:**
- `TINKER_BASE_URL` - API endpoint URL (defaults to production endpoint)
- `TINKER_BASE_MODEL` - Model identifier for sampling and training operations
- `TINKER_PROMPT` - Custom prompt text for sampling examples
- `TINKER_MAX_TOKENS` - Maximum tokens to generate in sampling operations
- `TINKER_TEMPERATURE` - Temperature parameter for sampling (controls randomness)
- `TINKER_NUM_SAMPLES` - Number of sequences to generate
- `TINKER_CHECKPOINT_PATH` - Optional override for optimizer resume path in `multimodal_resume_and_cleanup.exs`; falls back to cached `tmp/checkpoints/default.path` or the first checkpoint discovered via API

## Running Examples

Each example can be executed directly using the Mix run command:

```bash
export TINKER_API_KEY="your-api-key-here"
mix run examples/example_name.exs
```

For examples requiring additional configuration, set the relevant environment variables before execution:

```bash
export TINKER_API_KEY="your-api-key-here"
export TINKER_BASE_MODEL="meta-llama/Llama-3.1-8B"
export TINKER_PROMPT="Your custom prompt here"
mix run examples/sampling_basic.exs
```

### Run every example in one go

To run the curated set of runnable scripts sequentially, use the helper script:

```bash
export TINKER_API_KEY="your-api-key-here"
examples/run_all.sh
```

The script simply iterates through the example list and executes `mix run examples/<name>.exs` for each entry, exiting on the first failure. Export any additional variables (e.g., `TINKER_BASE_MODEL`, `TINKER_PROMPT`, `TINKEX_DEBUG=1`) before invoking the script so they apply to every example.

### Heartbeat probe

To verify the live heartbeat path, run:

```bash
export TINKER_API_KEY="your-api-key-here"
# optional:
# export TINKER_BASE_URL="https://tinker.thinkingmachines.dev/services/tinker-prod"
mix run examples/heartbeat_probe.exs
```

The probe creates a session, expects `POST /api/v1/session_heartbeat` to return 200, and asserts `POST /api/v1/heartbeat` returns 404.

## Example Descriptions

### sampling_basic.exs

This example demonstrates the fundamental sampling workflow using the Tinkex SDK. It creates a service client, initializes a sampling client with a base model, and generates text completions from a given prompt.

**Key Features:**
- Service client initialization and configuration
- Sampling client creation from base models
- Prompt encoding and tokenization
- Asynchronous sampling with configurable parameters
- Response decoding and output formatting

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional, defaults to "Hello from Tinkex!")
- `TINKER_MAX_TOKENS` (optional, defaults to 64)
- `TINKER_TEMPERATURE` (optional, defaults to 0.7)
- `TINKER_NUM_SAMPLES` (optional, defaults to 1)
- `TINKER_SAMPLE_TIMEOUT` (optional, defaults to 30000ms)

### training_loop.exs

This example illustrates a complete training workflow including forward-backward passes, optimizer steps, weight persistence, and optional sampling from trained weights. It demonstrates the full lifecycle of fine-tuning a language model using LoRA (Low-Rank Adaptation).

**Key Features:**
- Training client initialization with LoRA configuration
- Model input preparation and tokenization
- Forward-backward pass execution for gradient computation
- Optimizer step application (Adam)
- Weight saving for inference
- Optional sampling from fine-tuned weights

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional, training prompt)
- `TINKER_SAMPLE_AFTER_TRAIN` (optional, "1" to enable post-training sampling)
- `TINKER_SAMPLE_PROMPT` (optional, prompt for post-training sampling)

### custom_loss_training.exs

Live custom loss training that mirrors the Python SDK’s `forward_backward_custom` behavior. The example runs a forward pass to obtain logprobs, computes a user-defined loss in Elixir/Nx (per-datum logprob tensors), sends gradients back to the server, and immediately runs `optim_step/2` to apply them.

**Key Features:**
- Per-datum logprobs passed to a custom Nx loss function
- Gradients are sent to the backend as weights (actual training occurs)
- Returns `ForwardBackwardOutput` so `optim_step/2` works without special handling
- LoRA training client creation against a live model

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)

### save_weights_and_sample.exs

Demonstrates the synchronous helper `TrainingClient.save_weights_and_get_sampling_client_sync/2`: saves sampler weights (or performs an ephemeral sampler save), instantiates a `SamplingClient`, and performs a sample using the freshly saved weights.

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional, defaults to "Hello from Tinkex!")
- `TINKER_MAX_TOKENS` (optional, defaults to 32)

### forward_inference.exs

This example demonstrates the forward-only API introduced in SDK version 0.1.4 for running inference without a backward pass. It shows how to obtain logprobs from a forward pass and convert them to Nx tensors using the EXLA backend for accelerated custom loss computation.

**Key Features:**
- Forward-only inference without backward pass overhead
- Logprobs extraction from forward output
- Conversion to Nx tensors via `TensorData.to_nx/1`
- EXLA-accelerated tensor operations demonstration
- Custom loss computation foundation for advanced training workflows

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional, prompt for forward pass)

**Use Cases:**
- Custom loss functions computed in Elixir/Nx with EXLA acceleration
- Inference-only workflows that need logprobs
- Building structured regularizer pipelines
- Gradient computation in Elixir rather than on the server

### live_capabilities_and_logprobs.exs

This live demo probes server capabilities, checks health, and computes prompt logprobs via the new `SamplingClient.compute_logprobs/3` helper. It uses real network calls and therefore requires a valid API key.

**Key Features:**
- Retrieves supported models from `/api/v1/get_server_capabilities` with full metadata
- Displays `SupportedModel` structs with `model_id`, `model_name`, and `arch` fields
- Uses the `model_names/1` convenience helper for backward-compatible name extraction
- Performs a `/api/v1/healthz` readiness check
- Spawns a ServiceClient + SamplingClient to compute prompt logprobs

**Server Capabilities Response:**

The `GetServerCapabilitiesResponse` now returns a list of `SupportedModel` structs instead of plain strings, preserving full model metadata:

```elixir
%GetServerCapabilitiesResponse{
  supported_models: [
    %SupportedModel{
      model_id: "llama-3-8b",
      model_name: "meta-llama/Meta-Llama-3-8B",
      arch: "llama"
    },
    %SupportedModel{
      model_id: "qwen2-72b",
      model_name: "Qwen/Qwen2-72B",
      arch: "qwen2"
    }
  ]
}

# Convenience helper for just the names:
GetServerCapabilitiesResponse.model_names(resp)
# => ["meta-llama/Meta-Llama-3-8B", "Qwen/Qwen2-72B"]
```

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional, defaults to "Hello from Tinkex!")

**Quickstart:**

```bash
export TINKER_API_KEY="your-api-key-here"
# Optional:
# export TINKER_BASE_URL="https://custom-endpoint"
# export TINKER_BASE_MODEL="meta-llama/Llama-3.1-8B"
# export TINKER_PROMPT="Hello world"
mix run examples/live_capabilities_and_logprobs.exs
# Or run the full suite (includes this demo last):
examples/run_all.sh
```

Expected output includes supported models with metadata (model_id, architecture), `status: ok` for health, and a list of prompt logprobs.

### model_info_and_unload.exs

Fetch active model metadata via the TrainingClient (`get_info`) and explicitly unload the model when finished. This is the quickest way to confirm the tokenizer id returned by the service and to release GPU memory for the session.

**Key Features:**
- Creates a training client for the configured base model
- Calls `/api/v1/get_info` to print `model_name`, `arch`, and `tokenizer_id`
- Calls `/api/v1/unload_model` to end the session

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional, defaults to production)
- `TINKER_BASE_MODEL` (optional, defaults to `meta-llama/Llama-3.1-8B`)

**Quickstart:**

```bash
export TINKER_API_KEY="your-api-key-here"
mix run examples/model_info_and_unload.exs
```

### structured_regularizers.exs

This example demonstrates the structured regularizer composition system introduced in SDK version 0.1.5. It shows how to define composable regularizers, execute them in parallel or sequentially, track gradient norms, and serialize outputs to JSON. This example uses mock data and runs without a Tinker server connection.

**Key Features:**
- RegularizerSpec configuration with weight and name
- Multiple regularizer types (L1 sparsity, entropy, L2 weight decay)
- Pipeline.compute for orchestrated loss composition
- Parallel vs sequential execution comparison
- Gradient norm tracking for training dynamics monitoring
- Async regularizers for I/O-bound operations
- Direct Executor and GradientTracker usage
- Telemetry integration with attach_logger
- JSON serialization of CustomLossOutput and RegularizerOutput
- Error handling for duplicate names and invalid inputs
- Module-based regularizers using Tinkex.Regularizer behaviour

**Configuration Variables:**
- None required (uses mock data)

**Use Cases:**
- Learning the regularizer API without server access
- Testing regularizer functions before live deployment
- Understanding the loss composition formula
- Exploring gradient tracking capabilities

### structured_regularizers_live.exs

This example demonstrates custom loss computation with composable regularizers using the live Tinker API. It connects to a real Tinker server, performs a forward pass to obtain logprobs, and computes the composed loss with gradient tracking.

**Key Features:**
- Live API connection with TrainingClient
- Tokenization of text prompts via ModelInput.from_text
- L1 sparsity and entropy regularizers
- TrainingClient.forward_backward_custom integration
- Real gradient norm computation from server logprobs
- JSON output with complete metrics

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)

**Use Cases:**
- Production custom loss computation
- Research workflows with real model logprobs
- Training dynamics monitoring with gradient norms
- Composable regularization in live training loops

### sessions_management.exs

This example demonstrates the session management capabilities introduced in SDK version 0.1.1. It shows how to create a REST client, list all active sessions, and retrieve detailed information about specific sessions including associated training runs and samplers.

**Key Features:**
- REST client creation and initialization
- Session listing with pagination support
- Session detail retrieval
- Training run and sampler enumeration

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)

### checkpoints_management.exs

This example showcases checkpoint management operations including listing user checkpoints, filtering by training run, and viewing detailed checkpoint metadata such as size, creation time, and accessibility status.

**Key Features:**
- User checkpoint listing with pagination
- Run-specific checkpoint filtering
- Checkpoint metadata inspection
- Size formatting and status reporting

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_RUN_ID` (optional, filters checkpoints by training run)

### weights_inspection.exs

This example demonstrates the weights and sampler inspection APIs for querying checkpoint metadata, validating LoRA compatibility, and inspecting sampler state. These APIs are useful for validating checkpoints before loading and debugging training workflows.

**Key Features:**
- Checkpoint metadata inspection (base model, LoRA status, rank)
- Sampler state querying (loaded weights, base model)
- Training run listing and detail retrieval
- LoRA rank compatibility validation
- Training run lookup from tinker:// paths

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_CHECKPOINT_PATH` (optional, specific checkpoint to inspect)
- `TINKER_SAMPLER_ID` (optional, sampler to query)
- `TINKER_EXPECTED_RANK` (optional, expected LoRA rank for validation)

**Use Cases:**
- Validate checkpoint compatibility before loading into a sampler
- Debug why a sampler has unexpected behavior (check loaded weights)
- Audit training runs and their associated checkpoints
- Verify LoRA rank matches training configuration

### checkpoint_download.exs

This example demonstrates the complete checkpoint download workflow with **memory-efficient streaming**. Uses `Finch.stream_while/5` to download archives directly to disk with O(1) memory usage, making it safe to download large checkpoints (100MB-GBs) without risk of OOM errors. Includes intelligent fallback mechanisms to automatically discover available checkpoints when none are explicitly specified.

**Key Features:**
- **Streaming downloads** - O(1) memory usage regardless of file size
- **Progress callbacks** - Real-time download progress tracking
- Checkpoint discovery and validation
- Archive URL retrieval
- Tar archive extraction with automatic cleanup
- Automatic cleanup of temporary files
- Fallback checkpoint creation for testing

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_CHECKPOINT_PATH` (optional, explicit checkpoint to download)
- `TINKER_OUTPUT_DIR` (optional, defaults to current directory)
- `FORCE` (optional, "true" to overwrite existing directories)
- `TINKER_BASE_MODEL` (optional, used for fallback checkpoint generation)

### async_client_creation.exs

This example illustrates asynchronous client creation patterns enabling concurrent initialization of multiple sampling clients. It demonstrates the use of Elixir tasks for parallel operations and efficient resource utilization.

**Key Features:**
- Asynchronous sampling client creation
- Concurrent multi-client initialization
- Task-based parallelism with Task.await_many
- Performance timing and reporting
- Error handling for concurrent operations

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, for single client mode)
- `TINKER_CHECKPOINT_PATHS` (optional, comma-separated paths for concurrent mode)

### cli_run_text.exs

This example demonstrates programmatic usage of the Tinkex CLI interface for text-based sampling operations. It shows how to construct CLI arguments dynamically and invoke the CLI from within Elixir code.

**Key Features:**
- Programmatic CLI invocation
- Dynamic argument construction
- Configuration via environment variables
- JSON output support
- Error handling and reporting

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional)
- `TINKER_PROMPT` (optional)
- `TINKER_MAX_TOKENS` (optional)
- `TINKER_TEMPERATURE` (optional)
- `TINKER_NUM_SAMPLES` (optional)

### cli_run_prompt_file.exs

This example demonstrates CLI usage with file-based prompts, showing how to prepare prompt files, execute CLI commands with file inputs, and capture JSON-formatted outputs to disk.

**Key Features:**
- Prompt file preparation and management
- File-based CLI invocation
- JSON output capture
- Temporary file handling
- Output preview and verification

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional)
- `TINKER_PROMPT` or `TINKER_PROMPT_TOKENS` (optional, prompt file content)

### metrics_live.exs

Issue a live sampling request, then print the aggregated metrics snapshot so you can confirm latency percentiles and success counters without extra scripting.

**Key Features:**
- Resets metrics at start for a clean run
- Performs a single live sampling call
- Prints counters plus p50/p95/p99 latency from `Tinkex.Metrics`

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional, defaults to production)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional)
- `TINKER_MAX_TOKENS`, `TINKER_TEMPERATURE`, `TINKER_NUM_SAMPLES`, `TINKER_SAMPLE_TIMEOUT` (optional)

### telemetry_live.exs

Basic telemetry example that starts a reporter, logs custom events, performs sampling, and flushes telemetry to the Tinker backend.

**Key Features:**
- Manual reporter lifecycle management
- Custom event logging via `Reporter.log/4`
- HTTP telemetry capture from sampling operations
- Synchronous flush before shutdown

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional, defaults to production)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional)

### telemetry_reporter_demo.exs

Comprehensive demonstration of all Tinkex.Telemetry.Reporter features including session lifecycle, exception logging, retry logic, and graceful shutdown.

**Key Features:**
- Session lifecycle events (SESSION_START, SESSION_END)
- Generic event logging with custom data and severity levels
- Exception logging (fatal and non-fatal with stacktrace capture)
- Automatic HTTP telemetry capture from sampling
- Retry with exponential backoff (configurable max_retries, retry_base_delay_ms)
- Wait-until-drained semantics for reliable shutdown
- Graceful shutdown with `Reporter.stop/2`
- Configurable HTTP timeout and flush parameters

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional, defaults to production)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional)

**Use Cases:**
- Understanding telemetry reporter configuration options
- Testing telemetry integration before production deployment
- Debugging telemetry issues with verbose event logging
- Learning the reporter API and lifecycle management

### retry_and_capture.exs

Shows how to combine the new retry helper (`Tinkex.Retry.with_retry/3`) with telemetry events and exception capture macros. It emits retry telemetry for each attempt, retries synthetic 500 errors, and logs a fatal exception through the telemetry reporter if retries are exhausted.

**Key Features:**
- Pure Elixir retry loop with jittered backoff and telemetry emission
- Console logging of retry telemetry without sleeps
- Optional telemetry reporter bootstrap via `Tinkex.ServiceClient` (requires `TINKER_API_KEY`; uses live session creation)
- Exception capture via telemetry capture macros

**Configuration Variables:**
- `TINKER_API_KEY` (optional, required only if you want backend telemetry)
- `TINKER_BASE_URL` (optional, used when reporter is started)

**Use Cases:**
- Learning the retry helper and telemetry event shapes
- Exercising capture macros with a real telemetry reporter
- Adding defensive retries to client code paths without external dependencies

**Run it:**

```bash
# sends telemetry if TINKER_API_KEY is set (auto-creates a live session)
TINKER_API_KEY=your-key mix run examples/retry_and_capture.exs
# or run without the env var to stay local/console-only
mix run examples/retry_and_capture.exs
```

## Common Patterns

Several patterns appear consistently across these examples and represent best practices for working with the Tinkex SDK:

**Application Startup:** All examples begin with `Application.ensure_all_started(:tinkex)` to ensure proper initialization of the SDK and its dependencies.

**Configuration Management:** Examples use environment variables extensively, providing sensible defaults while allowing customization for different deployment scenarios.

**Error Handling:** Examples demonstrate proper error handling using Elixir's tagged tuple pattern, with fallback behaviors and user-friendly error messages.

**Resource Cleanup:** Examples properly clean up resources by stopping GenServer processes and removing temporary files when operations complete.

**Async Operations:** Examples that perform network operations use Task-based asynchronous patterns to avoid blocking the caller and enable concurrent operations.

## Troubleshooting

If you encounter issues running these examples, consider the following:

**Authentication Failures:** Verify that your `TINKER_API_KEY` is valid and has not expired. The key should be set as an environment variable before running any example.

**Network Connectivity:** Ensure you have network access to the Tinker API endpoints. If using a custom base URL, verify the endpoint is reachable and properly configured.

**Model Availability:** Some models may not be available in all deployment environments. If you encounter model-related errors, try using a different base model or verify that your account has access to the specified model.

**Timeout Issues:** Long-running operations may exceed default timeout values. Consider increasing timeout values through configuration or environment variables if you encounter timeout errors.

**Checkpoint Not Found:** In checkpoint examples, ensure that checkpoints actually exist for your account. The checkpoint download example includes automatic fallback mechanisms, but other examples may require valid checkpoint identifiers.

## Additional Resources

For more detailed information about specific SDK features and APIs, refer to the main Tinkex documentation and the implementation guides in the `20251121/tinker-updates/` directory, which provide comprehensive technical specifications and usage patterns.

## Expected Output

````bash
$ ./examples/run_all.sh

==> Running examples/sampling_basic.exs
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Received 1 sequence(s):
Sample 1:  How are you? I haven’t been around much lately, have I?
I have been busy with my job, I have been busy with my family, I have been busy with the house, I have been busy with getting ready for Christmas, and I have been busy with all sorts of other things.
I am sorry

==> Running examples/training_loop.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: 'Fine-tuning sample prompt'
Sample after training: false

[step] creating ServiceClient...
[step] creating ServiceClient completed in 549ms
[step] creating TrainingClient (LoRA rank=16)...
[note] this may take 30-120s on first run (model loading)...
[step] creating TrainingClient (LoRA rank=16) completed in 263ms
[step] building model input...
[step] got 6 tokens: [128000, 64816, 2442, 38302, 6205, 10137]
[step] building model input completed in 1.31s
[step] running forward_backward...
[step] forward_backward completed in 3.95s
[metrics] forward_backward: %{"clock_cycle:unique" => 3128535.0, "loss:sum" => 85.29592895507812}
[step] running optim_step...
[step] optim_step completed in 1.36s
[metrics] optim_step: (none - optimizer doesn't compute metrics)
[step] saving weights for sampler...
[step] save_weights_for_sampler completed in 7.57s
[result] save_weights: %{"path" => "tinker://18985ee5-4dd4-556a-96ef-ed73df10b976:train:0/sampler_weights/sampler-weights", "sampling_session_id" => nil, "size_bytes" => nil, "type" => "save_weights_for_sampler"}

[done] Training loop finished in 12.89s

==> Running examples/custom_loss_training.exs
================================================================================
Custom Loss Training (Live)
================================================================================

Base URL : https://tinker.thinkingmachines.dev/services/tinker-prod
Base model : meta-llama/Llama-3.1-8B

Creating training client...
Preparing training datum for prompt: Name three planets in the solar system.

Running forward_backward_custom...
Custom loss completed in 10227 ms

Running optim_step...
optim_step succeeded.

=== ForwardBackwardOutput ===
loss_fn_output_type: CrossEntropyLossReturn
metrics: %{"clock_cycle:unique" => 5864459.0, "custom_perplexity" => 201762.703125, "loss:sum" => 12.214847564697266}
loss_fn_outputs (truncated):
[
  %{
    "elementwise_loss" => %{
      "data" => [2.1878914833068848, 1.4284495115280151, 0.9292365312576294,
       1.1109141111373901, 1.0874944925308228, 0.9503259658813477,
       1.0561927556991577, 1.140026330947876, 2.3243160247802734],
      "dtype" => "float32",
      "shape" => ~c"\t"
    },
    "logprobs" => %{
      "data" => [-19.691022872924805, -12.856045722961426, -8.363128662109375,
       -9.9982271194458, -9.787450790405273, -8.552933692932129,
       -9.50573444366455, -10.260236740112305, -20.91884422302246],
      "dtype" => "float32",
      "shape" => ~c"\t"
    }
  }
]

Success! Gradients were sent to the backend and optim_step is ready.

==> Running examples/forward_inference.exs
=== Forward Inference Example ===
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: Hello from forward inference!

Creating training client...
Building model input from prompt...
Token count: 6

Running forward pass (inference only, no backward)...

Forward pass completed in 7282ms
Output type: CrossEntropyLossReturn
Metrics: %{"clock_cycle:unique" => 3128539.0, "loss:sum" => 71.73094177246094}
Number of loss_fn_outputs: 1

=== Nx Tensor Conversion Demo ===
Nx default backend: {EXLA.Backend, []}
Converted to Nx tensor:
  Shape: {6}
  Type: {:f, 32}
  First 5 values: [-19.69261360168457, -10.21618366241455, -9.270523071289062, -8.560188293457031, -9.272642135620117]

EXLA-accelerated operations:
  Mean: -11.955157279968262
  Min: -19.69261360168457
  Max: -8.560188293457031

==> Running examples/structured_regularizers.exs
================================================================================
Structured Regularizers in Tinkex
================================================================================

This example demonstrates custom loss computation with composable regularizers.
The total loss is computed as:

  loss_total = base_loss + Σ(weight_i × regularizer_i_loss)

Each regularizer can track gradient norms for monitoring training dynamics.


--- 1. Creating RegularizerSpec Configurations ---

Created L1 sparsity regularizer via NxPenalties adapter (weight=0.01)
Created entropy regularizer via NxPenalties adapter (weight=0.001)
Created entropy (temperature-scaled) regularizer via NxPenalties adapter (weight=0.001, temperature=0.5)
Created L2 regularizer via NxPenalties adapter (weight=0.005)
Created Elastic Net regularizer via NxPenalties adapter (weight=0.002)
Created KL divergence regularizer (forward) via NxPenalties adapter (weight=0.01)
Created KL divergence regularizer (reverse) via NxPenalties adapter (mode-seeking, weight=0.01)
Created KL divergence regularizer (symmetric) via NxPenalties adapter (balanced, weight=0.01)
Created consistency regularizer via NxPenalties adapter (weight=0.02)
Created orthogonality regularizer via NxPenalties adapter (weight=0.003)
Created gradient penalty regularizer via NxPenalties adapter (weight=0.001)

--- 2. Defining Base Loss Function ---

Base loss function: Negative Log-Likelihood with perplexity metric

--- 3. Creating Mock Data ---

Mock logprobs shape: {10}
Mock logprobs values: [-0.5, -1.2000000476837158, -0.800000011920929, -2.0999999046325684, -0.30000001192092896, -1.5, -0.8999999761581421, -1.7999999523162842, -0.6000000238418579, -1.100000023841858]

--- 4. Baseline: Base Loss Only ---

Base loss only:
  loss_total: 1.08
  perplexity: 2.9447

--- 5. With Regularizers (Parallel Execution) ---

Composed loss with 11 regularizers:
  loss_total: 1.3016
  base_loss: 1.08
  regularizer_total: 0.2216

Per-regularizer breakdown:
  consistency:
    value: 0.0085
    weight: 0.02
    contribution: 0.0002
  elastic_net:
    value: 12.36
    weight: 0.002
    contribution: 0.0247
  entropy:
    value: -3.1972
    weight: 0.001
    contribution: -0.0032
  entropy_sharp:
    value: -1.9354
    weight: 0.001
    contribution: -0.0019
  gradient_penalty:
    value: 4.6754
    weight: 0.001
    contribution: 0.0047
  kl_forward:
    value: 6.087
    weight: 0.01
    contribution: 0.0609
  kl_reverse:
    value: -1.1569
    weight: 0.01
    contribution: -0.0116
  kl_symmetric:
    value: 2.465
    weight: 0.01
    contribution: 0.0247
  l1_sparsity:
    value: 10.8
    weight: 0.01
    contribution: 0.108
  l2_weight_decay:
    value: 3.036
    weight: 0.005
    contribution: 0.0152
  orthogonality:
    value: 0.0
    weight: 0.003
    contribution: 0.0

--- 6. With Gradient Norm Tracking ---

Gradient norms for training dynamics monitoring:
  base_loss grad_norm: 0.3162
  total_grad_norm: 0.3575

Per-regularizer gradient norms:
  consistency:
    grad_norm: 0.0
    grad_norm_weighted: 0.0
  elastic_net:
    grad_norm: 4.8349
    grad_norm_weighted: 0.00967
  entropy:
    grad_norm: 0.6867
    grad_norm_weighted: 6.87e-4
  entropy_sharp:
    grad_norm: 0.4833
    grad_norm_weighted: 4.83e-4
  gradient_penalty:
    grad_norm: 0.0
    grad_norm_weighted: 0.0
  kl_forward:
    grad_norm: 0.0
    grad_norm_weighted: 0.0
  kl_reverse:
    grad_norm: 0.0
    grad_norm_weighted: 0.0
  kl_symmetric:
    grad_norm: 0.0
    grad_norm_weighted: 0.0
  l1_sparsity:
    grad_norm: 3.1623
    grad_norm_weighted: 0.031623
  l2_weight_decay:
    grad_norm: 3.4848
    grad_norm_weighted: 0.017424
  orthogonality:
    grad_norm: 0.0
    grad_norm_weighted: 0.0

--- 7. Sequential vs Parallel Execution ---

Execution time comparison:
  Parallel: 2461 μs
  Sequential: 3244 μs
  Results match: true

--- 8. Async Regularizers (for I/O-bound operations) ---

Created async regularizer (simulates external API call)
Async regularizer result:
  loss_total: 1.1016
  async_external_validation contribution: 0.0216
  Execution time: 11135 μs

--- 9. Direct Executor Usage ---

Single regularizer execution via Executor:
  name: l1_sparsity
  value: 10.8
  contribution: 0.108
  grad_norm: 3.1623

All regularizers via Executor.execute_all:
  l1_sparsity: value=10.8, grad_norm=3.1623
  entropy: value=-3.1972, grad_norm=0.6867
  entropy_sharp: value=-1.9354, grad_norm=0.4833
  l2_weight_decay: value=3.036, grad_norm=3.4848
  elastic_net: value=12.36, grad_norm=4.8349
  kl_forward: value=6.087, grad_norm=0.0
  kl_reverse: value=-1.1569, grad_norm=0.0
  kl_symmetric: value=2.465, grad_norm=0.0
  consistency: value=0.0085, grad_norm=0.0
  orthogonality: value=0.0, grad_norm=0.0
  gradient_penalty: value=4.6754, grad_norm=0.0

--- 10. Direct GradientTracker Usage ---

Gradient norm for sum(x):
  grad_norm: 3.1623
  (Expected: sqrt(n) = sqrt(10) ≈ 3.162)

Gradient norm for sum(x^2):
  grad_norm: 7.6681
  (Gradient is 2x, so norm depends on input values)

--- 11. Telemetry Integration ---


14:48:47.612 [info] The function passed as a handler with ID "tinkex-regularizer-3" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
Attached telemetry handler: tinkex-regularizer-3

Running pipeline with telemetry (watch for log output):

14:48:47.624 [info] Custom loss starting: regularizers=1 track_grad_norms=true

14:48:47.625 [info] Regularizer l1_sparsity starting

14:48:47.625 [info] Regularizer l1_sparsity value=10.8 contribution=0.108 in 0ms grad_norm=3.1623

14:48:47.625 [info] Custom loss computed in 1ms total=1.188 regularizer_total=0.108 regularizers=1
Detached telemetry handler

--- 12. JSON Serialization ---

CustomLossOutput as JSON:
{
  "loss_total": 1.3015642880909144,
  "regularizers": {
    "consistency": {
      "value": 0.008500001393258572,
      "custom": {
        "consistency_metric": "mse"
      },
      "weight": 0.02,
      "contribution": 1.7000002786517145e-4,
      "grad_norm": 0.0,
      "grad_norm_weighted": 0.0
    },
    "elastic_net": {
      "value": 12.360000610351562,
      "custom": {
        "elastic_net": 12.360000610351562,
        "l1_ratio": 0.6
      },
      "weight": 0.002,
      "contributio...

(Output truncated for display)

RegularizerOutput as JSON:
{
  "name": "l1_sparsity",
  "value": 10.80000114440918,
  "custom": {
    "l1_mean": 1.0800001621246338,
    "l1_raw": 10.80000114440918
  },
  "weight": 0.01,
  "contribution": 0.1080000114440918,
  "grad_norm": 3.1622776985168457,
  "grad_norm_weighted": 0.03162277698516846
}

--- 13. Error Handling ---

Caught expected error for duplicate names:
  Duplicate regularizer names: ["dup"]

Caught expected error for invalid base_loss_fn

--- 14. Module-Based Regularizer (Behaviour) ---

Module-based regularizer (implements Tinkex.Regularizer behaviour):
  name: module_l1
  loss: 10.8
  metrics: %{"l1_value" => 10.80000114440918}

--- 15. Live API Usage ---

To use with a real Tinker server, replace Pipeline.compute with TrainingClient:

```elixir
# 1. Connect to server
config = Tinkex.Config.new(
  host: "your-tinker-host",
  api_key: System.get_env("TINKER_API_KEY")
)

# 2. Create training client
{:ok, session} = Tinkex.SessionManager.start_session(config, "your-model")
{:ok, client} = Tinkex.TrainingClient.create(session)

# 3. Prepare training data (tokenized)
data = [
  %Datum{
    inputs: %ModelInput{tokens: [1, 2, 3, 4, 5]},
    targets: %ModelInput{tokens: [6, 7, 8, 9, 10]}
  }
]

# 4. Define regularizers
regularizers = [
  RegularizerSpec.new(fn: &l1_sparsity/2, weight: 0.01, name: "l1"),
  RegularizerSpec.new(fn: &entropy/2, weight: 0.001, name: "entropy")
]

# 5. Call forward_backward_custom (hits live API!)
{:ok, task} = TrainingClient.forward_backward_custom(
  client, data, &base_loss/2,
  regularizers: regularizers,
  track_grad_norms: true
)

{:ok, output} = Task.await(task, :infinity)

# output is a CustomLossOutput with real logprobs from the server!
IO.puts("Total loss: #{output.loss_total}")
```

The Pipeline.compute calls in this example use mock logprobs.
TrainingClient.forward_backward_custom does a real forward pass on the server,
then runs Pipeline.compute with the actual logprobs returned.


================================================================================
Summary
================================================================================

The structured regularizer system provides:

1. **RegularizerSpec** - Type-safe configuration for regularizers
   - fn: Loss computation function (arity 2 or 3)
   - weight: Non-negative multiplier
   - name: Unique identifier for telemetry
   - async: Support for Task-returning functions

2. **Pipeline.compute/4** - Orchestrates full loss composition
   - Base loss + weighted regularizers
   - Parallel or sequential execution
   - Optional gradient norm tracking
   - Comprehensive telemetry

3. **Executor** - Low-level regularizer execution
   - execute_one/4 for single regularizer
   - execute_all/4 for batched execution
   - Timeout and error handling

4. **GradientTracker** - Nx-based gradient computation
   - compute_grad_norm/2 for L2 norms
   - grad_norm_for_regularizer/3 for per-regularizer tracking
   - total_grad_norm/4 for composed loss

5. **Telemetry** - Observable training dynamics
   - [:tinkex, :custom_loss, :start | :stop | :exception]
   - [:tinkex, :regularizer, :compute, :start | :stop | :exception]

6. **JSON Serialization** - Export metrics for analysis
   - CustomLossOutput implements Jason.Encoder
   - RegularizerOutput implements Jason.Encoder

For production use with a Tinker backend, wrap these in:

  {:ok, task} = TrainingClient.forward_backward_custom(
    client, data, base_loss_fn,
    regularizers: regularizers,
    track_grad_norms: true
  )
  {:ok, output} = Task.await(task)

================================================================================


==> Running examples/structured_regularizers_live.exs
================================================================================
Structured Regularizers - Live API Example
================================================================================

Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Model: meta-llama/Llama-3.1-8B

Creating training client...
Building training datum from prompt: The quick brown fox jumps over the lazy dog.
Token count: 11

--- Defining Custom Loss + Regularizers ---


--- Running forward_backward_custom (Live API) ---

Completed in 11312ms

=== Metrics ===
base_nll: 12.02071
clock_cycle:unique: 5864466.0
consistency: 14.65879
custom_perplexity: 166160.59375
elastic_net: 71.157845
entropy: 1.35026
gradient_penalty: 5.366751
kl_forward: -0.003815
kl_reverse: 9.622814
kl_symmetric: 4.809499
l1: 12.02071
l2: 15.366093
loss:sum: 13.150629
orthogonality: 0.0

================================================================================
Success! Custom loss with regularizer terms computed via live Tinker API.
================================================================================

==> Running examples/sessions_management.exs
=== Tinkex Session Management Example ===

Starting ServiceClient...
Creating RestClient...

--- Listing Sessions ---
Found 10 sessions:
  • cd0d41a3-51c2-5a14-9ba8-af64d1e094c7
  • 68d03eaa-9b06-5863-95bc-c3acdb3545eb
  • def55c59-9dbc-5833-aa7b-b763dbb38c75
  • 4967ce58-2090-5211-af93-6c0acabbb477
  • 18985ee5-4dd4-556a-96ef-ed73df10b976
  • 09ef40a7-fc76-54dc-8145-39d0fbf23a10
  • 966d6790-9fe3-54dd-9dbe-4f61f6840bde
  • 098378b0-5cdd-5c5f-b566-4d3905bddeee
  • 6ec7d725-f0b6-59f5-8bf8-029ea7b36459
  • 3b373960-23fc-5626-a491-73ddccf2c465

--- Session Details: cd0d41a3-51c2-5a14-9ba8-af64d1e094c7 ---
Training Runs: 0
Samplers: 0

=== Example Complete ===

==> Running examples/checkpoints_management.exs
=== Tinkex Checkpoint Management Example ===

--- All User Checkpoints ---
Found 20 of 100 checkpoints:

  sampler_weights/sampler-weights
    Path: tinker://18985ee5-4dd4-556a-96ef-ed73df10b976:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-05 00:48:20.055773Z

  weights/recovery-live-2
    Path: tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:17:00.814946Z

  weights/recovery-live-1
    Path: tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:16:35.106294Z

  weights/recovery-live-2
    Path: tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:14:45.325072Z

  weights/recovery-live-1
    Path: tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:14:25.359194Z

  sampler_weights/sampler-weights
    Path: tinker://c0fe4b75-d2a6-5dfc-9b5f-bd243c4b8690:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-04 03:27:53.190382Z

  sampler_weights/sampler-weights
    Path: tinker://5fa8e8b9-6eaa-57c8-bc2b-7a89c2783243:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-04 02:31:39.923898Z

  weights/async_demo_checkpoint
    Path: tinker://9677c040-d833-5325-8a9d-4c3a1f816328:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-12-03 20:35:36.090807Z

  sampler_weights/sampler-weights
    Path: tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-12-03 20:32:09.677474Z

  weights/async_demo_checkpoint
    Path: tinker://170beeb9-9fa9-5011-b896-ba0616c7e94d:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-11-28 02:43:17.958810Z

  sampler_weights/sampler-weights
    Path: tinker://50398661-7150-5042-9891-5611cb535340:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-28 02:40:09.047757Z

  sampler_weights/sampler-weights
    Path: tinker://a5d5031a-72a5-5180-8417-e32c5c0a9598:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-28 02:32:20.546936Z

  weights/async_demo_checkpoint
    Path: tinker://47f7276e-454e-5dde-9188-1c1e3c3536b5:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-11-28 02:31:18.060463Z

  sampler_weights/async_demo_weights
    Path: tinker://a7517405-527c-571e-9fe2-c94e6b3cf548:train:0/sampler_weights/async_demo_weights
    Type: sampler
    Size: 51.0 MB
    Public: false
    Created: 2025-11-28 02:30:25.465448Z

  sampler_weights/async_demo_weights
    Path: tinker://73c466d3-b063-56a2-86d0-d035a1392c23:train:0/sampler_weights/async_demo_weights
    Type: sampler
    Size: 51.0 MB
    Public: false
    Created: 2025-11-28 02:29:56.731159Z

  sampler_weights/sampler-weights
    Path: tinker://53f0586d-3f98-58e5-b04e-297ea717378e:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:58:37.961274Z

  sampler_weights/sampler-weights
    Path: tinker://f4521144-ef58-53ec-950c-29260c9b1a41:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:44:47.285732Z

  sampler_weights/sampler-weights
    Path: tinker://1ec257a9-28bf-559c-aa73-e54a09cce5bd:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:37:23.205082Z

  sampler_weights/sampler-weights
    Path: tinker://046c91d9-d9f4-5dd6-ac42-0135bbde947e:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:15:50.316094Z

  sampler_weights/sampler-weights
    Path: tinker://fdf7af94-bcce-5bf7-847b-a159e8bfb025:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:11:28.567500Z


--- All User Checkpoints (paginated) ---
Fetched 50 (100 total)
  sampler_weights/sampler-weights
    Path: tinker://18985ee5-4dd4-556a-96ef-ed73df10b976:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-05 00:48:20.055773Z

  weights/recovery-live-2
    Path: tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:17:00.814946Z

  weights/recovery-live-1
    Path: tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:16:35.106294Z

  weights/recovery-live-2
    Path: tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:14:45.325072Z

  weights/recovery-live-1
    Path: tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-04 23:14:25.359194Z

  sampler_weights/sampler-weights
    Path: tinker://c0fe4b75-d2a6-5dfc-9b5f-bd243c4b8690:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-04 03:27:53.190382Z

  sampler_weights/sampler-weights
    Path: tinker://5fa8e8b9-6eaa-57c8-bc2b-7a89c2783243:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-04 02:31:39.923898Z

  weights/async_demo_checkpoint
    Path: tinker://9677c040-d833-5325-8a9d-4c3a1f816328:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-12-03 20:35:36.090807Z

  sampler_weights/sampler-weights
    Path: tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-12-03 20:32:09.677474Z

  weights/async_demo_checkpoint
    Path: tinker://170beeb9-9fa9-5011-b896-ba0616c7e94d:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-11-28 02:43:17.958810Z

  sampler_weights/sampler-weights
    Path: tinker://50398661-7150-5042-9891-5611cb535340:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-28 02:40:09.047757Z

  sampler_weights/sampler-weights
    Path: tinker://a5d5031a-72a5-5180-8417-e32c5c0a9598:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-28 02:32:20.546936Z

  weights/async_demo_checkpoint
    Path: tinker://47f7276e-454e-5dde-9188-1c1e3c3536b5:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-11-28 02:31:18.060463Z

  sampler_weights/async_demo_weights
    Path: tinker://a7517405-527c-571e-9fe2-c94e6b3cf548:train:0/sampler_weights/async_demo_weights
    Type: sampler
    Size: 51.0 MB
    Public: false
    Created: 2025-11-28 02:30:25.465448Z

  sampler_weights/async_demo_weights
    Path: tinker://73c466d3-b063-56a2-86d0-d035a1392c23:train:0/sampler_weights/async_demo_weights
    Type: sampler
    Size: 51.0 MB
    Public: false
    Created: 2025-11-28 02:29:56.731159Z

  sampler_weights/sampler-weights
    Path: tinker://53f0586d-3f98-58e5-b04e-297ea717378e:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:58:37.961274Z

  sampler_weights/sampler-weights
    Path: tinker://f4521144-ef58-53ec-950c-29260c9b1a41:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:44:47.285732Z

  sampler_weights/sampler-weights
    Path: tinker://1ec257a9-28bf-559c-aa73-e54a09cce5bd:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:37:23.205082Z

  sampler_weights/sampler-weights
    Path: tinker://046c91d9-d9f4-5dd6-ac42-0135bbde947e:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:15:50.316094Z

  sampler_weights/sampler-weights
    Path: tinker://fdf7af94-bcce-5bf7-847b-a159e8bfb025:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 18:11:28.567500Z

  sampler_weights/sampler-weights
    Path: tinker://8eba0a5a-0dcf-57f3-9d0d-65ec6ef22a1f:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 17:53:03.197669Z

  sampler_weights/checkpoint_1764230891.2048833.pt
    Path: tinker://fa0ecefc-83b2-5e26-a2a9-aee483b913ba:train:0/sampler_weights/checkpoint_1764230891.2048833.pt
    Type: sampler
    Size: 5.77 GB
    Public: false
    Created: 2025-11-27 08:09:13.441453Z

  sampler_weights/checkpoint_1764230289.3815918.pt
    Path: tinker://bc33563e-6730-5cbe-9a25-43e11dbe5095:train:0/sampler_weights/checkpoint_1764230289.3815918.pt
    Type: sampler
    Size: 5.77 GB
    Public: false
    Created: 2025-11-27 07:59:06.047243Z

  sampler_weights/checkpoint_1764229717.8670213.pt
    Path: tinker://bfc7c5e5-0b90-55a1-8c97-fc8bdac649c9:train:0/sampler_weights/checkpoint_1764229717.8670213.pt
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-27 07:48:41.184106Z

  sampler_weights/checkpoint_1764229539.9387324.pt
    Path: tinker://9922175e-533d-52e3-a433-5e0fa645462c:train:0/sampler_weights/checkpoint_1764229539.9387324.pt
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-27 07:45:42.982073Z

  weights/demo-checkpoint-1764228622
    Path: tinker://8c4cfd17-df85-5634-badf-e12068d2efc8:train:0/weights/demo-checkpoint-1764228622
    Type: training
    Size: 126.3 MB
    Public: false
    Created: 2025-11-27 07:30:37.300885Z

  sampler_weights/checkpoint_1764215477.2502818.pt
    Path: tinker://daba87c6-4e86-5797-81d5-efe038b44524:train:0/sampler_weights/checkpoint_1764215477.2502818.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27 03:51:18.921217Z

  sampler_weights/checkpoint_1764127354.6624672.pt
    Path: tinker://d0fde479-adea-5e5a-9974-1196f01fbb82:train:0/sampler_weights/checkpoint_1764127354.6624672.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-26 03:22:37.215881Z

  sampler_weights/checkpoint_1764127169.5448663.pt
    Path: tinker://64c07d46-5af8-5290-b146-8b3b72fcd412:train:0/sampler_weights/checkpoint_1764127169.5448663.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-26 03:19:31.522096Z

  sampler_weights/checkpoint_1764126259.022441.pt
    Path: tinker://8ffd2ac2-df28-5c6d-959f-ca1f3b993f38:train:0/sampler_weights/checkpoint_1764126259.022441.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-26 03:04:20.853521Z

  sampler_weights/eval-checkpoint
    Path: tinker://1a518dcd-98f2-5dbb-8ce1-97659577228e:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:43:55.884275Z

  sampler_weights/eval-checkpoint
    Path: tinker://4f34e47f-b6c1-5acd-9939-2e87cfd516ac:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:43:13.608804Z

  sampler_weights/eval-checkpoint
    Path: tinker://4e5865b6-dc04-576a-9776-98935107b89a:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:42:41.563024Z

  sampler_weights/eval-checkpoint
    Path: tinker://79772ba6-f047-5446-b82f-3467b5cb36c7:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:41:53.766834Z

  sampler_weights/eval-checkpoint
    Path: tinker://c8874248-0e9b-5aba-9724-82c52ee91ec1:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:41:01.481661Z

  sampler_weights/eval-checkpoint
    Path: tinker://c9ad0180-7655-50c2-a957-6fd241e7103d:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:40:13.515136Z

  sampler_weights/eval-checkpoint
    Path: tinker://bbccf257-c3fd-5c91-a2d1-73fbbb8fd00e:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:38:23.104113Z

  sampler_weights/eval-checkpoint
    Path: tinker://b9102c50-fbff-5f74-a06b-a3dee4d14131:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:37:12.980263Z

  sampler_weights/eval-checkpoint
    Path: tinker://9e55e0f8-63df-5ea0-aa16-8621bdb9109c:train:0/sampler_weights/eval-checkpoint
    Type: sampler
    Size: 12.8 MB
    Public: false
    Created: 2025-11-23 23:33:52.872673Z

  sampler_weights/checkpoint_1763771890.680426.pt
    Path: tinker://0478a1ab-95af-5eae-bd70-d3d3b441c021:train:0/sampler_weights/checkpoint_1763771890.680426.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-22 00:38:16.947541Z

  sampler_weights/checkpoint_1763771611.2195318.pt
    Path: tinker://f620a60b-7b30-5e7e-bc11-da12b0fb0765:train:0/sampler_weights/checkpoint_1763771611.2195318.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-22 00:33:35.488576Z

  sampler_weights/checkpoint_1763771585.3579679.pt
    Path: tinker://0ad21c1d-0eeb-5518-a6c8-1c497af7c5d5:train:0/sampler_weights/checkpoint_1763771585.3579679.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-22 00:33:06.824152Z

  sampler_weights/checkpoint_1763769127.646869.pt
    Path: tinker://5a3335fe-65fe-5afa-a6b4-d1294887e5bc:train:0/sampler_weights/checkpoint_1763769127.646869.pt
    Type: sampler
    Size: 42.1 MB
    Public: false
    Created: 2025-11-21 23:52:11.116436Z

  sampler_weights/checkpoint_1763768362.9477212.pt
    Path: tinker://bf88076d-f29e-5366-9ab6-80e0c5f2995a:train:0/sampler_weights/checkpoint_1763768362.9477212.pt
    Type: sampler
    Size: 42.1 MB
    Public: false
    Created: 2025-11-21 23:39:24.802998Z

  sampler_weights/checkpoint_1763767972.2357357.pt
    Path: tinker://f9bc9e13-1901-5818-99bd-b2b01ee8bb5b:train:0/sampler_weights/checkpoint_1763767972.2357357.pt
    Type: sampler
    Size: 42.1 MB
    Public: false
    Created: 2025-11-21 23:32:53.740553Z

  sampler_weights/checkpoint_1763767641.9865937.pt
    Path: tinker://d32bb9c6-04c0-5cd1-9793-745e7043e1dc:train:0/sampler_weights/checkpoint_1763767641.9865937.pt
    Type: sampler
    Size: 42.1 MB
    Public: false
    Created: 2025-11-21 23:27:23.422596Z

  sampler_weights/checkpoint_1763766626.1265566.pt
    Path: tinker://e5dfefc6-65fc-57bb-9a90-1bb3ef61f003:train:0/sampler_weights/checkpoint_1763766626.1265566.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-21 23:10:27.549888Z

  sampler_weights/checkpoint_1763765822.8686664.pt
    Path: tinker://96e6f7ba-426a-5854-ae78-0ce919ac48ec:train:0/sampler_weights/checkpoint_1763765822.8686664.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-21 22:57:05.276026Z

  sampler_weights/checkpoint_1763674749.0143857.pt
    Path: tinker://c3ebbb74-61f2-5be9-9f6b-aa8c70d60cb2:train:0/sampler_weights/checkpoint_1763674749.0143857.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:39:11.188934Z

  sampler_weights/checkpoint_1763674591.9668543.pt
    Path: tinker://3784f9f8-0ac3-5596-9b11-0b2c154954e1:train:0/sampler_weights/checkpoint_1763674591.9668543.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:36:33.769394Z

Fetched 50 (100 total)
  sampler_weights/checkpoint_1763674539.0671499.pt
    Path: tinker://492f6734-8b07-5c76-82d9-23501232c523:train:0/sampler_weights/checkpoint_1763674539.0671499.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:35:41.390717Z

  sampler_weights/checkpoint_1763674470.2715266.pt
    Path: tinker://ca2be487-be03-5b7e-aead-b9baab3c2aa0:train:0/sampler_weights/checkpoint_1763674470.2715266.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:34:32.076428Z

  sampler_weights/checkpoint_1763674428.9740841.pt
    Path: tinker://a886468c-bc20-5257-ad57-abaf0c4c6b7b:train:0/sampler_weights/checkpoint_1763674428.9740841.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:33:51.074219Z

  sampler_weights/checkpoint_1763674248.9320633.pt
    Path: tinker://7921b3ab-d30f-5c76-a574-376e8cd3c12f:train:0/sampler_weights/checkpoint_1763674248.9320633.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:30:50.657760Z

  sampler_weights/checkpoint_1763674208.8772275.pt
    Path: tinker://457e528f-d601-565e-b1a6-5c7914fcc3f2:train:0/sampler_weights/checkpoint_1763674208.8772275.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:30:10.982809Z

  sampler_weights/checkpoint_1763674139.0204463.pt
    Path: tinker://eff1740d-a0bb-5d01-a42c-94e95342bb82:train:0/sampler_weights/checkpoint_1763674139.0204463.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:29:00.808793Z

  sampler_weights/checkpoint_1763674099.0486119.pt
    Path: tinker://8cdb2b79-83c0-5c53-a025-1e7a83d2239f:train:0/sampler_weights/checkpoint_1763674099.0486119.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-20 21:28:20.577549Z

  sampler_weights/claim-extractor-scifact-20251119T041117
    Path: tinker://554bb03e-1d71-58cc-824d-1625d267f8be:train:0/sampler_weights/claim-extractor-scifact-20251119T041117
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-19 04:25:05.755741Z

  sampler_weights/claim-extractor-scifact-micro-20251119T023422
    Path: tinker://b484da35-1b57-5519-8e20-74ac4ec6776f:train:0/sampler_weights/claim-extractor-scifact-micro-20251119T023422
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-19 02:34:46.769328Z

  sampler_weights/claim-extractor-scifact-micro-20251119T000437
    Path: tinker://d459b31c-3f66-59dd-8fbc-500f9570b022:train:0/sampler_weights/claim-extractor-scifact-micro-20251119T000437
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-19 00:04:42.381541Z

  sampler_weights/claim-extractor-scifact-20251118T220454
    Path: tinker://8ff091db-2061-5279-ac9d-1dbf50acb114:train:0/sampler_weights/claim-extractor-scifact-20251118T220454
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-18 22:22:12.903958Z

  sampler_weights/claim-extractor-scifact-20251118T173307
    Path: tinker://ad9b0497-d1d0-5338-b603-fece00234d86:train:0/sampler_weights/claim-extractor-scifact-20251118T173307
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-18 17:48:19.509993Z

  sampler_weights/claim-extractor-scifact-20251112T070048
    Path: tinker://c0e9f526-4398-486e-bb03-755037abd8a7/sampler_weights/claim-extractor-scifact-20251112T070048
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-12 07:07:48.144064Z

  sampler_weights/claim-extractor-scifact-debug-20251112T064537
    Path: tinker://4c2d7d55-723d-421c-be56-2e3e71950f73/sampler_weights/claim-extractor-scifact-debug-20251112T064537
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-12 06:46:48.975254Z

  sampler_weights/claim-extractor-scifact-debug-20251112T064537-step20
    Path: tinker://4c2d7d55-723d-421c-be56-2e3e71950f73/sampler_weights/claim-extractor-scifact-debug-20251112T064537-step20
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-12 06:46:20.681625Z

  sampler_weights/claim-extractor-scifact-debug-20251112T004313
    Path: tinker://61541b24-18f0-4e27-a698-40e979fe0fb7/sampler_weights/claim-extractor-scifact-debug-20251112T004313
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-12 00:45:01.525748Z

  sampler_weights/claim-extractor-scifact-debug-20251112T004313-step20
    Path: tinker://61541b24-18f0-4e27-a698-40e979fe0fb7/sampler_weights/claim-extractor-scifact-debug-20251112T004313-step20
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-12 00:44:29.092184Z

  sampler_weights/claim-extractor-scifact-20251111T225459
    Path: tinker://3d88c2d0-ec2e-4f37-90f6-ad8855e1f5bd/sampler_weights/claim-extractor-scifact-20251111T225459
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-11 23:04:09.346257Z

  sampler_weights/claim-extractor-scifact-debug-20251111T220611
    Path: tinker://12d00816-3c6a-4fbd-b792-f30f66c1f6e2/sampler_weights/claim-extractor-scifact-debug-20251111T220611
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-11 22:08:09.959762Z

  sampler_weights/claim-extractor-scifact-debug-20251111T220611-step20
    Path: tinker://12d00816-3c6a-4fbd-b792-f30f66c1f6e2/sampler_weights/claim-extractor-scifact-debug-20251111T220611-step20
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-11 22:07:05.943612Z

  sampler_weights/claim-extractor-scifact-debug-20251111T213557
    Path: tinker://89aa268e-9532-4e5f-97aa-c228d7f86cbf/sampler_weights/claim-extractor-scifact-debug-20251111T213557
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-11 21:37:56.986377Z

  sampler_weights/claim-extractor-scifact-debug-20251111T213557-step20
    Path: tinker://89aa268e-9532-4e5f-97aa-c228d7f86cbf/sampler_weights/claim-extractor-scifact-debug-20251111T213557-step20
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-11 21:37:26.498233Z

  sampler_weights/claim-extractor-scifact-debug
    Path: tinker://7a4a9939-61ec-4982-9240-ecf40f7de451/sampler_weights/claim-extractor-scifact-debug
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-11 21:25:27.074834Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://7808d627-6a6f-4d38-af06-7d7e17662504/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-11 21:00:12.255132Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://9314e28c-6cf6-4b62-9eed-21b24384b2ee/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 19:38:29.156765Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://05d83bde-111d-44da-9f3e-80c63053f5dc/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 19:14:46.853453Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://216c1da7-a40e-481e-9ff1-91664d32df6f/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 19:07:06.230260Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://32e517fc-8980-4244-970a-77598702bb7b/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 18:37:33.121097Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://75f238d9-788a-4b15-ad11-4a27c3b6f2fe/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 18:35:13.649385Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://ae5c9b07-d765-4fb8-aa74-fb4839781eff/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 18:28:36.080161Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://314ca5b7-d1e8-48e7-8e1a-af899f831218/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 18:20:51.042305Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://4ca82d74-9e6d-486c-baf4-610f875bbff6/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 17:37:28.524613Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://952206f4-ceef-43ff-8ee4-f0dd16557955/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 17:34:16.304290Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://7a018085-7ea8-46a2-b070-2e6f64ecc03f/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 17:24:42.000819Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://e2261cbf-571b-44ed-ab1c-fb30bad8cb23/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 17:20:57.823861Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://672ddb08-c00e-40f9-9cd6-75d96d8f3c88/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 17:19:24.871822Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://f8ecb02f-d6a2-4f94-a6e8-90d0e6e0af6e/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 17:02:26.826126Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://f97b057b-a5d4-48d0-abee-288d598b959a/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 17:01:49.882479Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://83934987-0c45-4b62-8f87-b3098edf8bb0/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 16:31:19.498985Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://f781270c-abc7-4eb3-b40d-2b30ba6351d6/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 16:29:02.384505Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://a39cba93-8ae8-4134-b440-8c4e81e07929/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 16:15:45.231432Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://7f1f72c3-7040-4b11-98b6-c1f0e545b7e7/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 16:05:38.226751Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://be882e1a-3bee-42b3-b7c5-e9b41c653dc1/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 15:56:49.115534Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://e123b112-5a4f-4957-bc92-6169b580f6fe/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 15:46:48.628154Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://fb150365-dc79-4166-812b-a941cb35123f/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 15:27:30.872534Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://13fd1023-1433-4b22-bb8d-f2dd78274fc7/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 14:11:49.407842Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://8f51c170-e69b-44a5-98a1-241bc4a8ebfd/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 14:08:34.714697Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://6565b2a7-4123-4325-bb1c-f1dd4b51f4f0/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 13:58:24.829491Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://801ac30a-78b0-4faa-850d-1196f63c38cf/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 06:18:13.847517Z

  sampler_weights/claim-extractor-scifact
    Path: tinker://702d77bf-7bd3-474d-817a-fbf90575eb6e/sampler_weights/claim-extractor-scifact
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-09 06:13:22.659349Z


=== Example Complete ===

==> Running examples/weights_inspection.exs
=== Tinkex Weights Inspection Example ===

--- Training Runs ---
Found 10 training runs:

  68d03eaa-9b06-5863-95bc-c3acdb3545eb:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  def55c59-9dbc-5833-aa7b-b763dbb38c75:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  4967ce58-2090-5211-af93-6c0acabbb477:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  18985ee5-4dd4-556a-96ef-ed73df10b976:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:1
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:1/weights/recovery-live-2
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:0/weights/recovery-live-1
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  098378b0-5cdd-5c5f-b566-4d3905bddeee:train:1
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:1/weights/recovery-live-2
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  098378b0-5cdd-5c5f-b566-4d3905bddeee:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:0/weights/recovery-live-1
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  6ec7d725-f0b6-59f5-8bf8-029ea7b36459:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  3b373960-23fc-5626-a491-73ddccf2c465:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5


--- Training Run Details: 68d03eaa-9b06-5863-95bc-c3acdb3545eb:train:0 ---
  ID: 68d03eaa-9b06-5863-95bc-c3acdb3545eb:train:0
  Base Model: meta-llama/Llama-3.1-8B
  Is LoRA: true
  LoRA Rank: 16
  Corrupted: false
  Last Checkpoint: none
  Last Sampler Checkpoint: none
  Last Request: 2025-12-05 00:49:00.929754Z
  Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

--- User Checkpoints ---
Found 10 checkpoint(s):

  tinker://18985ee5-4dd4-556a-96ef-ed73df10b976:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 168.14 MB
    Time: 2025-12-05 00:48:20.055773Z

  tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:1/weights/recovery-live-2
    Type: training
    ID: weights/recovery-live-2
    Size: 252.22 MB
    Time: 2025-12-04 23:17:00.814946Z

  tinker://966d6790-9fe3-54dd-9dbe-4f61f6840bde:train:0/weights/recovery-live-1
    Type: training
    ID: weights/recovery-live-1
    Size: 252.22 MB
    Time: 2025-12-04 23:16:35.106294Z

  tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:1/weights/recovery-live-2
    Type: training
    ID: weights/recovery-live-2
    Size: 252.22 MB
    Time: 2025-12-04 23:14:45.325072Z

  tinker://098378b0-5cdd-5c5f-b566-4d3905bddeee:train:0/weights/recovery-live-1
    Type: training
    ID: weights/recovery-live-1
    Size: 252.22 MB
    Time: 2025-12-04 23:14:25.359194Z

  tinker://c0fe4b75-d2a6-5dfc-9b5f-bd243c4b8690:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 168.14 MB
    Time: 2025-12-04 03:27:53.190382Z

  tinker://5fa8e8b9-6eaa-57c8-bc2b-7a89c2783243:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 168.14 MB
    Time: 2025-12-04 02:31:39.923898Z

  tinker://9677c040-d833-5325-8a9d-4c3a1f816328:train:0/weights/async_demo_checkpoint
    Type: training
    ID: weights/async_demo_checkpoint
    Size: 152.98 MB
    Time: 2025-12-03 20:35:36.090807Z

  tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 84.1 MB
    Time: 2025-12-03 20:32:09.677474Z

  tinker://170beeb9-9fa9-5011-b896-ba0616c7e94d:train:0/weights/async_demo_checkpoint
    Type: training
    ID: weights/async_demo_checkpoint
    Size: 152.98 MB
    Time: 2025-11-28 02:43:17.958810Z


=== Example Complete ===

==> Running examples/checkpoint_download.exs
=== Tinkex Checkpoint Download Example ===

TINKER_CHECKPOINT_PATH not provided; downloading first available checkpoint:
  tinker://18985ee5-4dd4-556a-96ef-ed73df10b976:train:0/sampler_weights/sampler-weights

Downloading checkpoint: tinker://18985ee5-4dd4-556a-96ef-ed73df10b976:train:0/sampler_weights/sampler-weights
Output directory: /tmp/tinkex_checkpoints

Progress: 100.0% (168.1 MB / 168.1 MB)

Download complete!
Extracted to: /tmp/tinkex_checkpoints/18985ee5-4dd4-556a-96ef-ed73df10b976:train:0_sampler_weights_sampler-weights

Extracted files (3):
  • adapter_config.json (736 B)
  • adapter_model.safetensors (168.1 MB)
  • checkpoint_complete (0 B)

=== Example Complete ===

==> Running examples/async_client_creation.exs
=== Tinkex Async Client Creation Example ===

Creating sampling client asynchronously...
Task created, awaiting result...
✓ Sampling client created: #PID<0.321.0>

Creating LoRA training client asynchronously...
Task created, awaiting result...
✓ LoRA training client created: #PID<0.326.0>

Saving training state to create checkpoint...
✓ Saved state to: tinker://0927bbd5-890d-5599-9856-69cce21db777:train:0/weights/async_demo_checkpoint

Restoring training client from checkpoint asynchronously...
✓ Training client restored: #PID<0.341.0>

=== Example Complete ===

==> Running examples/cli_run_text.exs
Running CLI with args: run --base-model meta-llama/Llama-3.1-8B --prompt Hello from the CLI runner --max-tokens 64 --temperature 0.7 --num-samples 1 --api-key tml-mIf5gSt5tyewbDuXjwgeTkbdcgCZUpntGFyVBfKvmfGpb2FpJbfJ9tcFyYC5DXjcrAAAA
Starting sampling...
Sample 1:

This is the CLI runner. It is currently in an experimental state. If you face any issues please report them on the issue tracker.
The CLI runner is a CLI tool that runs tests using your existing configuration. This means that you can use it to run tests against a single environment, multiple environments, or use it
stop_reason=length | avg_logprob=-1.365
Sampling complete (1 sequences)
sampling response: %Tinkex.Types.SampleResponse{
  sequences: [
    %Tinkex.Types.SampledSequence{
      tokens: [198, 2028, 374, 279, 40377, 23055, 13, 1102, 374, 5131, 304, 459,
       22772, 1614, 13, 1442, 499, 3663, 904, 4819, 4587, 1934, 1124, 389, 279,
       4360, 29431, 627, 791, 40377, 23055, 374, 264, 40377, 5507, 430, 8640,
       7177, 1701, 701, 6484, 6683, 13, 1115, 3445, 430, 499, ...],
      logprobs: [-1.4361234903335571, -2.479361057281494, -0.25932776927948,
       -1.2123725414276123, -1.6413748264312744, -0.048216842114925385,
       -1.0027695894241333, -1.3641018867492676, -1.0831636190414429,
       -3.6615476608276367, -0.7715314626693726, -2.7191638946533203,
       -0.4583531618118286, -0.5444151163101196, -1.1914732456207275,
       -2.614192008972168, -0.012667667120695114, -7.911582946777344,
       -0.2652122974395752, -0.31163638830184937, -2.521589517593384,
       -0.7173861861228943, -0.05865137651562691, -1.2138450145721436,
       -0.5347287654876709, -0.8996114730834961, -0.011777156963944435,
       -1.3762850761413574, -0.7442678213119507, -0.09972235560417175,
       -0.00906707439571619, -0.3873786926269531, -0.444593608379364,
       -2.981180191040039, -0.2853538393974304, -0.30229970812797546,
       -2.0511136054992676, -1.7793821096420288, -2.8809404373168945,
       -3.8709161281585693, -2.2498362064361572, -2.1367833614349365,
       -0.5425164699554443, -2.7366628646850586, -1.1406540870666504,
       -0.43158265948295593, ...],
      stop_reason: :length
    }
  ],
  prompt_logprobs: nil,
  topk_prompt_logprobs: nil,
  type: "sample"
}

==> Running examples/cli_run_prompt_file.exs
Running CLI with prompt file /tmp/tinkex_prompt_5954.txt
Starting sampling...
Sampling complete (1 sequences)
JSON output written to /tmp/tinkex_output_6018.json
Preview:
{"prompt_logprobs":null,"sequences":[{"logprobs":[-7.96319580078125,-1.7995569705963135,-0.7040455341339111,-2.246551275253296,-1.2115405797958374,-7.837035655975342,-3.075432300567627,-7.406477928161621,-0.3570220470428467,-1.9917527437210083,-1.3402349948883057,-3.456505298614502,-0.8055366277694702,-2.099583625793457,-1.2591629028320312,-1.3160121440887451,-3.4967143535614014,-2.3119266033172607,-11.79848861694336,-5.338186264038086,-3.4330670833587646,-3.7198901176452637,-3.141948699951172,-0.026161331683397293,-1.6653755903244019,-0.03162405267357826,-3.069810628890991,-15.427691459655762,-2.413317918777466,-0.20740343630313873,-1.781112790107727,-1.21452796459198,-7.008791446685791,-8.362092018127441,-1.8042479753494263,-1.10298752784729,-7.477775573730469,-8.13217544555664,-2.3201980590820312,-4.633662223815918,-4.140694618225098,-5.963955879211426,-1.8250312805175781,-6.641912937164307,-0.9332862496376038,-4.5183281898498535,-5.844482421875,-2.3610100746154785,-2.9685559272766113,-3.1277875900268555,-11.624879837036133,-0.5474034547805786,-3.3870644569396973,-7.177423477172852,-1.9408257007598877,-0.286868155002594,-0.13570213317871094,-3.7800087928771973,-1.2897186279296875,-1.1051725149154663,-2.0236918926239014,-2.9605188369750977,-0.7718082070350647,-1.8585551977157593,-4.9193644523620605,-5.932526588439941,-1.8083453178405762,-5.84836483001709,-2.5370516777038574,-2.9574267864227295,-1.664341688156128,-3.8076682090759277,-2.0845351219177246,-0.40619027614593506,-0.9814534187316895,-0.5575854182243347,-4.759203910827637,-0.7834056615829468,-0.8127211928367615,-2.6250975131988525,-0.06558363884687424,-5.571848392486572,-0.9058957099914551,-3.1220479011535645,-1.1944575309753418,-1.7504912614822388,-1.0463886260986328,-1.1503291130065918,-0.5535348653793335,-2.727084159851074,-0.7947639226913452,-0.47700077295303345,-2.1005234718322754,-0.873145341873169,-3.016602039337158,-0.40251612663269043,-6.309215545654297,-0.7036334276199341,-0.12873491644859314,-1.336778998374939,-2.1923952102661133,-7.959309101104736,-0.2215152531862259,-13.867647171020508,-8.032867431640625,-2.264688491821289,-7.10334587097168,-0.09692396968603134,-0.19945241510868073,-0.036071691662073135,-2.0001604557037354,-0.49638301134109497,-2.4534177780151367,-5.783449172973633,-1.149391531944275,-4.21956729888916,-1.6345064640045166,-8.256973266601562,-0.4473314881324768,-3.060112953186035,-0.22193804383277893,-0.7761222124099731,-0.5606755018234253,-5.176653861999512,-7.524579048156738,-5.220108509063721,-10.23263931274414,-3.272451639175415,-7.525498867034912,-1.2741708755493164,-7.017579078674316,-5.819214820861816,-3.1171875,-3.7716281414031982,-3.7881085872650146,-5.211187839508057,-3.3115522861480713,-0.8564518690109253,-2.0093538761138916,-2.3687798976898193,-1.9857467412948608,-5.409823894500732,-0.1846037358045578,-10.703161239624023,-0.6280514001846313,-4.091708183288574,-3.518494129180908,-3.8031818866729736,-0.049861859530210495,-3.3525919914245605,-3.165851593017578,-10.01706600189209,-1.6839230060577393,-2.856780767440796,-2.3068442344665527,-6.5340142250061035,-1.463804006576538,-2.267378330230713,-3.1892893314361572,-3.693471908569336,-0.9123533964157104,-5.775394916534424,-3.651638984680176,-0.5415016412734985,-6.931995391845703,-1.3317131996154785,-2.4365334510803223,-0.02782283164560795,-8.348535537719727,-3.8247060775756836,-14.772314071655273,-3.8883824348449707,-3.0607118606567383,-2.8543434143066406,-5.278781890869141,-1.6440763473510742,-4.145020484924316,-3.491271495819092,-0.717750072479248,-3.3241634368896484,-5.380073070526123,-0.5063462257385254,-0.9169122576713562,-9.932243347167969,-3.9521431922912598,-9.589642524719238,-2.20503568649292,-0.8210789561271667,-1.9460680484771729,-1.6320478916168213,-0.9131648540496826,-7.640439510345459,-4.187091827392578,-5.831488132476807,-1.9483110904693604,-10.308152198791504,-0.21140693128108978,-2.4051337242126465,-5.371868133544922,-2.106792449951172,-8.068887710571289,-1.638217806816101,-2.2958486080169678,-2.81595778465271,-0.06216345354914665,-2.528615951538086,-0.014521271921694279,-6.897651672363281,-5.91160774230957,-6.982251167297363,-7.2731475830078125,-2.328253746032715,-3.350137710571289,-0.9306899309158325,-12.349739074707031,-0.23503921926021576,-3.6572134494781494,-1.6666399240493774,-3.076411247253418,-1.4847298860549927,-1.9186911582946777,-3.2676472663879395,-3.348572015762329,-1.0731945037841797,-1.0522472858428955,-1.5771652460098267,-1.7578365802764893,-2.228848934173584,-2.857914924621582,-0.5791002511978149,-0.9980031847953796,-2.104733467102051,-2.0121774673461914,-1.0358853340148926,-10.130950927734375,-0.3186267614364624,-1.2722163200378418,-4.596628189086914,-1.4858781099319458,-2.2922208309173584,-1.8526482582092285,-2.2649574279785156,-5.3437700271606445,-1.467323899269104,-2.0228915214538574,-3.3143186569213867,-6.936673164367676,-7.951779842376709,-4.795997619628906,-5.727677345275879,-9.00643539428711,-0.5929967761039734,-3.512505292892456,-8.523195266723633,-9.354928016662598,-4.906890869140625,-0.07769262790679932,-0.9878278374671936,-7.813033103942871,-3.937044382095337,-6.566921234130859,-2.5381174087524414,-0.3762642443180084,-2.2153704166412354,-0.6092191934585571,-2.6672234535217285,-3.004746675491333,-7.5873003005981445,-0.3904000222682953,-0.17792215943336487,-1.6223610639572144,-4.023347854614258,-0.3183903396129608,-7.422045707702637,-2.7044272422790527,-3.607872724533081,-4.031023979187012,-0.07382593303918839,-5.4143218994140625,-2.2059779167175293,-8.314618110656738,-11.849261283874512,-7.540658950805664,-8.836994171142578,-2.6192963123321533,-8.28978443145752,-5.047154903411865,-6.225893974304199,-0.07805974036455154,-1.789749026298523,-1.3587898015975952,-3.2210307121276855,-0.5696852207183838,-1.19810950756073,-5.541046619415283,-0.012510512955486774,-0.7197617888450623,-5.169851303100586,-5.630217552185059,-1.5394384860992432,-0.7640733122825623,-0.5567817687988281,-1.6767812967300415,-3.7258522510528564,-0.6998720169067383,-5.38449764251709,-1.1657755374908447,-10.699580192565918,-3.8187360763549805,-9.389928817749023,-2.0948901176452637,-8.520549774169922,-4.77166223526001,-0.8577556014060974,-0.1555960476398468,-0.025549715384840965,-10.711252212524414,-1.7098736763000488,-4.517306327819824,-3.452899217605591,-0.4462417960166931,-3.3787577152252197,-3.3969740867614746,-3.3208956718444824,-1.3861267566680908],"stop_reason":"stop","tokens":[49307,0,358,3021,701,40134,0,3580,499,304,279,18537,4999,40,3021,701,13633,323,16070,389,433,4999,13359,499,779,1790,13,15265,42775,1826,25945,72006,55638,95373,2294,0,912,27969,2082,4587,30,374,1070,220,16,477,1193,264,1949,4441,2671,5380,12947,1389,912,27969,2082,374,2631,13,1472,1253,3810,369,264,3658,4441,9633,11,323,422,4183,439,264,13946,11,1070,374,912,4441,11307,3060,13,1472,649,1101,3810,369,264,26745,4441,9633,369,400,19,13,18231,420,8779,4999,40,7055,369,49687,58937,0,3580,499,304,279,19853,4999,13359,369,701,40134,0,19045,15369,304,279,18537,4999,66173,28697,33970,258,420,1391,78,3021,1475,990,11,1633,14948,33970,198,40,1093,279,2144,430,6957,279,13633,433,3250,1431,2349,304,77723,11,323,433,16181,439,832,4459,5502,13,2360,1205,311,1797,279,1396,315,7059,433,18916,817,288,0,39405,990,323,1664,2884,389,1948,220,18,468,750,679,20,4999,40,1093,279,7795,19763,7434,323,42199,1486,11,779,1664,13205,704,627,13359,499,1633,1790,445,301,869,25894,13,1472,527,10032,311,3810,279,19853,5380,40,1097,16661,279,18537,13,358,690,3708,499,264,5975,449,279,73684,2723,627,2181,374,1633,6555,13,82644,627,40,4344,10917,452,337,635,9734,72,11,4946,6236,1348,424,323,14103,3675,32,389,856,3821,1160,11,779,16026,311,1518,1124,389,279,4264,627,52938,14103,3675,1389,499,1948,11843,478,4395,13,1148,1587,14103,3675,3152,30,374,433,701,51743,7987,5380,275,5084,311,757,430,279,13633,374,4382,323,34734,0,26063,0,1054,43,5576,40,965,48507,1600,362,435,16849,11453,71641,13,128001]}],"topk_prompt_logprobs":null,"type":"sample"}


==> Running examples/metrics_live.exs
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Sampled text: : the 2019 first half
As usual, many of our customers are interested in evaluating the state of their business before the end of the financial year.

=== Metrics Snapshot ===
Counters:
  tinkex_requests_success: 4
  tinkex_requests_total: 4

Latency (ms):
  count: 4
  mean: 471.83
  p50:  431.07
  p95:  859.12
  p99:  859.12

==> Running examples/telemetry_live.exs
Starting service client against https://tinker.thinkingmachines.dev/services/tinker-prod ...
Creating sampling client for meta-llama/Llama-3.1-8B ...

14:50:07.530 [info] HTTP post /api/v1/create_sampling_session start (pool=session base=https://tinker.thinkingmachines.dev/services/tinker-prod)

14:50:07.705 [info] HTTP post /api/v1/create_sampling_session ok in 175ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sending sample request ...

14:50:08.900 [info] HTTP post /api/v1/asample start (pool=sampling base=https://tinker.thinkingmachines.dev/services/tinker-prod)

14:50:09.311 [info] HTTP post /api/v1/asample ok in 410ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

14:50:09.321 [info] HTTP post /api/v1/retrieve_future start (pool=futures base=https://tinker.thinkingmachines.dev/services/tinker-prod)

14:50:10.005 [info] HTTP post /api/v1/retrieve_future ok in 683ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sampled sequences: [
  %Tinkex.Types.SampledSequence{
    tokens: [30834, 279, 2380, 15696, 320, 12840, 11, 1268, 11, 3249, 8, 315,
     62137, 13, 2893, 11782, 13, 1398, 25, 330, 6777, 37058, 374, 264, 1749,
     315, 39529, 46071, 279, 2704, 315, 264],
    logprobs: [-3.454059362411499, -0.7563347816467285, -4.0695953369140625,
     -8.167400360107422, -3.2517833709716797, -2.587627410888672,
     -0.046577077358961105, -1.4801626205444336, -0.0736905038356781,
     -0.6298926472663879, -0.5281040668487549, -1.5367215871810913,
     -0.2813340425491333, -1.1758594512939453, -2.5339417457580566,
     -3.5697615146636963, -1.897667646408081, -9.025256156921387,
     -0.38415706157684326, -1.788400650024414, -0.10921048372983932,
     -1.931004080688581e-4, -0.045151710510253906, -1.228928565979004,
     -2.036566734313965, -0.22626833617687225, -3.766385316848755,
     -3.619919776916504, -1.6744308471679688, -2.7987072467803955,
     -0.0685025006532669, -0.220526784658432],
    stop_reason: :length
  }
]

14:50:10.034 [info] HTTP post /api/v1/telemetry start (pool=telemetry base=https://tinker.thinkingmachines.dev/services/tinker-prod)
Flushed telemetry; detach logger and exit.

14:50:10.257 [info] HTTP post /api/v1/telemetry ok in 222ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

==> Running examples/telemetry_reporter_demo.exs
==========================================
Tinkex Telemetry Reporter Demo
==========================================
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Model: meta-llama/Llama-3.1-8B


1. Starting ServiceClient and reporter...
   Reporter started: #PID<0.319.0>

2. Logging generic events...
   Logged: demo.started
   Logged events with different severity levels

3. Logging a non-fatal exception...
   Logged non-fatal exception: Simulated non-fatal error for demonstration

4. Performing live sampling (generates HTTP telemetry)...
   Sampling complete!
   Generated:  It should be a perfect one-liner. Can you do it?
By Tim Troncale, Chief Technic...

5. Demonstrating wait_until_drained...
   Queue drained: true

6. Logging additional events...
   Logged 5 batch events

7. Stopping reporter gracefully...
   Reporter stopped gracefully (SESSION_END event sent)

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


==> Running examples/retry_and_capture.exs
Telemetry reporter started for live session.
[retry start] attempt=0
[retry retry] attempt=0 delay=200ms duration=0ms error=[api_status (500)] synthetic 500 for retry demo
[retry start] attempt=1
[retry retry] attempt=1 delay=400ms duration=0ms error=[api_status (500)] synthetic 500 for retry demo
[retry start] attempt=2
[retry stop] attempt=2 duration=0ms result=ok
Final result: "succeeded on attempt 3"

==> Running examples/model_info_and_unload.exs
[tinkex] base_url=https://tinker.thinkingmachines.dev/services/tinker-prod
[tinkex] base_model=meta-llama/Llama-3.1-8B
[tinkex] created session_id=95ad6e88-a9cc-5996-9a60-0795cbab65ba
[tinkex] poll #1 create_model request_id=95ad6e88-a9cc-5996-9a60-0795cbab65ba:train:0:0
[tinkex] created model_id=95ad6e88-a9cc-5996-9a60-0795cbab65ba:train:0
[tinkex] model_id=95ad6e88-a9cc-5996-9a60-0795cbab65ba:train:0
- model_name: meta-llama/Llama-3.1-8B
- arch: unknown
- tokenizer_id: thinkingmachineslabinc/meta-llama-3-tokenizer
- is_lora: true
- lora_rank: 32
[tinkex] unload_model
[tinkex] unload failed: [api_status (404)] HTTP 404 status=404
[tinkex] error data: %{"detail" => "Not Found"}
````