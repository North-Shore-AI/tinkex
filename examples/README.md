# Tinkex Examples

This directory contains examples demonstrating the core functionality of the Tinkex SDK. Each example is a self-contained script that illustrates specific features and workflows, from basic sampling operations to advanced checkpoint management and training loops.

## Overview

The examples are organized by functionality and complexity, ranging from simple single-operation demonstrations to complete end-to-end workflows. All examples require a valid Tinker API key and can be configured through environment variables to customize their behavior.

## Example Index

- `sampling_basic.exs` – basic sampling client creation and prompt decoding
- `training_loop.exs` – forward/backward pass, optim step, save weights, and optional sampling
- `custom_loss_training.exs` – live custom loss training that sends gradients to the backend via `forward_backward_custom/4`
- `forward_inference.exs` – forward-only pass returning logprobs for custom loss computation/evaluation with Nx/EXLA
- `structured_regularizers.exs` – composable regularizer pipeline demo with mock data (runs offline)
- `structured_regularizers_live.exs` – custom loss with inline regularizer terms via live Tinker API
- `live_capabilities_and_logprobs.exs` – live health/capabilities check plus prompt logprobs (requires API key)
- `model_info_and_unload.exs` – fetch active model metadata (tokenizer id, arch) and unload the session (requires API key)
- `sessions_management.exs` – REST session listing and detail queries
- `checkpoints_management.exs` – user checkpoint listing with metadata inspection
- `checkpoint_download.exs` – streaming checkpoint download (O(1) memory) with progress callbacks and extraction
- `weights_inspection.exs` – sampler/weights metadata inspection for LoRA+training run validation
- `async_client_creation.exs` – parallel sampling client creation via Task-based flows
- `cli_run_text.exs` – programmatic `tinkex run` invocation with inline prompts
- `cli_run_prompt_file.exs` – CLI sampling with prompt files and JSON output capture
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
Compiling 7 files (.ex)
Generated tinkex app
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Received 1 sequence(s):
Sample 1:  A new brand of personalised stationery that is all about adding joy to your day. We create unique personalised stationery that you can use for yourself or gift to your loved ones.
Tinkex is founded by a mother of 3 who is a stationery geek.
We create unique designer stationery that is not readily

==> Running examples/training_loop.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: 'Fine-tuning sample prompt'
Sample after training: false

