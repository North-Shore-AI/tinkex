# Tinkex Examples

This directory contains examples demonstrating the core functionality of the Tinkex SDK. Each example is a self-contained script that illustrates specific features and workflows, from basic sampling operations to advanced checkpoint management and training loops.

## Overview

The examples are organized by functionality and complexity, ranging from simple single-operation demonstrations to complete end-to-end workflows. Most examples require a valid Tinker API key and can be configured through environment variables to customize their behavior; offline-only scripts are noted below.

## Example Index

- `sampling_basic.exs` – basic sampling client creation and prompt decoding
- `kimi_k2_sampling_live.exs` – live sampling with MoonshotAI Kimi K2 using `tiktoken_ex` tokenization (skips if unavailable)
- `training_loop.exs` – forward/backward pass, optim step, save weights, and optional sampling
- `custom_loss_training.exs` – live custom loss training that sends gradients to the backend via `forward_backward_custom/4`
- `forward_inference.exs` – forward-only pass returning logprobs for custom loss computation/evaluation with Nx/EXLA
- `adam_and_chunking_live.exs` – byte-based training chunking preview plus `optim_step/2` with `weight_decay`/`grad_clip_norm`
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
- `queue_reasons_and_sampling_throttling.exs` – attaches queue-state telemetry, logs server-supplied reasons, simulates backoff to exercise layered sampling dispatch throttling, and runs a live sample
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

### kimi_k2_sampling_live.exs

This example demonstrates end-to-end sampling with MoonshotAI’s **Kimi K2**
models using `tiktoken_ex` tokenization. It checks live server capabilities for
`moonshotai/Kimi-K2-Thinking` (skips if the model is not advertised), prints a
tokenization round-trip for the prompt, then runs a live sampling request and
decodes the returned tokens.

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to `moonshotai/Kimi-K2-Thinking`)
- `TINKER_PROMPT` (optional, defaults to "Say hi")
- `TINKER_MAX_TOKENS` (optional, defaults to 32)
- `TINKER_TEMPERATURE` (optional, defaults to 0.7)
- `TINKER_NUM_SAMPLES` (optional, defaults to 1)
- `TINKER_SAMPLE_TIMEOUT` (optional, defaults to 60000ms)

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

### adam_and_chunking_live.exs

