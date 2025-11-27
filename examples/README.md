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
- Sampling retry tuning is supported in any sampling example via `retry_config` (e.g., pass
  `retry_config: [max_retries: 5, max_connections: 20]` to
  `ServiceClient.create_sampling_client/2` inside `sampling_basic.exs` if you want to see the
  new semaphore-based limiter in action).
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
Sample 1:  I'm a new member here. I'm very excited to find out about a place like this. I have polycystic ovaries and I'm in the process of trying to get pregnant and I'm really looking for some help and support. I have been trying to get pregnant since I was 19, and

==> Running examples/training_loop.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: 'Fine-tuning sample prompt'
Sample after training: false

[step] creating ServiceClient...
[step] creating ServiceClient completed in 760ms
[step] creating TrainingClient (LoRA rank=16)...
[note] this may take 30-120s on first run (model loading)...
[step] creating TrainingClient (LoRA rank=16) completed in 320ms
[step] building model input...
[step] got 6 tokens: [128000, 64816, 2442, 38302, 6205, 10137]
[step] building model input completed in 1.73s
[step] running forward_backward...
[step] forward_backward completed in 2.11s
[metrics] forward_backward: %{"clock_cycle:unique" => 1773468.0, "loss:sum" => 85.29592895507812}
[step] running optim_step...
[step] optim_step completed in 708ms
[metrics] optim_step: (none - optimizer doesn't compute metrics)
[step] saving weights for sampler...
[step] save_weights_for_sampler completed in 2.96s
[result] save_weights: %{"path" => "tinker://50398661-7150-5042-9891-5611cb535340:train:0/sampler_weights/sampler-weights", "sampling_session_id" => nil, "size_bytes" => nil, "type" => "save_weights_for_sampler"}

[done] Training loop finished in 5.79s

==> Running examples/custom_loss_training.exs
================================================================================
Custom Loss Training (Live)
================================================================================

Base URL : https://tinker.thinkingmachines.dev/services/tinker-prod
Base model : meta-llama/Llama-3.1-8B

Creating training client...
Preparing training datum for prompt: Name three planets in the solar system.

Running forward_backward_custom...
Custom loss completed in 4164 ms

Running optim_step...
optim_step succeeded.

=== ForwardBackwardOutput ===
loss_fn_output_type: CrossEntropyLossReturn
metrics: %{"clock_cycle:unique" => 1773473.0, "custom_perplexity" => 201762.703125, "loss:sum" => 12.214847564697266}
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
Compiling 2 files (.ex)
Generated tinkex app
=== Forward Inference Example ===
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: Hello from forward inference!

Creating training client...
Building model input from prompt...
Token count: 6

Running forward pass (inference only, no backward)...

Forward pass completed in 4321ms
Output type: CrossEntropyLossReturn
Metrics: %{"clock_cycle:unique" => 1773476.0, "loss:sum" => 71.73094177246094}
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
  Parallel: 273 μs
  Sequential: 181 μs
  Results match: true

--- 8. Async Regularizers (for I/O-bound operations) ---

Created async regularizer (simulates external API call)
Async regularizer result:
  loss_total: 1.1016
  async_external_validation contribution: 0.0216
  Execution time: 10950 μs

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


16:40:25.431 [info] The function passed as a handler with ID "tinkex-regularizer-8195" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
Attached telemetry handler: tinkex-regularizer-8195

Running pipeline with telemetry (watch for log output):

16:40:25.437 [info] Custom loss starting: regularizers=1 track_grad_norms=true

16:40:25.437 [info] Regularizer l1_sparsity starting

16:40:25.437 [info] Regularizer l1_sparsity value=10.8 contribution=0.108 in 0ms grad_norm=3.1623

16:40:25.437 [info] Custom loss computed in 0ms total=1.188 regularizer_total=0.108 regularizers=1
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

Completed in 7095ms

=== Metrics ===
base_nll: 12.02071
clock_cycle:unique: 1773479.0
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
  • e47047ab-6885-5b39-b648-b9873e4b3f77
  • 9f84518a-b264-5009-bca5-46d764f8d5b0
  • 9f773e1a-5187-5bf9-9f4b-2c293dd55602
  • 20a7d022-5706-5388-8869-ef4d3c703496
  • 50398661-7150-5042-9891-5611cb535340
  • 9f82c0d6-3f6e-5560-b5e5-9a60b151bbd3
  • 8ad60bdf-fd24-5867-8ee4-e731b81caff0
  • 10f2a665-dd9a-54c0-8dd9-d2dcdb4a2c46
  • 127a4ed4-9357-5f7f-ab25-b822f925016e
  • 984a07be-3844-549a-82a3-09ffd3cdc9cf

--- Session Details: e47047ab-6885-5b39-b648-b9873e4b3f77 ---
Training Runs: 0
Samplers: 0

=== Example Complete ===

==> Running examples/checkpoints_management.exs
=== Tinkex Checkpoint Management Example ===

--- All User Checkpoints ---
Found 6 of 90 checkpoints:

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


=== Example Complete ===

==> Running examples/weights_inspection.exs
=== Tinkex Weights Inspection Example ===

--- Training Runs ---
Found 10 training runs:

  9f84518a-b264-5009-bca5-46d764f8d5b0:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  9f773e1a-5187-5bf9-9f4b-2c293dd55602:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  20a7d022-5706-5388-8869-ef4d3c703496:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  50398661-7150-5042-9891-5611cb535340:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  8ad60bdf-fd24-5867-8ee4-e731b81caff0:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  10f2a665-dd9a-54c0-8dd9-d2dcdb4a2c46:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  127a4ed4-9357-5f7f-ab25-b822f925016e:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  984a07be-3844-549a-82a3-09ffd3cdc9cf:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  a5d5031a-72a5-5180-8417-e32c5c0a9598:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  47f7276e-454e-5dde-9188-1c1e3c3536b5:train:1
    Base Model: meta-llama/Llama-3.2-1B
    Is LoRA: true, Rank: 32
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5


--- Training Run Details: 9f84518a-b264-5009-bca5-46d764f8d5b0:train:0 ---
  ID: 9f84518a-b264-5009-bca5-46d764f8d5b0:train:0
  Base Model: meta-llama/Llama-3.1-8B
  Is LoRA: true
  LoRA Rank: 16
  Corrupted: false
  Last Checkpoint: none
  Last Sampler Checkpoint: none
  Last Request: 2025-11-28 02:40:36.691803Z
  Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

--- User Checkpoints ---
Found 2 checkpoint(s):

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


=== Example Complete ===

==> Running examples/checkpoint_download.exs
=== Tinkex Checkpoint Download Example ===

TINKER_CHECKPOINT_PATH not provided; downloading first available checkpoint:
  tinker://50398661-7150-5042-9891-5611cb535340:train:0/sampler_weights/sampler-weights

Downloading checkpoint: tinker://50398661-7150-5042-9891-5611cb535340:train:0/sampler_weights/sampler-weights
Output directory: /tmp/tinkex_checkpoints

Progress: 100.0% (84.1 MB / 84.1 MB)

Download complete!
Extracted to: /tmp/tinkex_checkpoints/50398661-7150-5042-9891-5611cb535340:train:0_sampler_weights_sampler-weights

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
✓ Saved state to: tinker://170beeb9-9fa9-5011-b896-ba0616c7e94d:train:0/weights/async_demo_checkpoint

Restoring training client from checkpoint asynchronously...
✓ Training client restored: #PID<0.278.0>

=== Example Complete ===

==> Running examples/cli_run_text.exs
Compiling 1 file (.ex)
Generated tinkex app
Running CLI with args: run --base-model meta-llama/Llama-3.1-8B --prompt Hello from the CLI runner --max-tokens 64 --temperature 0.7 --num-samples 1 --api-key tml-mIf5gSt5tyewbDuXjwgeTkbdcgCZUpntGFyVBfKvmfGpb2FpJbfJ9tcFyYC5DXjcrAAAA
Starting sampling...
Sample 1:
! 🐹

This is an ongoing series about building a Command Line Interface (CLI) using Node.js. In the previous posts , we built a CLI runner to run commands and display the output.

In this post, we will learn how to:

  - Build a shell for the CLI to display a prompt and
stop_reason=length | avg_logprob=-1.412
Sampling complete (1 sequences)
sampling response: %Tinkex.Types.SampleResponse{
  sequences: [
    %Tinkex.Types.SampledSequence{
      tokens: [0, 11410, 238, 117, 271, 2028, 374, 459, 14529, 4101, 922, 4857,
       264, 7498, 7228, 20620, 320, 65059, 8, 1701, 6146, 2927, 13, 763, 279,
       3766, 8158, 1174, 584, 5918, 264, 40377, 23055, 311, 1629, 11545, 323,
       3113, 279, 2612, 382, 644, 420, 1772, 11, 584, 690, ...],
      logprobs: [-1.7039800882339478, -3.466979742050171, -0.9360814094543457,
       -4.165317535400391, -0.650089681148529, -1.9199599027633667,
       -0.34799057245254517, -3.030365467071533, -5.270044803619385,
       -0.966291606426239, -2.1171317100524902, -2.510927438735962,
       -0.20073369145393372, -5.096033573150635, -0.05905577540397644,
       -0.014663073234260082, -0.13072693347930908, -0.007412430830299854,
       -0.006001902278512716, -2.369553565979004, -0.5246874094009399,
       -0.12046212702989578, -0.7990386486053467, -1.3348363637924194,
       -0.8554633259773254, -0.4986070692539215, -2.6043143272399902,
       -3.31363582611084, -0.0717608779668808, -1.4896317720413208,
       -0.36651191115379333, -0.28990933299064636, -1.2671798467636108,
       -3.112506866455078, -0.7198663949966431, -0.5957552194595337,
       -1.305849313735962, -2.085432529449463, -0.9527989625930786,
       -0.42896461486816406, -2.528024911880493, -0.2813137173652649,
       -0.014210226014256477, -0.034759532660245895, -0.016728835180401802,
       -0.007730448618531227, ...],
      stop_reason: :length
    }
  ],
  prompt_logprobs: nil,
  topk_prompt_logprobs: nil,
  type: "sample"
}

==> Running examples/cli_run_prompt_file.exs
Running CLI with prompt file /tmp/tinkex_prompt_5700.txt
Starting sampling...
Sampling complete (1 sequences)
JSON output written to /tmp/tinkex_output_5764.json
Preview:
{"prompt_logprobs":null,"sequences":[{"logprobs":[-2.400696039199829,-5.000959396362305,-6.997798919677734,-5.103384017944336,-1.474899172782898,-0.22148850560188293,-5.698232650756836,-8.8033447265625,-4.131427764892578,-3.1210622787475586,-11.481575965881348,-4.038726329803467,-6.739284038543701,-2.1484124660491943,-2.2500598430633545,-5.737714767456055,-0.14512623846530914,-6.080523490905762,-9.278803825378418,-5.87931489944458,-4.170082092285156,-4.829282760620117,-8.654241561889648,-4.822141170501709,-4.359817981719971,-4.025493621826172,-8.817239761352539,-2.915034294128418,-10.06367301940918,-1.0239031314849854],"stop_reason":"stop","tokens":[13,4815,35,71,2739,85,25,1304,701,10137,3930,84,304,1933,198,2727,25,816,37,86,33,22,3647,52,54,24,46164,198,19317,128001]}],"topk_prompt_logprobs":null,"type":"sample"}


==> Running examples/metrics_live.exs
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Sampled text:  with Tinkex API v1.3
Quick metrics check from Tinkex with Tinkex API v1.3
Request a set of specific

=== Metrics Snapshot ===
Counters:
  tinkex_requests_success: 4
  tinkex_requests_total: 4

Latency (ms):
  count: 4
  mean: 399.06
  p50:  307.40
  p95:  753.17
  p99:  753.17

==> Running examples/telemetry_live.exs
Starting service client against https://tinker.thinkingmachines.dev/services/tinker-prod ...
Creating sampling client for meta-llama/Llama-3.1-8B ...

16:43:39.285 [info] HTTP post /api/v1/create_sampling_session start (pool=session base=https://tinker.thinkingmachines.dev/services/tinker-prod)

16:43:39.499 [info] HTTP post /api/v1/create_sampling_session ok in 214ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sending sample request ...

16:43:40.379 [info] HTTP post /api/v1/asample start (pool=sampling base=https://tinker.thinkingmachines.dev/services/tinker-prod)

16:43:40.539 [info] HTTP post /api/v1/asample ok in 160ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

16:43:40.543 [info] HTTP post /api/v1/retrieve_future start (pool=futures base=https://tinker.thinkingmachines.dev/services/tinker-prod)

16:43:41.382 [info] HTTP post /api/v1/retrieve_future ok in 838ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sampled sequences: [
  %Tinkex.Types.SampledSequence{
    tokens: [2360, 11, 2216, 11, 1120, 832, 11914, 627, 47641, 555, 4074, 389,
     220, 966, 5936, 11, 220, 679, 18, 482, 220, 806, 25, 2946, 198, 6777,
     37058, 374, 279, 8198, 315, 26984],
    logprobs: [-4.704059600830078, -1.6005475521087646, -1.479292631149292,
     -0.7334266304969788, -0.8752605319023132, -0.10427486151456833,
     -0.28443869948387146, -0.7477242946624756, -9.216988563537598,
     -0.016099924221634865, -4.885961055755615, -0.0038587411399930716,
     -0.9665814638137817, -3.3782808780670166, -2.4663166999816895,
     -0.5304547548294067, -3.576278118089249e-7, -0.056088097393512726,
     -1.9098819494247437, -0.0014297273010015488, -4.410734163684538e-6,
     -2.457045793533325, -7.152555099310121e-7, -4.118589401245117,
     -0.027281949296593666, -1.7136030197143555, -2.3278864682652056e-4,
     -0.06805312633514404, -0.3185139000415802, -1.7561581134796143,
     -0.03197753056883812, -1.6106730699539185],
    stop_reason: :length
  }
]

16:43:41.411 [info] HTTP post /api/v1/telemetry start (pool=telemetry base=https://tinker.thinkingmachines.dev/services/tinker-prod)
Flushed telemetry; detach logger and exit.

16:43:41.656 [info] HTTP post /api/v1/telemetry ok in 245ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

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
   Generated:  Why not?
I've been teaching my kids about this, but they are still not able to ...

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
[tinkex] created session_id=be224b9d-8c94-58da-827b-c05a8d85a5a7
[tinkex] poll #1 create_model request_id=be224b9d-8c94-58da-827b-c05a8d85a5a7:train:0:0
[tinkex] created model_id=be224b9d-8c94-58da-827b-c05a8d85a5a7:train:0
[tinkex] model_id=be224b9d-8c94-58da-827b-c05a8d85a5a7:train:0
- model_name: meta-llama/Llama-3.1-8B
- arch: unknown
- tokenizer_id: baseten/Meta-Llama-3-tokenizer
- is_lora: true
- lora_rank: 32
[tinkex] unload_model
[tinkex] unload failed: [api_status (404)] HTTP 404 status=404
[tinkex] error data: %{"detail" => "Not Found"}
````