[step] creating ServiceClient...
[step] creating ServiceClient completed in 606ms
[step] creating TrainingClient (LoRA rank=16)...
[note] this may take 30-120s on first run (model loading)...
[step] creating TrainingClient (LoRA rank=16) completed in 317ms
[step] building model input...
[step] got 6 tokens: [128000, 64816, 2442, 38302, 6205, 10137]
[step] building model input completed in 1.87s
[step] running forward_backward...
[step] forward_backward completed in 9.8s
[metrics] forward_backward: %{"clock_cycle:unique" => 668517.0, "loss:sum" => 85.29592895507812}
[step] running optim_step...
[step] optim_step completed in 873ms
[metrics] optim_step: (none - optimizer doesn't compute metrics)
[step] saving weights for sampler...
[step] save_weights_for_sampler completed in 4.03s
[result] save_weights: %{"path" => "tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights", "sampling_session_id" => nil, "size_bytes" => nil, "type" => "save_weights_for_sampler"}

[done] Training loop finished in 14.71s

==> Running examples/custom_loss_training.exs
================================================================================
Custom Loss Training (Live)
================================================================================

Base URL : https://tinker.thinkingmachines.dev/services/tinker-prod
Base model : meta-llama/Llama-3.1-8B

Creating training client...
Preparing training datum for prompt: Name three planets in the solar system.

Running forward_backward_custom...
Custom loss completed in 20292 ms

Running optim_step...
optim_step succeeded.

=== ForwardBackwardOutput ===
loss_fn_output_type: CrossEntropyLossReturn
metrics: %{"clock_cycle:unique" => 668522.0, "custom_perplexity" => 201762.703125, "loss:sum" => 12.214847564697266}
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

Forward pass completed in 10357ms
Output type: CrossEntropyLossReturn
Metrics: %{"clock_cycle:unique" => 3556618.0, "loss:sum" => 71.73094177246094}
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

Created L1 sparsity regularizer: weight=0.01
Created entropy regularizer: weight=0.001
Created L2 regularizer: weight=0.005

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

Composed loss with 3 regularizers:
  loss_total: 1.2583
  base_loss: 1.08
  regularizer_total: 0.1783

Per-regularizer breakdown:
  entropy:
    value: -3.1972
    weight: 0.001
    contribution: -0.0032
  l1_sparsity:
    value: 10.8
    weight: 0.01
    contribution: 0.108
  l2_weight_decay:
    value: 14.7
    weight: 0.005
    contribution: 0.0735

--- 6. With Gradient Norm Tracking ---

Gradient norms for training dynamics monitoring:
  base_loss grad_norm: 0.3162
  total_grad_norm: 0.3822

Per-regularizer gradient norms:
  entropy:
    grad_norm: 0.6867
    grad_norm_weighted: 6.87e-4
  l1_sparsity:
    grad_norm: 3.1623
    grad_norm_weighted: 0.031623
  l2_weight_decay:
    grad_norm: 7.6681
    grad_norm_weighted: 0.038341

--- 7. Sequential vs Parallel Execution ---

Execution time comparison:
  Parallel: 471 μs
  Sequential: 242 μs
  Results match: true

--- 8. Async Regularizers (for I/O-bound operations) ---

Created async regularizer (simulates external API call)
Async regularizer result:
  loss_total: 1.1016
  async_external_validation contribution: 0.0216
  Execution time: 11387 μs

--- 9. Direct Executor Usage ---

Single regularizer execution via Executor:
  name: l1_sparsity
  value: 10.8
  contribution: 0.108
  grad_norm: 3.1623

All regularizers via Executor.execute_all:
  l1_sparsity: value=10.8, grad_norm=3.1623
  entropy: value=-3.1972, grad_norm=0.6867
  l2_weight_decay: value=14.7, grad_norm=7.6681

--- 10. Direct GradientTracker Usage ---

Gradient norm for sum(x):
  grad_norm: 3.1623
  (Expected: sqrt(n) = sqrt(10) ≈ 3.162)

Gradient norm for sum(x^2):
  grad_norm: 7.6681
  (Gradient is 2x, so norm depends on input values)

--- 11. Telemetry Integration ---


10:32:48.777 [info] The function passed as a handler with ID "tinkex-regularizer-5186" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
Attached telemetry handler: tinkex-regularizer-5186

Running pipeline with telemetry (watch for log output):

10:32:48.784 [info] Custom loss starting: regularizers=1 track_grad_norms=true

10:32:48.784 [info] Regularizer l1_sparsity starting

10:32:48.784 [info] Regularizer l1_sparsity value=10.8 contribution=0.108 in 0ms grad_norm=3.1623

10:32:48.784 [info] Custom loss computed in 0ms total=1.188 regularizer_total=0.108 regularizers=1
Detached telemetry handler

--- 12. JSON Serialization ---

CustomLossOutput as JSON:
{
  "loss_total": 1.2583030109405517,
  "regularizers": {
    "entropy": {
      "value": -3.1971569061279297,
      "custom": {},
      "weight": 0.001,
      "contribution": -0.0031971569061279297,
      "grad_norm": 0.6867480278015137,
      "grad_norm_weighted": 6.867480278015136e-4
    },
    "l1_sparsity": {
      "value": 10.80000114440918,
      "custom": {},
      "weight": 0.01,
      "contribution": 0.1080000114440918,
      "grad_norm": 3.1622776985168457,
      "grad_norm_weighted":...

(Output truncated for display)

RegularizerOutput as JSON:
{
  "name": "l1_sparsity",
  "value": 10.80000114440918,
  "custom": {},
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

Completed in 6125ms

=== Metrics ===
base_nll: 12.02071
clock_cycle:unique: 668526.0
custom_perplexity: 166160.59375
entropy: -5.0e-6
l1: 1.322278
loss:sum: 13.343032

================================================================================
Success! Custom loss with regularizer terms computed via live Tinker API.
================================================================================

==> Running examples/sessions_management.exs
=== Tinkex Session Management Example ===

Starting ServiceClient...
Creating RestClient...

--- Listing Sessions ---
Found 10 sessions:
  • 1b237267-9f76-5a03-9ea8-96578ddbe935
  • bef237d2-e7dc-54ae-8055-55b143264cbd
  • 046c901d-5e46-5982-a80d-32fcc2acfb9f
  • e461bab9-a627-5c7b-889b-26b744d46df3
  • 39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4
  • ae3e031a-e2a4-512a-8d85-708e93dd4f1b
  • 0ba9f266-961a-5c66-8bed-a5103ed577bd
  • f9ee4b55-c2b5-59da-9c4a-e15b50d13845
  • f66b0737-c942-5f75-831a-b86dbd5c4d7e
  • c86fee95-7c04-5163-a4ca-9f9002fd49c7

--- Session Details: 1b237267-9f76-5a03-9ea8-96578ddbe935 ---
Training Runs: 0
Samplers: 0

=== Example Complete ===

==> Running examples/checkpoints_management.exs
=== Tinkex Checkpoint Management Example ===

--- All User Checkpoints ---
Found 20 of 92 checkpoints:

  sampler_weights/sampler-weights
    Path: tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-12-03T20:32:09.677474Z

  weights/async_demo_checkpoint
    Path: tinker://170beeb9-9fa9-5011-b896-ba0616c7e94d:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-11-28T02:43:17.958810Z

  sampler_weights/sampler-weights
    Path: tinker://50398661-7150-5042-9891-5611cb535340:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-28T02:40:09.047757Z

  sampler_weights/sampler-weights
    Path: tinker://a5d5031a-72a5-5180-8417-e32c5c0a9598:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-28T02:32:20.546936Z

  weights/async_demo_checkpoint
    Path: tinker://47f7276e-454e-5dde-9188-1c1e3c3536b5:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 153.0 MB
    Public: false
    Created: 2025-11-28T02:31:18.060463Z

  sampler_weights/async_demo_weights
    Path: tinker://a7517405-527c-571e-9fe2-c94e6b3cf548:train:0/sampler_weights/async_demo_weights
    Type: sampler
    Size: 51.0 MB
    Public: false
    Created: 2025-11-28T02:30:25.465448Z

  sampler_weights/async_demo_weights
    Path: tinker://73c466d3-b063-56a2-86d0-d035a1392c23:train:0/sampler_weights/async_demo_weights
    Type: sampler
    Size: 51.0 MB
    Public: false
    Created: 2025-11-28T02:29:56.731159Z

  sampler_weights/sampler-weights
    Path: tinker://53f0586d-3f98-58e5-b04e-297ea717378e:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27T18:58:37.961274Z

  sampler_weights/sampler-weights
    Path: tinker://f4521144-ef58-53ec-950c-29260c9b1a41:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27T18:44:47.285732Z

  sampler_weights/sampler-weights
    Path: tinker://1ec257a9-28bf-559c-aa73-e54a09cce5bd:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27T18:37:23.205082Z

  sampler_weights/sampler-weights
    Path: tinker://046c91d9-d9f4-5dd6-ac42-0135bbde947e:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27T18:15:50.316094Z

  sampler_weights/sampler-weights
    Path: tinker://fdf7af94-bcce-5bf7-847b-a159e8bfb025:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27T18:11:28.567500Z

  sampler_weights/sampler-weights
    Path: tinker://8eba0a5a-0dcf-57f3-9d0d-65ec6ef22a1f:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27T17:53:03.197669Z

  sampler_weights/checkpoint_1764230891.2048833.pt
    Path: tinker://fa0ecefc-83b2-5e26-a2a9-aee483b913ba:train:0/sampler_weights/checkpoint_1764230891.2048833.pt
    Type: sampler
    Size: 5.77 GB
    Public: false
    Created: 2025-11-27T08:09:13.441453Z

  sampler_weights/checkpoint_1764230289.3815918.pt
    Path: tinker://bc33563e-6730-5cbe-9a25-43e11dbe5095:train:0/sampler_weights/checkpoint_1764230289.3815918.pt
    Type: sampler
    Size: 5.77 GB
    Public: false
    Created: 2025-11-27T07:59:06.047243Z

  sampler_weights/checkpoint_1764229717.8670213.pt
    Path: tinker://bfc7c5e5-0b90-55a1-8c97-fc8bdac649c9:train:0/sampler_weights/checkpoint_1764229717.8670213.pt
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-27T07:48:41.184106Z

  sampler_weights/checkpoint_1764229539.9387324.pt
    Path: tinker://9922175e-533d-52e3-a433-5e0fa645462c:train:0/sampler_weights/checkpoint_1764229539.9387324.pt
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-11-27T07:45:42.982073Z

  weights/demo-checkpoint-1764228622
    Path: tinker://8c4cfd17-df85-5634-badf-e12068d2efc8:train:0/weights/demo-checkpoint-1764228622
    Type: training
    Size: 126.3 MB
    Public: false
    Created: 2025-11-27T07:30:37.300885Z

  sampler_weights/checkpoint_1764215477.2502818.pt
    Path: tinker://daba87c6-4e86-5797-81d5-efe038b44524:train:0/sampler_weights/checkpoint_1764215477.2502818.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-27T03:51:18.921217Z

  sampler_weights/checkpoint_1764127354.6624672.pt
    Path: tinker://d0fde479-adea-5e5a-9974-1196f01fbb82:train:0/sampler_weights/checkpoint_1764127354.6624672.pt
    Type: sampler
    Size: 84.1 MB
    Public: false
    Created: 2025-11-26T03:22:37.215881Z


=== Example Complete ===

==> Running examples/weights_inspection.exs
=== Tinkex Weights Inspection Example ===

--- Training Runs ---
Found 10 training runs:

  bef237d2-e7dc-54ae-8055-55b143264cbd:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  046c901d-5e46-5982-a80d-32fcc2acfb9f:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  e461bab9-a627-5c7b-889b-26b744d46df3:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  0ba9f266-961a-5c66-8bed-a5103ed577bd:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  f9ee4b55-c2b5-59da-9c4a-e15b50d13845:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  598b870d-dc81-5be9-9581-d4c3bffb44be:train:0
    Base Model: meta-llama/Llama-3.2-1B
    Is LoRA: true, Rank: 32
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  cd663bca-7892-55cb-be4e-c7b646d850b2:train:0
    Base Model: meta-llama/Llama-3.2-1B
    Is LoRA: true, Rank: 32
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  a847bd03-868b-5c68-b726-5a8bd072625a:train:0
    Base Model: meta-llama/Llama-3.2-1B
    Is LoRA: true, Rank: 32
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  7c78675f-2d36-5aca-a0ec-bef786762a91:train:0
    Base Model: meta-llama/Llama-3.2-1B
    Is LoRA: true, Rank: 32
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5


--- Training Run Details: bef237d2-e7dc-54ae-8055-55b143264cbd:train:0 ---
  ID: bef237d2-e7dc-54ae-8055-55b143264cbd:train:0
  Base Model: meta-llama/Llama-3.1-8B
  Is LoRA: true
  LoRA Rank: 16
  Corrupted: false
  Last Checkpoint: none
  Last Sampler Checkpoint: none
  Last Request: 2025-12-03 20:32:55.109826Z
  Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

--- User Checkpoints ---
Found 10 checkpoint(s):

  tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 84.1 MB
    Time: 2025-12-03T20:32:09.677474Z

  tinker://170beeb9-9fa9-5011-b896-ba0616c7e94d:train:0/weights/async_demo_checkpoint
    Type: training
    ID: weights/async_demo_checkpoint
    Size: 152.98 MB
    Time: 2025-11-28T02:43:17.958810Z

  tinker://50398661-7150-5042-9891-5611cb535340:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 84.1 MB
    Time: 2025-11-28T02:40:09.047757Z

  tinker://a5d5031a-72a5-5180-8417-e32c5c0a9598:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 84.1 MB
    Time: 2025-11-28T02:32:20.546936Z

  tinker://47f7276e-454e-5dde-9188-1c1e3c3536b5:train:0/weights/async_demo_checkpoint
    Type: training
    ID: weights/async_demo_checkpoint
    Size: 152.98 MB
    Time: 2025-11-28T02:31:18.060463Z

  tinker://a7517405-527c-571e-9fe2-c94e6b3cf548:train:0/sampler_weights/async_demo_weights
    Type: sampler
    ID: sampler_weights/async_demo_weights
    Size: 50.98 MB
    Time: 2025-11-28T02:30:25.465448Z

  tinker://73c466d3-b063-56a2-86d0-d035a1392c23:train:0/sampler_weights/async_demo_weights
    Type: sampler
    ID: sampler_weights/async_demo_weights
    Size: 50.98 MB
    Time: 2025-11-28T02:29:56.731159Z

  tinker://53f0586d-3f98-58e5-b04e-297ea717378e:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 84.1 MB
    Time: 2025-11-27T18:58:37.961274Z

  tinker://f4521144-ef58-53ec-950c-29260c9b1a41:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 84.1 MB
    Time: 2025-11-27T18:44:47.285732Z

  tinker://1ec257a9-28bf-559c-aa73-e54a09cce5bd:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 84.1 MB
    Time: 2025-11-27T18:37:23.205082Z


=== Example Complete ===

==> Running examples/checkpoint_download.exs
=== Tinkex Checkpoint Download Example ===

TINKER_CHECKPOINT_PATH not provided; downloading first available checkpoint:
  tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights

Downloading checkpoint: tinker://39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0/sampler_weights/sampler-weights
Output directory: /tmp/tinkex_checkpoints

Progress: 100.0% (84.1 MB / 84.1 MB)

Download complete!
Extracted to: /tmp/tinkex_checkpoints/39b4a59d-e0e4-553d-87d1-2e8ae9db0bd4:train:0_sampler_weights_sampler-weights

Extracted files (3):
  • adapter_config.json (736 B)
  • adapter_model.safetensors (84.1 MB)
  • checkpoint_complete (0 B)

=== Example Complete ===

==> Running examples/async_client_creation.exs
=== Tinkex Async Client Creation Example ===

Creating sampling client asynchronously...
Task created, awaiting result...
✓ Sampling client created: #PID<0.252.0>

Creating LoRA training client asynchronously...
Task created, awaiting result...
✓ LoRA training client created: #PID<0.260.0>

Saving training state to create checkpoint...
✓ Saved state to: tinker://9677c040-d833-5325-8a9d-4c3a1f816328:train:0/weights/async_demo_checkpoint

Restoring training client from checkpoint asynchronously...
✓ Training client restored: #PID<0.278.0>

=== Example Complete ===

==> Running examples/cli_run_text.exs
Running CLI with args: run --base-model meta-llama/Llama-3.1-8B --prompt Hello from the CLI runner --max-tokens 64 --temperature 0.7 --num-samples 1 --api-key tml-mIf5gSt5tyewbDuXjwgeTkbdcgCZUpntGFyVBfKvmfGpb2FpJbfJ9tcFyYC5DXjcrAAAA
Starting sampling...
Sample 1:
.
I'm not sure if this is possible, but I'd like to be able to run tests from the CLI runner that use the test runner, which in turn uses the command runner to execute the test code.
So, for example, I have a test runner file that looks like this:
var testRunner = require
stop_reason=length | avg_logprob=-1.306
Sampling complete (1 sequences)
sampling response: %Tinkex.Types.SampleResponse{
  sequences: [
    %Tinkex.Types.SampledSequence{
      tokens: [627, 40, 2846, 539, 2771, 422, 420, 374, 3284, 11, 719, 358,
       4265, 1093, 311, 387, 3025, 311, 1629, 7177, 505, 279, 40377, 23055, 430,
       1005, 279, 1296, 23055, 11, 902, 304, 2543, 5829, 279, 3290, 23055, 311,
       9203, 279, 1296, 2082, 627, 4516, 11, 369, 3187, ...],
      logprobs: [-3.5795583724975586, -1.0052404403686523, -1.2745513916015625,
       -2.8693130016326904, -0.2649388611316681, -0.8700623512268066,
       -0.559992790222168, -0.04600697010755539, -4.418613433837891,
       -0.4960397779941559, -0.03471290320158005, -0.28530794382095337,
       -1.37711763381958, -0.09592393785715103, -0.015257902443408966,
       -1.4179904460906982, -0.0015180503251031041, -2.4399164249189198e-4,
       -0.7839916944503784, -3.9295105934143066, -1.264305830001831,
       -0.1773315817117691, -1.5910406112670898, -1.316138744354248,
       -1.7571544647216797, -2.5250649452209473, -0.5046882033348083,
       -3.402918577194214, -0.47159984707832336, -2.6524651050567627,
       -3.103660821914673, -1.989617109298706, -0.01729818433523178,
       -0.7375035881996155, -0.14178435504436493, -3.6171159744262695,
       -3.4245076179504395, -2.65036678314209, -1.733647346496582,
       -0.42849284410476685, -1.1295380592346191, -2.542349100112915,
       -0.5898256897926331, -3.905834436416626, -0.7327507734298706,
       -1.018278956413269, ...],
      stop_reason: :length
    }
  ],
  prompt_logprobs: nil,
  topk_prompt_logprobs: nil,
  type: "sample"
}

==> Running examples/cli_run_prompt_file.exs
Running CLI with prompt file /tmp/tinkex_prompt_5826.txt
Starting sampling...
Sampling complete (1 sequences)
JSON output written to /tmp/tinkex_output_5890.json
Preview:
{"prompt_logprobs":null,"sequences":[{"logprobs":[-2.4103214740753174,-1.481612205505371,-1.6993517875671387,-1.6085186004638672,-5.111445426940918,-1.97594153881073,-1.1717655658721924,-0.4643413722515106,-1.3711751699447632,-0.006968954112380743,-1.1871790885925293,-0.04053192213177681,-2.121251106262207,-0.004537524189800024,-1.3446797132492065,-6.138952255249023,-5.222756385803223,-4.653529167175293,-5.804534912109375,-0.8416662216186523,-9.227217674255371,-1.2605887651443481,-1.5938613414764404,-2.1836817264556885,-5.224343299865723,-1.3763225078582764,-0.11617501080036163,-2.9787542819976807,-0.6054537296295166,-5.050826072692871,-0.5107788443565369,-2.1634936332702637,-2.498811960220337,-3.2069690227508545,-2.2543468475341797,-2.579184055328369,-3.743730306625366,-8.058501243591309,-6.793439865112305,-5.710214138031006,-8.676680564880371,-6.139692783355713,-6.30639123916626,-2.062299966812134,-3.8482143878936768,-4.542710781097412,-0.5203852653503418,-3.8335604667663574,-1.6408588886260986,-1.568137288093567,-0.012080245651304722,-1.2023649215698242,-1.4825797080993652,-1.482069969177246,-1.3127667903900146,-0.17095088958740234,-1.4786778688430786,-1.6125874519348145,-0.006843580398708582,-5.21590518951416,-0.05076216533780098,-0.22017771005630493,-5.9606404304504395,-5.549184322357178,-4.7872209548950195,-4.855972766876221,-0.9366350173950195,-0.12604430317878723,-9.595711708068848,-0.7755651473999023,-2.820842742919922,-3.7621843814849854,-5.157322883605957,-2.6577000617980957,-5.21419095993042,-1.5303518772125244,-0.007139763794839382,-1.9781513214111328,-1.3684971332550049,-2.268671751022339,-1.777215600013733,-7.819088935852051,-11.438087463378906,-2.451627254486084,-8.741952896118164,-6.708137512207031,-5.673834800720215,-3.203212261199951,-8.400153160095215,-6.0843095779418945,-16.10692596435547,-3.2539682388305664,-5.298253059387207,-8.841060638427734,-3.1346662044525146,-7.1228485107421875,-2.2069647312164307,-6.067137241363525,-2.42806077003479,-5.857672691345215,-2.4751973152160645,-6.354546546936035,-4.133467674255371,-11.019477844238281,-2.4210262298583984,-0.893137514591217,-3.2921323776245117,-9.257552146911621,-6.81947135925293,-6.079846382141113,-11.751153945922852,-1.789302110671997,-8.758362770080566,-4.224250793457031,-7.154967784881592,-2.3976199626922607,-11.934314727783203,-2.5352611541748047,-2.5792174339294434,-3.3471624851226807,-8.435900688171387,-3.911782741546631,-4.933475494384766,-6.7821455001831055,-2.338259696960449,-1.733213186264038,-0.16573885083198547,-0.8874191641807556,-3.5605456829071045,-0.1679030954837799,-0.15616737306118011,-0.39686769247055054,-0.07913373410701752,-0.4499230682849884,-6.871246150694788e-4,-0.007271964568644762,-3.6272482872009277,-0.07902028411626816,-0.07613808661699295,-0.0017864234978333116,-0.052572790533304214,-0.00722569040954113,-0.02836875058710575,-0.06212211400270462,-3.5470392322167754e-4,-0.002725697821006179,-7.942138671875,-10.012084007263184,-0.07492903620004654,-0.002745907986536622,-0.06627770513296127,-0.10175099223852158,-0.012989195063710213,-0.013234037905931473,-0.07967877388000488,-0.0505918487906456,-5.078217945992947e-4,-0.009351381100714207,-5.694699287414551,-3.7189815044403076,-0.028416143730282784,-0.07267549633979797,-0.0015376898227259517,-0.017790740355849266,-0.011137695983052254,-0.0010033579310402274,-0.0037643304094672203,-5.360727787017822,-0.5493968725204468,-0.1271948218345642,-2.130580425262451,-8.717945098876953,-0.640282392501831,-0.1252182573080063,-0.020092058926820755,-0.6820160746574402,-0.5253106951713562,-10.228569030761719,-6.81758451461792,-8.117961883544922,-2.3921868801116943,-8.689125061035156,-1.7730913162231445,-4.698187828063965,-0.24678246676921844,-4.603797435760498,-2.967658758163452,-5.875194072723389,-18.165441513061523,-4.863584041595459,-0.2899436056613922,-2.8398327827453613,-5.573713779449463,-3.1849451065063477,-11.773632049560547,-0.30232974886894226,-5.63413143157959,-1.2279820442199707,-14.847956657409668,-10.91910171508789,-11.21194076538086,-2.8944525718688965,-0.43136003613471985,-0.6919549107551575,-0.7771584391593933,-1.5401930809020996,-5.155832290649414,-4.753726959228516,-0.96075439453125,-1.223474144935608,-10.294321060180664,-9.029932975769043,-12.407955169677734,-5.040881156921387,-1.532426357269287,-9.444000244140625,-3.103414297103882,-8.488123893737793,-4.926351547241211,-6.718753337860107,-1.0221798419952393,-7.329015731811523,-0.4833906292915344,-7.192741394042969,-4.679009437561035,-4.814059257507324,-13.409563064575195,-7.051697254180908,-9.483461380004883,-5.190164566040039,-6.417781829833984,-9.602149963378906,-9.241943359375,-3.491941452026367,-4.302358150482178,-1.8735932111740112,-4.267017364501953,-3.7181270122528076,-1.7670300006866455,-1.4795916080474854,-2.524857521057129,-9.832592964172363,-0.18930113315582275,-7.060855865478516,-3.470280647277832,-4.026463031768799,-4.834967613220215,-2.6490068435668945,-3.39202880859375,-1.1640807390213013,-7.865609645843506,-0.6302926540374756,-7.037282943725586,-2.540952205657959,-1.1739842891693115,-0.1342141032218933,-1.9657386541366577,-13.7061185836792,-3.214365243911743,-2.070497989654541,-2.3705854415893555,-2.711764335632324,-13.07050609588623,-10.616802215576172,-4.135945796966553,-4.414124965667725,-4.404797554016113,-0.9277579188346863,-9.539392471313477,-4.300154209136963,-1.4321762323379517,-8.916997909545898,-1.6228301525115967,-3.8632383346557617,-8.053675651550293,-5.6849212646484375,-0.23074105381965637,-7.190181255340576,-8.572669982910156,-4.091102600097656,-0.02828427404165268,-5.719094276428223,-4.888680458068848,-2.3962152004241943,-10.532453536987305,-6.399784088134766,-3.3022067546844482,-6.654189109802246,-9.710124969482422,-2.229261636734009,-5.250110626220703,-0.980569064617157,-0.5991645455360413,-8.894183158874512,-6.204658031463623,-0.6972963213920593,-14.117812156677246,-9.730276107788086,-4.162985801696777,-7.3795485496521,-8.472846984863281,-7.300466537475586,-3.631579637527466,-2.0620036125183105,-12.545825004577637,-7.127178192138672,-1.880378007888794,-7.33294677734375,-4.351083755493164,-0.9646018743515015,-4.605457305908203,-3.1085894107818604,-4.044012546539307,-9.295428276062012,-3.486915111541748,-4.781571865081787,-5.992690086364746,-1.0766656398773193,-7.147191047668457,-2.5994911193847656,-5.492531776428223,-7.9876275062561035,-5.285679817199707,-3.2594082355499268,-2.0916457176208496,-8.100872039794922,-11.840993881225586,-2.974590539932251,-7.839136123657227,-4.262036323547363,-5.481948375701904,-10.553565979003906,-7.0019850730896,-6.973628044128418,-2.470111846923828,-9.823935508728027,-0.1414492279291153,-11.930364608764648,-3.5212631225585938,-6.222449779510498,-9.678894996643066,-7.970310211181641,-8.884906768798828,-8.208680152893066,-6.209246635437012,-2.3077828884124756,-2.941310405731201,-8.231354713439941,-3.543962001800537,-9.320425033569336,-2.950599431991577,-4.594964027404785,-3.985895872116089,-3.410745859146118,-2.042266607284546,-5.721744537353516,-6.170266151428223,-1.3732715845108032,-4.510341644287109,-4.921364784240723,-1.452978253364563,-3.3367912769317627,-3.4576730728149414,-4.878668308258057,-1.75033438205719,-6.508336544036865,-1.5457738637924194,-5.313633441925049,-3.0053248405456543,-5.352481842041016,-0.6981807351112366,-5.106980800628662,-5.385060787200928,-8.490257263183594,-10.190001487731934,-0.247206911444664,-3.7554209232330322,-2.4797203540802,-1.8158812522888184,-2.5369791984558105,-2.602865219116211,-2.7751574516296387,-3.1225266456604004,-5.000789642333984,-1.214324712753296,-4.346864700317383,-2.109657049179077,-5.430792331695557,-6.761059284210205,-6.898703575134277,-4.7746968269348145,-2.015768527984619,-5.372612953186035,-1.9969673156738281,-2.989100456237793,-1.8669538497924805,-6.728403091430664,-7.530834197998047,-0.936662495136261,-3.904484748840332,-1.7678725719451904,-4.4931488037109375,-1.889866590499878,-6.541816234588623,-6.394891738891602,-5.447674751281738,-2.8917791843414307,-5.015178680419922,-4.118044853210449,-7.045520782470703,-0.13903780281543732,-5.570929527282715,-1.4497491121292114,-6.02664041519165,-5.345512866973877,-3.697784423828125,-5.528990745544434,-1.119093418121338,-3.6796624660491943,-5.868624687194824,-3.658134937286377,-0.2156352996826172,-6.301939964294434,-4.858808517456055,-6.971897125244141,-2.8257932662963867,-4.060304641723633,-4.664558410644531,-1.4773588180541992,-3.924105405807495,-2.857407569885254,-1.909933090209961,-3.4156386852264404,-6.915688991546631,-2.9088029861450195,-3.8407182693481445,-1.5526909828186035,-0.0837012305855751,-0.07925884425640106,-0.8097116351127625,-5.971117973327637,-2.222133159637451,-3.4983556270599365,-7.906166076660156,-3.9793972969055176,-1.1109726428985596,-1.9890332221984863,-2.1169726848602295,-5.793446063995361,-5.1206207275390625,-8.680839538574219,-0.031018543988466263,-1.6338731050491333,-7.992051124572754,-3.1342926025390625,-2.637775182723999,-4.140921115875244,-2.619992733001709,-3.3330860137939453,-6.303351879119873,-2.9176695346832275,-4.456803798675537,-1.5668621063232422,-5.857741355895996,-1.6906102895736694,-5.212464809417725,-3.2073841094970703,-12.405179023742676,-11.078841209411621,-3.3388383388519287,-7.54919958114624,-11.077221870422363,-7.113646507263184,-6.839696884155273,-0.5240275859832764,-8.117510795593262,-3.773449659347534,-3.436506509780884,-3.421865940093994,-0.7046695947647095,-2.365330696105957,-0.4494428038597107,-1.8536851406097412,-5.814051628112793,-0.15075509250164032,-7.569639205932617,-9.599751472473145,-3.3304550647735596,-1.9099969863891602,-0.003810290014371276,-4.44084358215332,-0.14838072657585144,-0.015774348750710487,-9.892560005187988,-6.56809663772583,-0.7999904155731201,-8.854347229003906,-1.5444003343582153,-6.854297637939453,-2.026348352432251,-3.3447279930114746,-6.2145795822143555,-7.157571792602539,-4.418673515319824,-7.0218353271484375,-4.038987159729004,-1.8179885149002075,-0.22167687118053436,-1.7934563159942627,-7.91077184677124,-5.223263740539551,-10.383594512939453,-0.4000903367996216,-4.405243396759033,-9.333325386047363,-8.555054664611816,-4.383699417114258,-6.802282333374023,-9.053688049316406,-5.417450904846191,-2.7287087440490723,-4.119086742401123,-2.404736280441284,-0.134462371468544,-7.951897621154785,-7.543621063232422,-5.40523624420166,-10.465496063232422,-6.980744361877441,-3.8108181953430176,-7.191021919250488,-1.1321568489074707,-2.5136146545410156,-5.294621467590332,-4.425957679748535,-1.7979824542999268,-7.669944763183594,-3.084674596786499,-3.0852231979370117,-0.1785353124141693,-6.065652370452881,-12.09787654876709,-4.717751502990723,-1.6871678829193115,-4.653213977813721,-2.914987564086914,-2.222034215927124,-6.606910705566406,-1.9629156589508057,-9.310382843017578,-2.0288844108581543,-2.9871809482574463,-0.8337690234184265,-0.06881903111934662,-0.11161081492900848,-7.116535186767578,-3.6248185634613037,-2.492919445037842,-1.9082257747650146,-3.1884868144989014],"stop_reason":"stop","tokens":[13,358,1097,264,11164,11,323,420,1772,574,56168,555,611,84,14,754,347,370,1037,68,4749,13,358,690,2815,304,220,17,4207,505,1457,382,40,690,387,1203,994,328,45456,66313,40124,334,81663,17160,10245,36868,3507,93350,57318,71361,55759,3651,40330,7354,2006,83069,2794,16511,6979,10009,37636,45613,1389,5782,393,25434,44272,15215,39129,19324,16932,2006,16139,1389,7354,63427,50736,34733,63151,57277,2,35390,5211,271,13617,5829,220,19,14774,19930,69338,22071,311,46113,220,1419,3626,1555,279,4272,11,7999,832,51658,311,1855,832,45082,100441,100699,126450,101305,107915,101179,108797,96298,18939,382,2,29438,16067,1432,334,15147,1035,16,13,510,42144,9725,2,50378,340,17,13,510,61032,40227,9725,2,47928,40227,340,18,13,510,35891,65776,9725,2,62344,2427,19253,14164,340,19,13,510,15777,21829,811,9725,2,25615,12,25742,811,12795,2,35907,271,1255,347,370,1037,71853,374,1981,439,7060,264,3560,43012,4029,439,6866,382,4516,102503,3018,306,13,1442,358,8122,36626,433,311,37002,72537,11299,304,3021,449,433,13,3639,1436,387,810,50765,551,49582,382,2,38943,1038,12834,1455,5865,527,22486,311,3566,477,4641,83430,482,2613,3834,1288,12771,20160,2613,16692,13,2030,1148,422,499,617,15860,315,9624,13422,499,2351,1701,11,323,842,709,14324,264,2763,315,892,20505,304,279,7074,13,11930,15987,382,2181,1253,387,17057,389,264,27946,5569,369,320,97525,8,6222,13650,1778,439,4443,26743,13,30013,10925,617,8066,75581,389,1778,13650,439,6696,7512,11,34266,39230,277,311,612,442,8322,11,34507,3674,3772,430,1436,387,9959,304,3938,13042,323,20207,25907,13,3297,1101,5101,1418,21646,22917,13,34863,32855,13,10323,10397,45933,12309,16736,30098,449,1560,83775,23460,5315,14,63879,61912,83663,5922,13122,389,11,9455,502,11983,323,3674,2065,2671,11,3318,12135,449,502,3674,3772,323,1023,6732,13,1398,69597,358,2846,5128,2771,1070,6866,2317,7191,1109,904,832,1732,1436,11000,1440,477,48248,13,1442,358,1518,1403,3062,18845,11,499,3358,617,264,9257,1317,9860,3938,13,1666,264,3682,3157,320,269,8996,374,4560,311,4667,449,1778,3674,29130,28271,8,374,1455,8173,304,2038,5552,4819,323,3674,7640,11,584,617,311,1781,2225,5627,520,279,1890,892,13,18156,433,1253,4097,810,1109,264,3254,3217,1389,4536,956,433,34707,13,358,4510,279,1455,28289,3245,574,279,5133,449,1884,358,27724,16250,323,8661,84257,358,42777,922,1980,2181,1053,1101,387,6555,311,617,520,3325,510,16497,9725,1277,1129,268,34466,2726,705,1095,7636,4815,2,12027,271,9,13688,18939,551,65,14369,512,9,13688,505,832,2055,2,74977,12,5263,16067,55160,5520,9669,2997,912,1862,369,2653,36106,1389,62019,6924,4669,15161,32705,596,8106,6559,269,5471,279,1217,505,34111,21142,382,2,65814,362,482,5649,22166,5560,271,2,65814,426,482,14969,612,35680,1038,128001]}],"topk_prompt_logprobs":null,"type":"sample"}


==> Running examples/metrics_live.exs
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Sampled text:
The Tinkex dashboard shows a quick, at-a-glance view of your projects. The dashboard allows you to easily compare projects to see where your time

=== Metrics Snapshot ===
Counters:
  tinkex_requests_success: 4
  tinkex_requests_total: 4

Latency (ms):
  count: 4
  mean: 502.44
  p50:  465.24
  p95:  826.13
  p99:  826.13

==> Running examples/telemetry_live.exs
Starting service client against https://tinker.thinkingmachines.dev/services/tinker-prod ...
Creating sampling client for meta-llama/Llama-3.1-8B ...

10:36:07.331 [info] HTTP post /api/v1/create_sampling_session start (pool=session base=https://tinker.thinkingmachines.dev/services/tinker-prod)

10:36:07.611 [info] HTTP post /api/v1/create_sampling_session ok in 279ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sending sample request ...

10:36:08.688 [info] HTTP post /api/v1/asample start (pool=sampling base=https://tinker.thinkingmachines.dev/services/tinker-prod)

10:36:09.166 [info] HTTP post /api/v1/asample ok in 477ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

10:36:09.185 [info] HTTP post /api/v1/retrieve_future start (pool=futures base=https://tinker.thinkingmachines.dev/services/tinker-prod)

10:36:09.994 [info] HTTP post /api/v1/retrieve_future ok in 808ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sampled sequences: [
  %Tinkex.Types.SampledSequence{
    tokens: [3639, 374, 433, 30, 8595, 656, 584, 1005, 433, 30, 3639, 527, 279,
     7720, 1980, 6777, 37058, 374, 279, 1920, 315, 26984, 323, 42118, 828, 311,
     8895, 26793, 1139, 279, 5178, 11],
    logprobs: [-1.4004876613616943, -0.21809379756450653, -0.5183565616607666,
     -0.6882222890853882, -1.6689610481262207, -1.3359495401382446,
     -0.507761538028717, -1.121880054473877, -0.017047420144081116,
     -0.21992535889148712, -0.6591378450393677, -0.9404007196426392,
     -0.35884523391723633, -0.8169716000556946, -4.404777526855469,
     -0.4814941883087158, -2.7092601521871984e-4, -0.023718087002635002,
     -0.40297552943229675, -1.0642532110214233, -0.005674799904227257,
     -0.5010918378829956, -0.418936550617218, -0.707565426826477,
     -0.07639224827289581, -1.5775229930877686, -1.2423986196517944,
     -0.3514748513698578, -0.48231393098831177, -0.23728083074092865,
     -0.06967131048440933, -1.6731479167938232],
    stop_reason: :length
  }
]

10:36:10.026 [info] HTTP post /api/v1/telemetry start (pool=telemetry base=https://tinker.thinkingmachines.dev/services/tinker-prod)

10:36:10.249 [info] HTTP post /api/v1/telemetry ok in 222ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Flushed telemetry; detach logger and exit.

==> Running examples/telemetry_reporter_demo.exs
==========================================
Tinkex Telemetry Reporter Demo
==========================================
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Model: meta-llama/Llama-3.1-8B


1. Starting ServiceClient and reporter...
   Reporter started: #PID<0.250.0>

2. Logging generic events...
   Logged: demo.started
   Logged events with different severity levels

3. Logging a non-fatal exception...
   Logged non-fatal exception: Simulated non-fatal error for demonstration

4. Performing live sampling (generates HTTP telemetry)...
   Sampling complete!
   Generated:  Can you say anything about the technology, but also about industry and scope?
T...

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
[tinkex] created session_id=a9a84697-074e-5a76-a4f2-f6a6f3a24364
[tinkex] poll #1 create_model request_id=a9a84697-074e-5a76-a4f2-f6a6f3a24364:train:0:0
[tinkex] created model_id=a9a84697-074e-5a76-a4f2-f6a6f3a24364:train:0
[tinkex] model_id=a9a84697-074e-5a76-a4f2-f6a6f3a24364:train:0
- model_name: meta-llama/Llama-3.1-8B
- arch: unknown
- tokenizer_id: baseten/Meta-Llama-3-tokenizer
- is_lora: true
- lora_rank: 32
[tinkex] unload_model
[tinkex] unload failed: [api_status (404)] HTTP 404 status=404
[tinkex] error data: %{"detail" => "Not Found"}
````