End-to-end live training that previews the byte-based chunking plan (1024 item / 5MB caps), runs `forward_backward/3` on a dataset that defaults to two chunks, and applies an optimizer step with `AdamParams` populated with `weight_decay` and `grad_clip_norm`.

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_CHUNK_COUNT` (optional, defaults to 1025 to show multi-chunk preview)
- `TINKER_RUN_COUNT` (optional, defaults to 128 to keep the live request small; raise carefully if you see HTTP/2 window/backpressure errors)

### queue_reasons_and_sampling_throttling.exs

Attaches telemetry to queue-state changes, demonstrates server-preferred reason logging, simulates a backoff window to exercise the new sampling dispatch throttling (layered semaphores + byte penalty), and finishes with a live sampling request while printing estimated prompt bytes.

**Configuration Variables:**
- `TINKER_API_KEY` (required)
- `TINKER_BASE_URL` (optional)
- `TINKER_BASE_MODEL` (optional, defaults to Llama-3.1-8B)
- `TINKER_PROMPT` (optional, defaults to a short demo string)

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
Sample 1:  I am your host, Laura! I am a mother to a 7 year old and a 2 year old. My kids are my world, however it is a world that I am always trying to improve upon. I am always looking for new ways to make our home and our lives at home function better, be

==> Running examples/training_loop.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: 'Fine-tuning sample prompt'
Sample after training: false

[step] creating ServiceClient...
[step] creating ServiceClient completed in 351ms
[step] creating TrainingClient (LoRA rank=16)...
[note] this may take 30-120s on first run (model loading)...
[step] creating TrainingClient (LoRA rank=16) completed in 208ms
[step] building model input...
[step] got 6 tokens: [128000, 64816, 2442, 38302, 6205, 10137]
[step] building model input completed in 1.31s
[step] running forward_backward...
[step] forward_backward completed in 3.42s
[metrics] forward_backward: %{"clock_cycle:unique" => 9437441.0, "loss:sum" => 85.29592895507812}
[step] running optim_step...
[step] optim_step completed in 863ms
[metrics] optim_step: (none - optimizer doesn't compute metrics)
[step] saving weights for sampler...
[step] save_weights_for_sampler completed in 4.15s
[result] save_weights: %{"path" => "tinker://95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0/sampler_weights/sampler-weights", "sampling_session_id" => nil, "size_bytes" => nil, "type" => "save_weights_for_sampler"}

[done] Training loop finished in 8.45s

==> Running examples/custom_loss_training.exs
================================================================================
Custom Loss Training (Live)
================================================================================

Base URL : https://tinker.thinkingmachines.dev/services/tinker-prod
Base model : meta-llama/Llama-3.1-8B

Creating training client...
Preparing training datum for prompt: Name three planets in the solar system.

Running forward_backward_custom...
Custom loss completed in 15025 ms

Running optim_step...
optim_step succeeded.

=== ForwardBackwardOutput ===
loss_fn_output_type: CrossEntropyLossReturn
metrics: %{"clock_cycle:unique" => 7175773.0, "custom_perplexity" => 201762.703125, "loss:sum" => 12.214847564697266}
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

Forward pass completed in 14582ms
Output type: CrossEntropyLossReturn
Metrics: %{"clock_cycle:unique" => 9233322.0, "loss:sum" => 71.73094177246094}
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
  Parallel: 2734 μs
  Sequential: 3889 μs
  Results match: true

--- 8. Async Regularizers (for I/O-bound operations) ---

Created async regularizer (simulates external API call)
Async regularizer result:
  loss_total: 1.1016
  async_external_validation contribution: 0.0216
  Execution time: 10604 μs

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


20:50:25.145 [info] The function passed as a handler with ID "tinkex-regularizer-4" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
Attached telemetry handler: tinkex-regularizer-4

Running pipeline with telemetry (watch for log output):

20:50:25.153 [info] Custom loss starting: regularizers=1 track_grad_norms=true

20:50:25.154 [info] Regularizer l1_sparsity starting

20:50:25.154 [info] Regularizer l1_sparsity value=10.8 contribution=0.108 in 0ms grad_norm=3.1623

20:50:25.154 [info] Custom loss computed in 1ms total=1.188 regularizer_total=0.108 regularizers=1
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

Completed in 14014ms

=== Metrics ===
base_nll: 12.02071
clock_cycle:unique: 244358.0
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
  • 679a9ad9-13f5-5760-b4cb-1acac0f888e5
  • 685c17ea-05fc-59b6-9ac2-f965a7c9d4db
  • 28a720a8-fbf6-5236-9ed3-c9c5707bb2d9
  • 89f2052b-266d-5242-a602-814cbf06184d
  • 95706e7e-827d-5d7c-b8b4-5e1ee86733d8
  • f0ea0c02-9de3-5082-a551-0082936b8f12
  • d48059bf-dcb7-5927-bd47-43b4bc96f603
  • c5b6fe33-f1c5-5a70-aed6-1e8a3ff39415
  • c53a8dcd-babb-5464-ae8f-d1f1c6bcd1c6
  • b5a2d510-7ea8-5449-b1f4-c76747230375

--- Session Details: 679a9ad9-13f5-5760-b4cb-1acac0f888e5 ---
Training Runs: 0
Samplers: 0

=== Example Complete ===

==> Running examples/checkpoints_management.exs
=== Tinkex Checkpoint Management Example ===

--- All User Checkpoints ---
Found 20 of 102 checkpoints:

  sampler_weights/sampler-weights
    Path: tinker://95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-08 06:49:46.096855Z

  weights/async_demo_checkpoint
    Path: tinker://0927bbd5-890d-5599-9856-69cce21db777:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-05 00:49:42.481039Z

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


--- All User Checkpoints (paginated) ---
Fetched 50 (102 total)
  sampler_weights/sampler-weights
    Path: tinker://95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-08 06:49:46.096855Z

  weights/async_demo_checkpoint
    Path: tinker://0927bbd5-890d-5599-9856-69cce21db777:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-05 00:49:42.481039Z

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

Fetched 50 (102 total)
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

Fetched 2 (102 total)
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

  685c17ea-05fc-59b6-9ac2-f965a7c9d4db:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  28a720a8-fbf6-5236-9ed3-c9c5707bb2d9:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  89f2052b-266d-5242-a602-814cbf06184d:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  d48059bf-dcb7-5927-bd47-43b4bc96f603:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  c5b6fe33-f1c5-5a70-aed6-1e8a3ff39415:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  69ac3c27-0a43-578e-838b-bf318b0675c6:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  6c903270-3693-53a4-b148-2d94095c7506:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  535250a4-85f0-56ad-a7fc-e9ac562d9495:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  e08f03cf-bbe2-5e4e-8b4f-a116b9e870d3:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5


--- Training Run Details: 685c17ea-05fc-59b6-9ac2-f965a7c9d4db:train:0 ---
  ID: 685c17ea-05fc-59b6-9ac2-f965a7c9d4db:train:0
  Base Model: meta-llama/Llama-3.1-8B
  Is LoRA: true
  LoRA Rank: 16
  Corrupted: false
  Last Checkpoint: none
  Last Sampler Checkpoint: none
  Last Request: 2025-12-08 06:50:41.104684Z
  Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

--- User Checkpoints ---
Found 10 checkpoint(s):

  tinker://95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 168.14 MB
    Time: 2025-12-08 06:49:46.096855Z

  tinker://0927bbd5-890d-5599-9856-69cce21db777:train:0/weights/async_demo_checkpoint
    Type: training
    ID: weights/async_demo_checkpoint
    Size: 305.8 MB
    Time: 2025-12-05 00:49:42.481039Z

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


=== Example Complete ===

==> Running examples/checkpoint_download.exs
=== Tinkex Checkpoint Download Example ===

TINKER_CHECKPOINT_PATH not provided; downloading first available checkpoint:
  tinker://95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0/sampler_weights/sampler-weights

Downloading checkpoint: tinker://95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0/sampler_weights/sampler-weights
Output directory: /tmp/tinkex_checkpoints

Progress: 100.0% (168.1 MB / 168.1 MB)

Download complete!
Extracted to: /tmp/tinkex_checkpoints/95706e7e-827d-5d7c-b8b4-5e1ee86733d8:train:0_sampler_weights_sampler-weights

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
✓ LoRA training client created: #PID<0.328.0>

Saving training state to create checkpoint...
✓ Saved state to: tinker://a01f0a63-89aa-560b-8dbf-82a8fffbaa7b:train:0/weights/async_demo_checkpoint

Restoring training client from checkpoint asynchronously...
✓ Training client restored: #PID<0.340.0>

=== Example Complete ===

==> Running examples/cli_run_text.exs
Running CLI with args: run --base-model meta-llama/Llama-3.1-8B --prompt Hello from the CLI runner --max-tokens 64 --temperature 0.7 --num-samples 1 --api-key tml-mIf5gSt5tyewbDuXjwgeTkbdcgCZUpntGFyVBfKvmfGpb2FpJbfJ9tcFyYC5DXjcrAAAA
Starting sampling...
Sample 1:
! 👋
CLI runner lets you run CI/CD jobs in parallel using your existing CI infrastructure.
It is open-source, and is written in Go, but it can be used with any CI runner.
Why should I use it?
It is currently the only tool that can be used with any CI runner, you
stop_reason=length | avg_logprob=-1.781
Sampling complete (1 sequences)
sampling response: %Tinkex.Types.SampleResponse{
  sequences: [
    %Tinkex.Types.SampledSequence{
      tokens: [0, 62904, 233, 198, 65059, 23055, 15714, 499, 1629, 21351, 14,
       6620, 7032, 304, 15638, 1701, 701, 6484, 21351, 14054, 627, 2181, 374,
       1825, 31874, 11, 323, 374, 5439, 304, 6122, 11, 719, 433, 649, 387, 1511,
       449, 904, 21351, 23055, 627, 10445, 1288, 358, 1005, 433, ...],
      logprobs: [-1.704558253288269, -3.450963020324707, -0.0016221948899328709,
       -0.6610124111175537, -3.9991812705993652, -0.43093565106391907,
       -5.22663688659668, -0.009449634701013565, -0.14332005381584167,
       -4.746139049530029, -0.7311502695083618, -4.23184028477408e-5,
       -1.3739851713180542, -1.942132592201233, -5.01203727722168,
       -2.2423200607299805, -1.856949806213379, -0.8863710165023804,
       -0.6584771275520325, -3.53775691986084, -1.2324718236923218,
       -1.567047357559204, -1.8811769485473633, -3.3902244567871094,
       -1.3855783939361572, -0.9778281450271606, -1.4297370910644531,
       -3.148252248764038, -3.4274587631225586, -0.03877663612365723,
       -1.0353710651397705, -2.493137836456299, -4.517518043518066,
       -1.4003181457519531, -1.2896896600723267, -0.7605559825897217,
       -0.1885213851928711, -0.5928910970687866, -0.021373534575104713,
       -0.6150001287460327, -4.024051666259766, -1.0493953227996826,
       -3.736922264099121, -2.8585686683654785, -0.8943158388137817,
       -0.05982040613889694, ...],
      stop_reason: :length
    }
  ],
  prompt_logprobs: nil,
  topk_prompt_logprobs: nil,
  type: "sample"
}

==> Running examples/cli_run_prompt_file.exs
Running CLI with prompt file /tmp/tinkex_prompt_322.txt
Starting sampling...
Sampling complete (1 sequences)
JSON output written to /tmp/tinkex_output_386.json
Preview:
{"prompt_logprobs":null,"sequences":[{"logprobs":[-2.400696039199829,-7.625959396362305,-0.2517755925655365,-4.67180871963501,-1.206678867340088,-2.188699722290039,-9.300558090209961,-0.9959198236465454,-0.055651936680078506,-3.607316493988037,-1.5985894203186035,-0.3201850652694702,-9.268465042114258,-2.150397777557373,-6.5981597900390625,-0.18008999526500702,-4.307760238647461,-8.482027053833008,-1.0406467914581299,-3.7304487228393555,-1.9353032112121582,-3.4535837173461914,-3.952777147293091,-4.30113410949707,-2.041212320327759,-3.001446008682251,-2.405333995819092,-2.47849178314209,-1.3032582998275757,-1.288406252861023,-3.981355667114258,-0.15822695195674896,-1.1745420694351196,-1.1587333679199219,-3.380772590637207,-4.576085567474365,-1.415477991104126,-0.0040738931857049465,-3.8093810081481934,-0.9867255091667175,-0.2280021458864212,-0.8518000245094299,-4.0296630859375,-2.2701029777526855,-0.3303205370903015,-3.1738669872283936,-4.907995700836182,-1.4022254943847656,-2.942186117172241,-2.527484893798828,-7.016465187072754,-0.19478364288806915,-2.133114814758301,-2.324347972869873,-3.5836877822875977,-0.8195840120315552,-2.1537530422210693,-3.7657783031463623,-0.8613870143890381,-0.9212002754211426,-0.40482959151268005,-1.8157744407653809,-1.0453544855117798,-1.2729696035385132,-1.9722286462783813,-0.18839353322982788,-1.2747716903686523,-4.402801513671875,-7.908890724182129,-3.7228646278381348,-1.2830487489700317,-4.750363826751709,-1.589170217514038,-4.978814125061035,-3.6082913875579834,-3.3754396438598633,-3.5252938270568848,-1.5657964944839478,-0.7129288911819458,-1.572585940361023,-4.040330410003662,-6.992875099182129,-3.8381903171539307,-2.240241289138794,-3.7185702323913574,-2.3026561737060547,-0.8298953175544739,-1.664353847503662,-1.4389604330062866,-0.09990230947732925,-0.13927605748176575,-0.28862765431404114,-1.294569730758667,-2.1870484352111816,-6.238943576812744,-9.783080101013184,-0.7784769535064697,-5.629996299743652,-0.5992649793624878,-3.8539371490478516,-0.24612393975257874,-4.885526180267334,-7.016366004943848,-8.871540069580078,-8.362029075622559,-2.2187886238098145,-0.9239722490310669,-3.398615837097168,-0.8867708444595337,-4.727583408355713,-11.540332794189453,-1.401877760887146,-2.9992504119873047,-3.3054113388061523,-1.6435246467590332,-1.104436993598938,-3.3433399200439453,-1.5847920179367065,-1.3798545598983765,-8.051169395446777,-0.3977756202220917,-3.74413800239563,-3.2545814514160156,-1.5580618381500244,-4.1460490226745605,-1.5045924186706543,-9.046341896057129,-1.268045425415039,-1.4552284479141235,-6.20389986038208,-0.6640440225601196,-1.498968482017517,-0.8671838641166687,-1.1729459762573242,-1.7825428247451782,-0.6374697685241699,-3.1052587032318115,-11.976297378540039,-3.5506725311279297,-1.2006776332855225,-6.373994827270508,-1.415395975112915,-7.7139573097229,-4.698295593261719,-3.476203441619873,-8.235069274902344,-1.8129546642303467,-3.5614333152770996,-2.3523080348968506,-3.4656519889831543,-1.9546592235565186,-6.197614669799805,-7.972033500671387,-4.483292102813721,-0.6652193069458008,-1.68873929977417,-0.32680657505989075,-0.9038156867027283,-0.5062711238861084,-0.5332136154174805,-1.170531153678894,-2.376903533935547,-0.7649188041687012,-7.059678077697754,-1.5282914638519287,-1.5321338176727295,-3.2791192531585693,-4.446094036102295,-0.6669924855232239,-0.3378583490848541,-2.0493593215942383,-4.447623252868652,-2.099663019180298,-6.068744659423828,-1.0732653141021729,-2.994983196258545,-1.3863379955291748,-4.557352066040039,-0.9613248109817505,-4.482196807861328,-2.345778465270996,-1.3696173429489136,-0.38216403126716614,-10.148058891296387,-0.40529176592826843,-1.1245571374893188,-5.276291847229004,-3.994873523712158,-0.7470945119857788,-1.0075466632843018,-2.2467241287231445,-2.8380303382873535,-1.6085946559906006,-1.189160704612732,-2.2571630477905273,-0.8351939916610718,-0.5800741910934448,-0.7851913571357727,-0.06011691316962242,-0.22706080973148346,-1.775824785232544,-2.436000347137451,-6.266515731811523,-1.0859229564666748,-0.42175906896591187,-4.879487037658691,-7.909746170043945,-0.838945746421814,-2.564143657684326,-6.1898393630981445,-1.737146258354187,-3.888838768005371,-4.008388519287109,-3.497586727142334,-1.4815406799316406,-4.5677714347839355,-1.4539841413497925,-2.278151750564575],"stop_reason":"stop","tokens":[13,50958,311,990,704,1148,40929,2133,389,323,1268,311,35692,627,59150,1093,2555,30418,279,1052,1887,477,701,12035,627,2675,2643,617,264,17188,315,1063,3169,627,22170,312,34788,17157,323,1518,422,430,21522,2574,704,369,1457,13,1442,430,5084,311,387,264,31528,3072,1243,1629,264,17188,8737,323,1518,1148,4131,709,13,5112,2555,690,387,11054,627,2170,279,1023,1772,1071,11,433,40929,34490,10535,13,578,1193,3245,430,4131,311,4059,374,430,433,596,17439,555,3060,264,35311,477,1023,3445,5552,1063,1268,311,40831,13,763,1938,596,315,28960,455,11,264,35311,1053,43146,92455,11894,3626,323,30342,323,13334,1124,311,3041,279,21455,430,279,6500,574,2103,659,4401,13,4343,701,1670,1853,315,7634,1405,40831,1053,14614,10477,701,1144,2374,843,11,1144,13466,11,1144,10920,3626,11,369,3187,627,2181,1587,5222,1093,2555,39270,13,4418,80215,22743,11,4869,13,4718,828,1288,387,30547,311,279,3241,422,433,40929,539,264,17188,13,1442,433,374,264,17188,11,433,1253,37088,701,828,13971,9778,13,358,2643,4284,36201,323,13598,369,30020,13,128001]}],"topk_prompt_logprobs":null,"type":"sample"}


==> Running examples/metrics_live.exs
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Sampled text: . I will be out of the office next week. In the meantime, here is your weekly metrics report.
Visits: 3,231 (+1.

=== Metrics Snapshot ===
Counters:
  tinkex_requests_success: 4
  tinkex_requests_total: 4

Latency (ms):
  count: 4
  mean: 518.58
  p50:  473.20
  p95:  848.43
  p99:  848.43

==> Running examples/telemetry_live.exs
Starting service client against https://tinker.thinkingmachines.dev/services/tinker-prod ...
Creating sampling client for meta-llama/Llama-3.1-8B ...

20:51:49.471 [info] HTTP post /api/v1/create_sampling_session start (pool=session base=https://tinker.thinkingmachines.dev/services/tinker-prod)

20:51:49.714 [info] HTTP post /api/v1/create_sampling_session ok in 242ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sending sample request ...

20:51:50.605 [info] HTTP post /api/v1/asample start (pool=sampling base=https://tinker.thinkingmachines.dev/services/tinker-prod)

20:51:51.184 [info] HTTP post /api/v1/asample ok in 578ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

20:51:51.187 [info] HTTP post /api/v1/retrieve_future start (pool=futures base=https://tinker.thinkingmachines.dev/services/tinker-prod)

20:51:51.887 [info] HTTP post /api/v1/retrieve_future ok in 699ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sampled sequences: [
  %Tinkex.Types.SampledSequence{
    tokens: [3011, 753, 433, 13, 12334, 810, 13, 2684, 374, 264, 2763, 315,
     2038, 2736, 2561, 389, 279, 7757, 922, 62137, 13, 5810, 374, 264, 2723,
     311, 264, 3997, 902, 15100, 62137, 304],
    logprobs: [-5.030082702636719, -0.5867346525192261, -1.3159239292144775,
     -0.3008876442909241, -3.918519973754883, -0.7226240038871765,
     -0.428449422121048, -6.237043380737305, -1.5220794677734375,
     -2.5206899642944336, -0.6170402765274048, -0.5679656863212585,
     -0.7924634218215942, -5.785129547119141, -1.1444653272628784,
     -0.7880459427833557, -0.4194923937320709, -0.9669249653816223,
     -0.605694055557251, -0.18910646438598633, -0.9658671617507935,
     -4.5308942794799805, -1.3459312915802002, -0.5771136283874512,
     -2.1780076026916504, -0.06951285153627396, -0.7946727871894836,
     -4.146535396575928, -3.22021484375, -1.836809754371643, -0.709998369216919,
     -0.3945309519767761],
    stop_reason: :length
  }
]

20:51:51.912 [info] HTTP post /api/v1/telemetry start (pool=telemetry base=https://tinker.thinkingmachines.dev/services/tinker-prod)
Flushed telemetry; detach logger and exit.

20:51:53.238 [info] HTTP post /api/v1/telemetry ok in 1325ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

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
   Generated:  Use only one word (or phrase) to describe the concept. I’ll explain my interpre...

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

==> Running examples/live_capabilities_and_logprobs.exs
== Server capabilities ==
Supported models (18 available):
  - deepseek-ai/DeepSeek-V3.1
  - deepseek-ai/DeepSeek-V3.1-Base
  - meta-llama/Llama-3.1-70B
  - meta-llama/Llama-3.1-8B
  - meta-llama/Llama-3.1-8B-Instruct
  - meta-llama/Llama-3.2-1B
  - meta-llama/Llama-3.2-3B
  - meta-llama/Llama-3.3-70B-Instruct
  - Qwen/Qwen3-235B-A22B-Instruct-2507
  - Qwen/Qwen3-30B-A3B
  - Qwen/Qwen3-30B-A3B-Base
  - Qwen/Qwen3-30B-A3B-Instruct-2507
  - Qwen/Qwen3-32B
  - Qwen/Qwen3-4B-Instruct-2507
  - Qwen/Qwen3-8B
  - Qwen/Qwen3-8B-Base
  - openai/gpt-oss-120b
  - openai/gpt-oss-20b

Model names only: deepseek-ai/DeepSeek-V3.1, deepseek-ai/DeepSeek-V3.1-Base, meta-llama/Llama-3.1-70B, meta-llama/Llama-3.1-8B, meta-llama/Llama-3.1-8B-Instruct, meta-llama/Llama-3.2-1B, meta-llama/Llama-3.2-3B, meta-llama/Llama-3.3-70B-Instruct, Qwen/Qwen3-235B-A22B-Instruct-2507, Qwen/Qwen3-30B-A3B, Qwen/Qwen3-30B-A3B-Base, Qwen/Qwen3-30B-A3B-Instruct-2507, Qwen/Qwen3-32B, Qwen/Qwen3-4B-Instruct-2507, Qwen/Qwen3-8B, Qwen/Qwen3-8B-Base, openai/gpt-oss-120b, openai/gpt-oss-20b

== Health check ==
Health: ok

== Compute prompt logprobs ==
Prompt: Hello from Tinkex!
Logprobs: [nil, -7.96064567565918, -4.212800025939941, -5.870484828948975, -6.74709939956665, -11.390317916870117, -2.6839911937713623]

==> Running examples/file_upload_multipart.exs
============================================================
Tinkex Multipart Encoding Demo
============================================================

[1] Input File:
    Path: examples/uploads/sample_upload.bin
    Size: 6 bytes

[2] File Transformation:
    Input:  %{"file" => "examples/uploads/sample_upload.bin"}
    Output: %{"file" => {"sample_upload.bin", <<6 bytes>>}}

[3] Form Field Serialization:
    Input:  %{metadata: %{version: "0.2.1", source: "tinkex"}, note: "Multipart demo from Tinkex"}
    Output: %{"metadata[source]" => "tinkex", "metadata[version]" => "0.2.1", "note" => "Multipart demo from Tinkex"}

[4] Multipart Encoding:
    Content-Type: multipart/form-data; boundary=694a07403eea839ac9aa7c27a29a6d75
    Body size: 516 bytes

[5] Multipart Body Preview:
    --694a07403eea839ac9aa7c27a29a6d75
    Content-Disposition: form-data; name="metadata[source]"

    tinkex
    --694a07403eea839ac9aa7c27a29a6d75
    Content-Disposition: form-data; name="metadata[version]"

    0.2.1
    --694a07403eea839ac9aa7c27a29a6d75
    Content-Disposition: form-data; name="note"

    Multipart demo from Tinkex
    --694a07403eea839ac9aa7c27a29a6d75
    Content-Disposition: form-data; name="file"; filename="sample_upload.bin"
    Content-Type: application/octet-stream

    hello

    --694a07403eea839ac9aa7c27a29a6d75--

    ... (16 more bytes)

[6] API Integration:
    API key present but TINKER_UPLOAD_ENDPOINT not set
    Note: The Tinker API has no file upload endpoints currently.
    Set TINKER_UPLOAD_ENDPOINT to test against a custom endpoint.

============================================================
Demo complete. Multipart encoding is working correctly.
============================================================

==> Running examples/adam_and_chunking_live.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Preview count: 1025 (max chunk len is 1024; >1024 shows multi-chunk)
Run count: 128 (trimmed subset sent to the API)
----------------------------------------

[info] chunk preview (byte-based): [1024, 1]
[info] sending 128 datum(s) to the API (use TINKER_RUN_COUNT to adjust)
[ok] forward_backward returned 128 chunk result(s) for run data
[step] running optim_step with weight_decay=0.01, grad_clip_norm=1.0...
[ok] optim_step metrics: nil
[done] AdamParams and byte-based chunking demo complete

==> Running examples/llama3_tokenizer_override_live.exs
Tokenizer ID: thinkingmachineslabinc/meta-llama-3-tokenizer
Encoded prompt token IDs (13): [128000, 80853, 71015, 445, 81101, 12, 18, 47058, 2882, 304, 832, 11914, 13]
Decoded first sequence:  I would like to ask for a small example of Llama-3 tokenizer override

==> Running examples/queue_reasons_and_sampling_throttling.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: Hello from throttling + queue reasons!
----------------------------------------


20:52:54.599 [info] The function passed as a handler with ID "queue-reasons-demo-6210" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] demonstrating server-preferred reason via QueueStateLogger
[info] simulating backoff to exercise throttled dispatch + byte penalty

20:52:54.606 [warning] Sampling is paused for 881c7df5-292c-58cd-a2ce-5a8f19a9ec0f:sample:0. Reason: server says: running short on capacity (demo)
[info] dispatch acquisition order (penalized bytes): one at -576460750802
[info] estimated prompt bytes: 90
[step] running live sample...
[ok] sample returned 1 sequence(s)
[done] queue reasons + throttling demo complete

==> Running examples/multimodal_resume_and_cleanup.exs
== Multimodal sampling with expected_tokens
No vision-capable model advertised; skipping multimodal sampling. Set TINKER_BASE_MODEL to a vision-capable model to exercise image input.

== Optimizer resume via ServiceClient helper
Restoring weights + optimizer from tinker://0ba9f266-961a-5c66-8bed-a5103ed577bd:train:0/weights/multi-delete-1764742201-a ...
Resume failed: %Tinkex.Error{message: "HTTP 400", type: :api_status, status: 400, category: :user, data: %{"detail" => "Invalid checkpoint tinker path tinker://0ba9f266-961a-5c66-8bed-a5103ed577bd:train:0/weights/multi-delete-1764742201-a."}, retry_after_ms: 1000}

CLI multi-delete (single confirmation):
  tinkex checkpoint delete tinker://run-1/weights/0001 tinker://run-2/weights/0002 --yes


==> Running examples/training_persistence_live.exs
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Checkpoint name: demo-checkpoint-1765176780
Saved checkpoint to tinker://69ebdc9e-0108-58e2-b022-d19c8beeb094:train:0/weights/demo-checkpoint-1765176780
Reloaded checkpoint with optimizer state
Created a fresh training client from checkpoint: #PID<0.342.0>

==> Running examples/checkpoint_multi_delete_live.exs
Saved checkpoint multi-delete-1765176812-a: tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-a
Saved checkpoint multi-delete-1765176812-b: tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-b
Cached default checkpoint path at tmp/checkpoints/default.path: tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-a

Deleting 2 checkpoints with one confirmation...
Deleting 1/2: tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-a
Deleted tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-a
Deleting 2/2: tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-b
Deleted tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-b

Multi-delete summary:
result: %{
  command: :checkpoint,
  action: :delete,
  failed: 0,
  paths: ["tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-a",
   "tinker://723f51aa-c3aa-52bd-9722-decdf17190d0:train:0/weights/multi-delete-1765176812-b"],
  failures: [],
  deleted: 2
}

==> Running examples/save_weights_and_sample.exs
[setup] base_model=Qwen/Qwen3-8B
[setup] prompt="Hello from Tinkex!"
[setup] max_tokens=32 lora_rank=8
[save] saving weights and creating a SamplingClient (sync helper)...
[error] save_weights_and_get_sampling_client_sync failed: [validation] Either model_path or base_model must be provided data=nil

==> Running examples/queue_state_observer_demo.exs
====================================================
Queue State Observer Demo
====================================================
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Observer mode: builtin

This demo shows how queue state observers work.
When rate limits or capacity issues occur, you'll see
automatic log warnings from the built-in observer.


[step] Creating ServiceClient...

----------------------------------------------------
Part 1: SamplingClient Queue State Observer
----------------------------------------------------
The SamplingClient automatically logs warnings when
queue state changes. Watch for messages like:

  [warning] Sampling is paused for session-xyz.
            Reason: concurrent LoRA rate limit hit


[step] Creating SamplingClient...
[step] SamplingClient created successfully
[info] Using built-in observer (automatic logging)
[step] Submitting sample request...
[note] If rate limited, you'll see queue state warnings here

[success] Got 1 sample(s)

----------------------------------------------------
Part 2: TrainingClient Queue State Observer
----------------------------------------------------
The TrainingClient uses "concurrent models rate limit hit"
instead of "concurrent LoRA rate limit hit" for rate limits.

  [warning] Training is paused for model-abc.
            Reason: concurrent models rate limit hit


[step] Creating TrainingClient with LoRA (rank=8)...
[note] This may take 30-120s on first run (model loading)...

[step] TrainingClient created successfully
[info] Using built-in observer (automatic logging)
[step] Submitting forward_backward request...
[note] If rate limited, you'll see queue state warnings here

[warning] Training failed (this is expected if rate limited)
[warning] Error: [api_status (400)] HTTP 400

[success] Demo completed successfully!

==> Running examples/recovery_simulated.exs

20:54:12.983 [info] The function passed as a handler with ID "recovery-demo-10818" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
1) Seeded checkpoint tinker://demo-run-10754/weights/0001
2) Simulated corruption flag on demo-run-10754
3) Recovery succeeded from tinker://demo-run-10754/weights/0001 -> #PID<0.323.0>
4) Checkpoints processed: tinker://demo-run-10754/weights/0001, tinker://demo-run-10754/weights/0002
Final run status: %{
  clients: [#PID<0.323.0>],
  completed: [
    %Tinkex.Types.Checkpoint{
      checkpoint_id: "cp-0001",
      checkpoint_type: "weights",
      tinker_path: "tinker://demo-run-10754/weights/0001",
      training_run_id: "demo-run-10754",
      size_bytes: nil,
      public: false,
      time: ~U[2025-12-08 06:54:12.978510Z]
    },
    %Tinkex.Types.Checkpoint{
      checkpoint_id: "cp-0002",
      checkpoint_type: "weights",
      tinker_path: "tinker://demo-run-10754/weights/0002",
      training_run_id: "demo-run-10754",
      size_bytes: nil,
      public: false,
      time: ~U[2025-12-08 06:54:12.981619Z]
    }
  ],
  last_checkpoint: "tinker://demo-run-10754/weights/0002",
  corrupted?: false
}

==> Running examples/recovery_live_injected.exs
Saved checkpoint tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:0/weights/recovery-live-1
Recovery callback: old=#PID<0.323.0> new=#PID<0.345.0> cp=tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:0/weights/recovery-live-1
Saved checkpoint tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:1/weights/recovery-live-2
Recovered from tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:0/weights/recovery-live-1
Second checkpoint saved: tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:1/weights/recovery-live-2

==> Running examples/kimi_k2_sampling_live.exs
== Kimi K2 tokenization (tiktoken_ex)
Model: moonshotai/Kimi-K2-Thinking
Prompt: "Say hi"
Token IDs (first 32): [71079, 20910] (2 total)
Round-trip decode: "Say hi"

== Live sampling
Sampling 1 sequence(s) from moonshotai/Kimi-K2-Thinking ...
Received 1 sequence(s):
Sample 1:  to your folks for me." He turned his attention back to the road, and the car lurched forward.
I stood on the curb, watching them go.

==> Running examples/model_info_and_unload.exs
[tinkex] base_url=https://tinker.thinkingmachines.dev/services/tinker-prod
[tinkex] base_model=meta-llama/Llama-3.1-8B
[tinkex] created session_id=8dff67e9-e3f4-56f2-b3a4-2b67d36155f4
[tinkex] poll #1 create_model request_id=8dff67e9-e3f4-56f2-b3a4-2b67d36155f4:train:0:0
[tinkex] created model_id=8dff67e9-e3f4-56f2-b3a4-2b67d36155f4:train:0
[tinkex] model_id=8dff67e9-e3f4-56f2-b3a4-2b67d36155f4:train:0
- model_name: meta-llama/Llama-3.1-8B
- arch: unknown
- tokenizer_id: thinkingmachineslabinc/meta-llama-3-tokenizer
- is_lora: true
- lora_rank: 32
[tinkex] unload_model
[tinkex] unload failed: [api_status (404)] HTTP 404 status=404
[tinkex] error data: %{"detail" => "Not Found"}
````
