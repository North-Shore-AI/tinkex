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
- `multimodal_resume_and_cleanup.exs` – builds a multimodal payload (text + image), prefers Qwen3-VL models (`Qwen/Qwen3-VL-30B-A3B-Instruct`, `Qwen/Qwen3-VL-235B-A22B-Instruct`) when advertised (override via `TINKER_BASE_MODEL`), and runs a live sampling request when a vision model is available (otherwise logs and skips). Uses `examples/assets/vision_sample.png` by default (override via `TINKER_IMAGE_PATH`; optional `TINKER_IMAGE_EXPECTED_TOKENS`). Then restores a training client with optimizer state (uses `TINKER_CHECKPOINT_PATH` override or caches the first checkpoint at `tmp/checkpoints/default.path`; only `TINKER_API_KEY` is required) and prints the CLI multi-delete usage.
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
- `TINKER_IMAGE_PATH` - Image path override for `multimodal_resume_and_cleanup.exs` (defaults to `examples/assets/vision_sample.png`)
- `TINKER_IMAGE_EXPECTED_TOKENS` - Optional expected token count for the image chunk (if set and incorrect, the backend may reject the request)
- `TINKER_CHECKPOINT_PATH` - Optional override for optimizer resume path in `multimodal_resume_and_cleanup.exs`; falls back to cached `tmp/checkpoints/default.path` or the first checkpoint discovered via API

## Running Examples

Each example can be executed directly using the Mix run command:

```bash
export TINKER_API_KEY="tml-your-api-key-here"
mix run examples/example_name.exs
```

For examples requiring additional configuration, set the relevant environment variables before execution:

```bash
export TINKER_API_KEY="tml-your-api-key-here"
export TINKER_BASE_MODEL="meta-llama/Llama-3.1-8B"
export TINKER_PROMPT="Your custom prompt here"
mix run examples/sampling_basic.exs
```

### Run every example in one go

To run the curated set of runnable scripts sequentially, use the helper script:

```bash
export TINKER_API_KEY="tml-your-api-key-here"
examples/run_all.sh
```

The script simply iterates through the example list and executes `mix run examples/<name>.exs` for each entry, exiting on the first failure. Export any additional variables (e.g., `TINKER_BASE_MODEL`, `TINKER_PROMPT`, `TINKEX_DEBUG=1`) before invoking the script so they apply to every example.

### Heartbeat probe

To verify the live heartbeat path, run:

```bash
export TINKER_API_KEY="tml-your-api-key-here"
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
export TINKER_API_KEY="tml-your-api-key-here"
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
export TINKER_API_KEY="tml-your-api-key-here"
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
Compiling 10 files (.ex)
Compiling 3 files (.ex)
Generated tinkex app
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Received 1 sequence(s):
Sample 1:  I’m Tinkex the Flying Squirrel!
I’m a 2D platformer. I will fly across the bright and colorful backgrounds and try to collect all the gems. I will help you to go through the dangerous and unpredictable levels, where you will deal with traps and different enemies.

==> Running examples/training_loop.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: 'Fine-tuning sample prompt'
Sample after training: false

[step] creating ServiceClient...
[step] creating ServiceClient completed in 648ms
[step] creating TrainingClient (LoRA rank=16)...
[note] this may take 30-120s on first run (model loading)...
[step] creating TrainingClient (LoRA rank=16) completed in 217ms
[step] building model input...
[step] got 6 tokens: [128000, 64816, 2442, 38302, 6205, 10137]
[step] building model input completed in 1.23s
[step] running forward_backward...
[step] forward_backward completed in 18.95s
[metrics] forward_backward: %{"clock_cycle:unique" => 105018.0, "loss:sum" => 85.29592895507812}
[step] running optim_step...
[step] optim_step completed in 772ms
[metrics] optim_step: (none - optimizer doesn't compute metrics)
[step] saving weights for sampler...
[step] save_weights_for_sampler completed in 3.88s
[result] save_weights: %{"path" => "tinker://51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0/sampler_weights/sampler-weights", "sampling_session_id" => nil, "size_bytes" => nil, "type" => "save_weights_for_sampler"}

[done] Training loop finished in 23.61s

==> Running examples/custom_loss_training.exs
================================================================================
Custom Loss Training (Live)
================================================================================

Base URL : https://tinker.thinkingmachines.dev/services/tinker-prod
Base model : meta-llama/Llama-3.1-8B

Creating training client...
Preparing training datum for prompt: Name three planets in the solar system.

Running forward_backward_custom...
Custom loss completed in 38948 ms

Running optim_step...
optim_step succeeded.

=== ForwardBackwardOutput ===
loss_fn_output_type: CrossEntropyLossReturn
metrics: %{"clock_cycle:unique" => 2032351.0, "custom_perplexity" => 200694.9375, "loss:sum" => 12.214847564697266}
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

Forward pass completed in 13605ms
Output type: CrossEntropyLossReturn
Metrics: %{"clock_cycle:unique" => 908449.0, "loss:sum" => 71.73094177246094}
Number of loss_fn_outputs: 1

=== Nx Tensor Conversion Demo ===
Nx default backend: {Nx.BinaryBackend, []}
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
  Parallel: 557 μs
  Sequential: 433 μs
  Results match: true

--- 8. Async Regularizers (for I/O-bound operations) ---

Created async regularizer (simulates external API call)
Async regularizer result:
  loss_total: 1.1016
  async_external_validation contribution: 0.0216
  Execution time: 10559 μs

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


08:05:05.472 [info] The function passed as a handler with ID "tinkex-regularizer-21" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
Attached telemetry handler: tinkex-regularizer-21

Running pipeline with telemetry (watch for log output):

08:05:05.477 [info] Custom loss starting: regularizers=1 track_grad_norms=true

08:05:05.477 [info] Regularizer l1_sparsity starting

08:05:05.477 [info] Regularizer l1_sparsity value=10.8 contribution=0.108 in 0ms grad_norm=3.1623

08:05:05.477 [info] Custom loss computed in 0ms total=1.188 regularizer_total=0.108 regularizers=1
Detached telemetry handler

--- 12. JSON Serialization ---

CustomLossOutput as JSON:
{
  "loss_total": 1.3015641638748348,
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
      "value": 12.359999656677246,
      "custom": {
        "elastic_net": 12.359999656677246,
        "l1_ratio": 0.6
      },
      "weight": 0.002,
      "contributio...

(Output truncated for display)

RegularizerOutput as JSON:
{
  "name": "l1_sparsity",
  "value": 10.800000190734863,
  "custom": {
    "l1_mean": 1.0800000429153442,
    "l1_raw": 10.800000190734863
  },
  "weight": 0.01,
  "contribution": 0.10800000190734864,
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
  metrics: %{"l1_value" => 10.800000190734863}

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

Completed in 27993ms

=== Metrics ===
base_nll: 12.02071
clock_cycle:unique: 105023.0
consistency: 14.65879
custom_perplexity: 166160.59375
elastic_net: 71.157852
entropy: 1.35026
gradient_penalty: 5.366751
kl_forward: -0.003815
kl_reverse: 9.622814
kl_symmetric: 4.809499
l1: 12.02071
l2: 15.366092
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
  • 20dd1ff5-21ae-570d-adf1-2f7c6dc1a4ea
  • d3a4e3d2-3551-5192-ad7e-28be5ff2d2c8
  • c232dda9-5380-59a3-8c7f-bc69ecb219cb
  • 9482c87c-31d5-52ec-bc77-6ecfaf61146a
  • 51056eb0-5fa7-57d1-a2d2-50e05d9e54d3
  • b620577f-c5f2-53b3-addf-008affc967b1
  • 16951143-cfc7-5f3c-a279-7754df375182
  • 90c2d45b-45c0-5099-b5ee-6376f5631366
  • e73aadc9-acd3-5ada-bdc7-cbe5698b75cd
  • e23dd145-f7e7-5a2e-9030-1894a742f029

--- Session Details: 20dd1ff5-21ae-570d-adf1-2f7c6dc1a4ea ---
Training Runs: 0
Samplers: 0

=== Example Complete ===

==> Running examples/checkpoints_management.exs
=== Tinkex Checkpoint Management Example ===

--- All User Checkpoints ---
Found 20 of 107 checkpoints:

  sampler_weights/sampler-weights
    Path: tinker://51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-13 18:04:04.468099Z

  weights/recovery-live-2
    Path: tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-08 06:54:55.955090Z

  weights/recovery-live-1
    Path: tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-08 06:54:38.615993Z

  weights/demo-checkpoint-1765176780
    Path: tinker://69ebdc9e-0108-58e2-b022-d19c8beeb094:train:0/weights/demo-checkpoint-1765176780
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-08 06:53:12.221993Z

  weights/async_demo_checkpoint
    Path: tinker://a01f0a63-89aa-560b-8dbf-82a8fffbaa7b:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-08 06:51:22.843442Z

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


--- All User Checkpoints (paginated) ---
Fetched 50 (107 total)
  sampler_weights/sampler-weights
    Path: tinker://51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-13 18:04:04.468099Z

  weights/recovery-live-2
    Path: tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-08 06:54:55.955090Z

  weights/recovery-live-1
    Path: tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-08 06:54:38.615993Z

  weights/demo-checkpoint-1765176780
    Path: tinker://69ebdc9e-0108-58e2-b022-d19c8beeb094:train:0/weights/demo-checkpoint-1765176780
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-08 06:53:12.221993Z

  weights/async_demo_checkpoint
    Path: tinker://a01f0a63-89aa-560b-8dbf-82a8fffbaa7b:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-08 06:51:22.843442Z

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

Fetched 50 (107 total)
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

Fetched 7 (107 total)
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

  d3a4e3d2-3551-5192-ad7e-28be5ff2d2c8:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  c232dda9-5380-59a3-8c7f-bc69ecb219cb:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  9482c87c-31d5-52ec-bc77-6ecfaf61146a:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  16951143-cfc7-5f3c-a279-7754df375182:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  90c2d45b-45c0-5099-b5ee-6376f5631366:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  e73aadc9-acd3-5ada-bdc7-cbe5698b75cd:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  a793774d-a0bc-51b4-8678-d78681221fac:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  8d5bb0bd-cad3-5eeb-b7c9-90a4a28f946b:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  8dbb1404-d815-513c-9a5e-b5a0c494a4f6:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5


--- Training Run Details: d3a4e3d2-3551-5192-ad7e-28be5ff2d2c8:train:0 ---
  ID: d3a4e3d2-3551-5192-ad7e-28be5ff2d2c8:train:0
  Base Model: meta-llama/Llama-3.1-8B
  Is LoRA: true
  LoRA Rank: 16
  Corrupted: false
  Last Checkpoint: none
  Last Sampler Checkpoint: none
  Last Request: 2025-12-13 18:05:35.906800Z
  Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

--- User Checkpoints ---
Found 10 checkpoint(s):

  tinker://51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 168.14 MB
    Time: 2025-12-13 18:04:04.468099Z

  tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:1/weights/recovery-live-2
    Type: training
    ID: weights/recovery-live-2
    Size: 252.22 MB
    Time: 2025-12-08 06:54:55.955090Z

  tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:0/weights/recovery-live-1
    Type: training
    ID: weights/recovery-live-1
    Size: 252.22 MB
    Time: 2025-12-08 06:54:38.615993Z

  tinker://69ebdc9e-0108-58e2-b022-d19c8beeb094:train:0/weights/demo-checkpoint-1765176780
    Type: training
    ID: weights/demo-checkpoint-1765176780
    Size: 252.22 MB
    Time: 2025-12-08 06:53:12.221993Z

  tinker://a01f0a63-89aa-560b-8dbf-82a8fffbaa7b:train:0/weights/async_demo_checkpoint
    Type: training
    ID: weights/async_demo_checkpoint
    Size: 305.8 MB
    Time: 2025-12-08 06:51:22.843442Z

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


=== Example Complete ===

==> Running examples/checkpoint_download.exs
=== Tinkex Checkpoint Download Example ===

TINKER_CHECKPOINT_PATH not provided; downloading first available checkpoint:
  tinker://51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0/sampler_weights/sampler-weights

Downloading checkpoint: tinker://51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0/sampler_weights/sampler-weights
Output directory: /tmp/tinkex_checkpoints

Progress: 100.0% (168.1 MB / 168.1 MB)

Download complete!
Extracted to: /tmp/tinkex_checkpoints/51056eb0-5fa7-57d1-a2d2-50e05d9e54d3:train:0_sampler_weights_sampler-weights

Extracted files (3):
  • adapter_config.json (736 B)
  • adapter_model.safetensors (168.1 MB)
  • checkpoint_complete (0 B)

=== Example Complete ===

==> Running examples/async_client_creation.exs
=== Tinkex Async Client Creation Example ===

Creating sampling client asynchronously...
Task created, awaiting result...
✓ Sampling client created: #PID<0.311.0>

Creating LoRA training client asynchronously...
Task created, awaiting result...
✓ LoRA training client created: #PID<0.318.0>

Saving training state to create checkpoint...
✓ Saved state to: tinker://fea7a6c0-cb47-585a-bf33-f2b6d7cdd42a:train:0/weights/async_demo_checkpoint

Restoring training client from checkpoint asynchronously...
✓ Training client restored: #PID<0.333.0>

=== Example Complete ===

==> Running examples/cli_run_text.exs
Running CLI with args: run --base-model meta-llama/Llama-3.1-8B --prompt Hello from the CLI runner --max-tokens 64 --temperature 0.7 --num-samples 1 --api-key tml-mIf5gSt5tyewbDuXjwgeTkbdcgCZUpntGFyVBfKvmfGpb2FpJbfJ9tcFyYC5DXjcrAAAA
Starting sampling...
Sample 1:
 community.
We’ve been posting weekly updates to our community since the launch of CLI Runner, and we’ve decided to start sharing them here too.
Here’s what’s been happening in the past week:
We fixed a bug where the CLI runner would crash when trying to run a job that had a step that didn’t reference
stop_reason=length | avg_logprob=-1.584
Sampling complete (1 sequences)
sampling response: %Tinkex.Types.SampleResponse{
  sequences: [
    %Tinkex.Types.SampledSequence{
      tokens: [4029, 627, 1687, 4070, 1027, 17437, 17496, 9013, 311, 1057, 4029,
       2533, 279, 7195, 315, 40377, 46046, 11, 323, 584, 4070, 6773, 311, 1212,
       11821, 1124, 1618, 2288, 627, 8586, 753, 1148, 753, 1027, 12765, 304,
       279, 3347, 2046, 512, 1687, 8521, 264, 10077, 1405, 279, 40377, ...],
      logprobs: [-7.1504082679748535, -3.548954963684082, -0.8432145714759827,
       -3.7652602195739746, -0.3171641528606415, -8.535903930664062,
       -4.072669506072998, -0.408132404088974, -2.073996067047119,
       -0.6542057394981384, -2.3376808166503906, -3.291036367416382,
       -1.067060947418213, -2.5809507369995117, -0.017461497336626053,
       -0.8036983013153076, -1.248597502708435, -1.857757329940796,
       -0.4016723036766052, -0.49168887734413147, -1.5423728227615356,
       -1.0354734659194946, -0.1142837181687355, -0.9116798043251038,
       -1.1620310544967651, -0.8455746173858643, -0.896711528301239,
       -2.4103140830993652, -0.848863959312439, -3.0597715377807617,
       -0.27744022011756897, -1.057984709739685, -1.6263339519500732,
       -0.51412433385849, -0.2626418471336365, -0.6739249229431152,
       -0.11578977853059769, -1.298628330230713, -0.32234883308410645,
       -0.5400999188423157, -0.8074171543121338, -4.869328022003174,
       -0.5103867053985596, -0.25200900435447693, -1.4003057479858398,
       -0.4965852200984955, ...],
      stop_reason: :length
    }
  ],
  prompt_logprobs: nil,
  topk_prompt_logprobs: nil,
  type: "sample"
}

==> Running examples/cli_run_prompt_file.exs
Running CLI with prompt file /tmp/tinkex_prompt_9411.txt
Starting sampling...
Sampling complete (1 sequences)
JSON output written to /tmp/tinkex_output_9475.json
Preview:
{"prompt_logprobs":null,"sequences":[{"logprobs":[-3.025696039199829,-3.4897959232330322,-4.838353157043457,-3.982738494873047,-4.041533470153809,-3.7887024879455566,-2.2361600399017334,-3.416745662689209,-5.481904983520508,-1.8151867389678955,-0.06926839798688889,-4.23408317565918,-2.5793867111206055,-0.5476784706115723,-1.0005900859832764,-0.27768442034721375,-1.5020582675933838,-2.5450515747070312,-0.8015535473823547,-0.0229493360966444,-1.3163361549377441,-0.9038182497024536,-1.0711292028427124,-8.379087448120117,-0.6717662215232849,-7.316762447357178,-3.410490036010742,-7.85792350769043,-4.744497299194336,-4.646977424621582,-1.3598833084106445,-1.7405455112457275,-5.503695487976074,-2.3318605422973633,-6.789593696594238,-1.1641185283660889,-3.1640608310699463,-1.1502330303192139,-0.08503222465515137,-1.8809154033660889,-2.592095136642456,-1.0010550022125244,-6.092687606811523,-6.9638261795043945,-0.697133481502533,-8.660367012023926,-2.5746405124664307,-5.021520614624023,-3.911353826522827,-0.4099976420402527,-3.2738349437713623,-3.9655323028564453,-2.7665791511535645,-6.912379741668701,-5.804718017578125,-2.299795627593994,-0.9553049802780151,-2.800122022628784,-0.5821402668952942,-0.8071856498718262,-0.5003320574760437,-7.157462120056152,-5.322279453277588,-1.0119328498840332,-1.4818432331085205,-2.4835333824157715,-2.113086700439453,-3.0668790340423584,-12.023530006408691,-0.025376325473189354,-1.522172212600708,-1.9340626001358032,-4.283868789672852,-5.151783466339111,-12.333015441894531,-0.789423942565918,-6.470842361450195,-2.589305877685547,-0.024889469146728516,-2.6786842346191406,-2.174694061279297,-5.794835567474365,-1.1417479515075684,-8.071657180786133,-5.886308670043945,-4.31973934173584,-2.7830333709716797,-6.953725814819336,-1.394743800163269,-3.4445550409145653e-4,-4.6852312088012695,-3.744091510772705,-11.080554962158203,-2.916038751602173,-3.176513195037842,-2.347118854522705,-7.115866661071777,-4.450666427612305,-3.9144797325134277,-6.913010120391846,-5.781047821044922,-1.1942366361618042,-12.832793235778809,-3.8976166248321533,-3.399862766265869,-7.4198503494262695,-0.5706915259361267,-1.1404515504837036,-5.843376636505127,-6.192821025848389,-1.2431952953338623,-2.6399435997009277,-9.40709114074707,-7.868457317352295,-4.79378080368042,-1.9932386875152588,-1.724284291267395,-1.1247574090957642,-7.394559860229492,-1.0851293802261353,-3.19225811958313,-0.5222971439361572,-3.2932424545288086,-6.233297348022461,-0.19235028326511383,-5.287505149841309,-0.019150134176015854,-5.700234413146973,-0.12258584052324295,-2.2147254943847656,-1.013492226600647,-2.1254723072052,-3.5342860221862793,-4.613475799560547,-2.4111719131469727,-6.55515718460083,-2.1758360862731934,-4.987590789794922,-0.6425871849060059,-4.78355598449707,-1.2765480279922485,-3.243790626525879,-1.043023943901062,-3.5904223918914795,-4.952436447143555,-1.2822781801223755,-0.02027442492544651,-0.017788046970963478,-0.7087422013282776,-0.7485809326171875,-4.302149772644043,-2.9346280097961426,-0.6578460931777954,-1.2396349906921387,-5.6584343910217285,-2.4207048416137695,-2.8362183570861816,-0.2459764927625656,-4.200606822967529,-2.399829149246216,-5.332483768463135,-1.6984069347381592,-8.982038497924805,-5.069303512573242,-12.225506782531738,-0.007916858419775963,-0.7357928156852722,-3.3867111206054688,-2.8666176795959473,-2.1169862747192383,-2.2356817722320557,-3.407243490219116,-1.4976184368133545,-2.5067832469940186,-4.596858024597168,-0.10881175100803375,-9.256787300109863,-1.0628867149353027,-3.9704153537750244,-8.702530860900879,-5.233683109283447,-2.6401641368865967,-5.512701034545898,-7.752107620239258,-2.351719856262207,-0.005228179972618818,-0.007480940781533718,-0.008119196631014347,-2.2513861656188965,-0.6322335600852966,-0.38765615224838257,-0.32079580426216125,-5.048252105712891,-0.37312793731689453,-2.3119757175445557,-0.5296133756637573,-2.236729860305786,-1.0663084983825684,-5.846041202545166,-0.9425379633903503,-1.2373985052108765,-4.546425819396973,-1.8957890272140503,-0.0343395434319973,-9.792586326599121,-0.8229575157165527,-0.008502001874148846,-1.3733234405517578,-3.027263641357422,-2.40727162361145,-3.936887264251709,-2.3914594650268555,-7.026406288146973,-4.334274768829346,-2.096723794937134,-9.455707550048828,-4.412418365478516,-4.707293510437012,-1.1862249374389648,-1.8768473863601685,-1.5368965864181519,-1.3934376239776611,-6.475048542022705,-8.563284873962402,-0.2608819007873535,-6.320605278015137,-10.668148040771484,-5.960540771484375,-7.594727516174316,-1.0489511489868164,-0.22141285240650177,-4.359391689300537,-6.354190826416016,-1.0704466104507446,-4.182348728179932,-0.9903972148895264,-9.890692710876465,-4.472762107849121,-5.9738616943359375,-4.037741661071777,-0.577606737613678,-1.6783093214035034,-6.936842918395996,-6.1391496658325195,-4.952871322631836,-6.305163383483887,-1.2156856060028076,-8.011954307556152,-9.213798522949219,-0.8676616549491882,-2.3999791145324707,-5.67311954498291,-3.7580695152282715,-2.815300464630127,-3.05488920211792,-4.264396667480469,-2.157440423965454,-5.5260796546936035,-0.23426304757595062,-0.9324260950088501,-1.0878534317016602,-6.416697025299072,-4.46500825881958,-4.280740261077881,-7.978292465209961,-1.60710608959198,-7.76317024230957,-0.38338834047317505,-1.1587824821472168,-1.4896572828292847,-5.114147186279297,-2.202253580093384,-0.009101686999201775,-2.2414937019348145,-8.256174087524414,-0.29591813683509827,-1.5002150535583496,-8.868410110473633,-0.9248039126396179,-2.6205148696899414,-1.5356780290603638,-7.2378621101379395,-0.09477263689041138,-7.087702751159668,-0.9192488193511963,-0.0015889888163655996,-3.770005702972412,-1.0649118423461914,-0.9218720197677612,-5.294816493988037,-1.8517872095108032,-4.405572414398193,-2.7728705406188965,-2.791749954223633,-0.011696805246174335,-0.07877340167760849,-5.031989574432373,-9.199760437011719,-0.8442966938018799,-2.7899258136749268,-5.834721565246582,-0.7975068092346191,-1.8190988302230835,-1.9243824481964111,-1.5171581506729126,-2.5627927780151367,-0.20999066531658173,-1.842368721961975,-4.581088066101074,-7.212950706481934,-7.807436943054199,-1.4368864297866821,-2.319873332977295,-6.907958984375,-5.346011161804199,-10.23203182220459,-6.979944229125977,-4.495486259460449,-1.6378862857818604,-7.178471088409424,-3.2815051078796387,-3.37876033782959,-6.837266445159912,-1.8434935808181763,-5.1331868171691895,-1.000324010848999,-2.6603026390075684,-0.3391916751861572,-3.3302831649780273,-5.034126281738281,-2.2891528606414795,-1.095426082611084,-5.000678062438965,-1.1100528240203857,-3.7029972076416016,-0.9216164350509644,-5.6080193519592285,-1.4156826734542847,-3.5840768814086914,-2.1903154850006104,-1.691255807876587,-3.241307258605957,-8.748435974121094,-1.511560082435608,-5.21695613861084,-3.1864702701568604,-2.6838200092315674,-7.906514644622803,-1.0330291986465454,-6.870367527008057,-4.081564903259277,-1.9401386976242065,-8.377819061279297,-6.4656219482421875,-4.144499778747559,-2.361382246017456,-2.3288776874542236,-1.8049094676971436,-9.786879539489746,-3.68664813041687,-2.1608424186706543,-1.2999062538146973,-0.4634464681148529,-9.446081161499023,-9.696352005004883,-0.10403896868228912,-7.40753173828125,-2.9980924129486084,-8.069002151489258,-1.166266918182373,-1.393257975578308,-1.8780031204223633,-2.5423994064331055,-6.275936126708984,-11.81277847290039,-3.9059488773345947,-4.877236366271973,-6.070926189422607,-1.410857915878296,-3.129284381866455,-0.4473651647567749,-0.0540994331240654,-1.8983407020568848,-2.471829414367676,-0.7207156419754028,-13.573415756225586,-11.02490520477295,-1.1117846965789795,-0.06017708033323288,-2.905505657196045,-3.515413522720337,-6.285492897033691,-0.00618306640535593,-1.9995357990264893,-5.754003524780273,-1.054722785949707,-11.594680786132812,-4.1187424659729,-6.9562177658081055,-2.5901784896850586,-5.833555221557617,-3.4397168159484863,-0.40877270698547363,-0.08183005452156067,-1.816535234451294,-7.204521179199219,-9.983590126037598,-1.9017633199691772,-8.384108543395996,-1.3384783267974854,-4.058760643005371,-6.952820301055908,-9.77871322631836,-2.967848300933838,-2.855963945388794,-1.9061390161514282,-5.2540388107299805,-0.0143232811242342,-2.1829049587249756,-3.1461565494537354,-0.5929434299468994,-7.119356155395508,-2.3198153972625732,-4.4664177894592285,-2.5147969722747803,-6.131519794464111,-9.942419052124023,-1.5108582973480225,-3.377128839492798,-6.10338020324707,-5.814617156982422,-9.18580436706543,-3.9009041786193848,-4.50989294052124,-0.3955172896385193,-1.734757900238037,-2.403585433959961,-6.959916591644287,-1.9737868309020996,-4.349694728851318,-8.224324226379395,-1.3324836492538452,-3.135150909423828,-1.9844292402267456,-4.685450553894043,-7.054054260253906,-0.49034368991851807,-1.4630916118621826,-2.2769103050231934,-0.2300039678812027,-0.4998844265937805,-8.584559440612793,-1.2843737602233887,-2.121216058731079,-2.294708251953125,-2.563279628753662,-7.915112495422363,-3.357381820678711,-8.077068328857422,-5.237475395202637,-3.0925233364105225,-0.12338519841432571,-0.8425803184509277,-3.097583055496216,-5.0876030921936035,-0.34066706895828247,-12.202810287475586,-4.251224517822266,-7.158044815063477,-5.811994552612305,-5.939337730407715,-4.786324977874756,-1.747721791267395,-4.728799819946289,-5.034611225128174,-1.5086588859558105,-7.502719402313232,-6.313857078552246,-2.3251495361328125,-2.910101890563965,-5.00321102142334,-4.487321376800537,-1.4419009685516357,-6.012881755828857,-0.16472195088863373,-3.0053114891052246,-0.013587608002126217,-3.5258431434631348,-4.965574264526367,-2.5655899047851562,-0.8095013499259949,-6.054292678833008,-0.25098779797554016,-1.843359112739563,-5.8385748863220215,-2.780134916305542,-5.305627346038818,-7.971423149108887,-0.29442891478538513,-8.84107780456543,-4.590526580810547,-2.3022565841674805,-2.217393636703491,-9.262946128845215,-3.575500011444092,-6.655107498168945,-10.286872863769531,-4.773249626159668,-7.831517219543457,-0.13899080455303192,-5.365932464599609,-6.248811721801758,-8.728192329406738,-0.0249090027064085,-7.076460361480713,-1.987311601638794,-4.614083290100098,-12.403421401977539,-9.411081314086914,-0.33988386392593384,-9.385912895202637,-0.7843312621116638,-0.40380099415779114,-5.242660045623779,-2.704420328140259,-6.274008750915527,-1.5073366165161133,-5.889546871185303,-2.5785884857177734,-7.699233531951904,-4.720683574676514,-3.6507140612229705e-4,-2.195390224456787,-0.8983066082000732,-3.7491986751556396,-9.798286437988281,-9.273184776306152,-2.4046554565429688,-4.160177230834961,-3.785425901412964,-6.5120038986206055,-1.7351677417755127,-8.4390869140625,-2.732605457305908,-2.53896427154541,-2.8718440532684326,-1.0815566778182983,-9.139026641845703,-1.2087254524230957,-2.8059890270233154,-2.4058005809783936,-3.142190456390381,-5.067569255828857,-4.503044128417969,-5.57534122467041,-7.038793087005615,-0.49204546213150024,-0.5387963056564331,-3.0738420486450195,-1.3913556337356567,-6.32019567489624,-3.472797393798828,-6.946234226226807,-2.0188214778900146,-2.6683411598205566,-6.161157608032227,-5.952831745147705,-2.112031936645508,-0.8010090589523315,-2.3764312267303467,-8.926811218261719,-2.068533420562744,-0.28411564230918884,-4.751130104064941,-0.005369763821363449,-1.554225206375122,-0.9360930919647217,-6.514286994934082,-4.0041351318359375,-0.7190356850624084,-5.545326232910156,-4.703491687774658,-2.2452831268310547,-10.865188598632812,-0.4540483355522156,-1.1262726783752441,-11.113760948181152,-11.477560043334961,-3.2830913066864014,-10.929559707641602,-4.780423164367676,-8.425603866577148,-2.269737720489502,-8.539045333862305,-10.811283111572266,-5.688617706298828,-4.977023124694824,-1.7331387996673584,-0.09480831027030945,-1.2160308361053467,-6.761878967285156,-8.083685874938965,-0.9309521913528442,-0.41948166489601135,-6.474377632141113,-11.046647071838379,-2.443277597427368,-4.629175186157227,-6.901726722717285,-0.09651554375886917,-1.3899061679840088,-3.3351895809173584,-2.029348134994507,-5.026644706726074,-1.4766366481781006,-5.21449089050293,-4.949216365814209,-6.409243583679199,-4.838743209838867,-1.3023874759674072,-8.114340782165527,-1.091314435005188,-0.23843061923980713,-1.777590036392212,-8.334016799926758,-2.8512625694274902,-5.840643882751465,-0.15963447093963623,-0.002249688608571887,-5.480129241943359,-8.425273895263672,-1.2835205793380737,-0.2835255265235901,-2.1888561248779297,-8.46290397644043,-1.8064820766448975,-3.6065096855163574,-0.1555265635251999,-1.6709636449813843,-2.429034948348999,-2.187028646469116,-5.372296333312988,-0.9528034925460815,-2.1790459156036377,-3.826483726501465,-1.1582823991775513,-1.1067742109298706,-3.725109338760376,-2.079155921936035,-1.1634770631790161,-5.917745590209961,-2.5606842041015625,-4.295101642608643,-1.5127805471420288,-2.477846384048462,-4.929770469665527,-0.5388892889022827,-1.5951002836227417,-4.815679550170898,-3.7332029342651367,-6.663653373718262,-7.004015922546387,-0.2480604648590088,-2.740945339202881,-4.3739213943481445,-0.20154313743114471,-3.9140326976776123,-0.5947703719139099,-6.840810298919678,-0.6790475249290466,-1.1347719430923462,-1.5323995351791382,-8.498834609985352,-6.233529567718506,-8.442756652832031,-4.694723606109619,-8.066761016845703,-0.39128515124320984,-1.7365901470184326,-7.578317642211914,-3.5907859802246094,-9.500675201416016,-3.165358543395996,-4.546144008636475,-11.105713844299316,-7.8667802810668945,-1.847731590270996,-5.022680759429932,-5.309821128845215,-0.7325171828269958,-6.897071361541748,-3.5612659454345703,-7.020320892333984,-4.957221031188965,-1.3332830667495728,-10.795286178588867,-2.8323636054992676,-6.748175144195557,-1.3969851732254028,-0.8626935482025146,-2.617800712585449,-14.387324333190918,-1.9782770872116089,-6.274344444274902,-6.417116165161133,-3.6462135314941406,-5.903509616851807,-13.875564575195312,-11.267038345336914,-3.730473041534424,-8.74604606628418,-1.1547259092330933,-9.607996940612793,-2.4036147594451904,-3.9317448139190674,-5.704814910888672,-3.5371310710906982,-2.3097968101501465,-9.394268035888672,-2.024954319000244,-1.4524935483932495,-5.411561489105225,-4.318902015686035,-4.402475357055664,-2.456632137298584,-5.210230827331543,-10.157633781433105,-0.19923648238182068,-0.2895786762237549,-14.856823921203613,-2.7582554817199707,-6.449850082397461,-4.679463863372803,-6.151156902313232,-1.1034767627716064,-8.595211029052734,-0.9721438884735107,-5.102712631225586,-1.8541606664657593,-4.630821704864502,-4.878361701965332,-0.6535159945487976,-3.9504477977752686,-1.1020903587341309,-6.464789867401123,-1.1513829231262207,-3.980325698852539,-2.9243505001068115,-0.17759312689304352,-0.1493237167596817,-1.8414819240570068,-6.3630805015563965,-4.501737117767334,-4.319284915924072,-8.475319862365723,-1.8419108390808105,-6.7209978103637695,-6.535702705383301,-0.8917056322097778,-0.3048034608364105,-0.7886217832565308,-2.2570815086364746,-1.3170007467269897,-6.089432716369629,-3.951314926147461,-1.2562482357025146,-3.2408862113952637,-4.519215106964111,-2.5913665294647217,-9.312250137329102,-3.841825008392334,-4.671795845031738,-0.08800793439149857,-1.6262227296829224,-6.123904228210449,-3.592233419418335,-2.2333083152770996,-0.9655603170394897,-1.2429126501083374,-7.751476287841797,-5.566987037658691,-3.6183323860168457,-0.9792526960372925,-2.7706499099731445,-4.060028553009033,-1.3333443403244019,-6.96173620223999,-1.9572783708572388,-1.2517293691635132,-9.826967239379883,-7.640473365783691,-3.743875026702881,-11.272836685180664,-2.533677816390991,-0.9302537441253662,-8.168253898620605,-8.147543907165527,-3.506408452987671,-7.52756404876709,-2.624738931655884,-1.6829246282577515,-10.840214729309082,-4.030367374420166,-1.8911534547805786,-9.74068546295166,-1.799918293952942,-9.218852996826172,-2.9031434059143066,-10.686826705932617,-1.4368599653244019,-4.523280143737793,-5.680057525634766,-1.7375116348266602,-1.3000699281692505,-5.933823108673096,-2.0730338096618652,-1.1159167289733887,-4.517872333526611,-1.1384682655334473,-1.0624337196350098,-10.184062957763672,-5.83445930480957,-2.2054340839385986,-5.494099140167236,-10.826064109802246,-1.902824878692627,-2.5767085552215576,-4.911996841430664,-9.086302757263184,-0.557978093624115,-0.8090352416038513,-3.299950361251831,-2.6907310485839844,-1.5884422063827515,-5.812432765960693,-0.8958203196525574,-7.86104679107666,-1.077542781829834,-6.784422874450684,-2.4310081005096436,-10.377486228942871,-3.612636089324951,-15.098679542541504,-3.202655076980591,-10.0764799118042,-2.641963005065918,-0.8007711172103882,-3.165435552597046,-8.761849403381348,-7.5031304359436035,-4.234189987182617,-4.315836429595947,-0.007670591119676828,-3.4313108921051025,-0.4458136558532715,-5.731142997741699,-0.1900615245103836,-0.26683083176612854,-2.508694887161255,-5.866711616516113,-0.687239408493042,-1.7651805877685547,-2.287064552307129,-4.828229904174805,-0.02618839032948017,-6.8518171310424805,-0.592533528804779,-5.942873001098633,-2.7099416255950928,-11.181535720825195,-3.040637969970703,-5.498404502868652,-1.852453589439392,-0.8801359534263611,-1.3271484375,-3.6797478199005127,-9.81787109375,-4.326875686645508,-0.4227485954761505,-10.56921672821045,-2.1878702640533447,-4.280265808105469,-10.908709526062012,-2.5833840370178223,-7.419928073883057,-4.1855058670043945,-1.6822059154510498,-0.12711776793003082,-2.4205052852630615,-2.1342973709106445,-12.067365646362305,-2.925652027130127,-12.136661529541016,-10.181781768798828,-5.468680381774902,-6.803785800933838,-6.735340118408203,-3.053309917449951,-8.536128997802734,-1.1702065467834473,-1.6920150518417358,-5.408812999725342,-1.30111825466156,-6.25788688659668,-3.646744728088379,-1.4726333618164062,-1.730677843093872,-1.1395354270935059,-0.4896814823150635,-7.513782978057861,-7.776716232299805,-6.359313488006592,-2.1114864349365234,-5.471551895141602,-2.600029230117798,-0.5795108675956726,-0.9653878211975098,-3.1816623210906982,-3.0322365760803223,-10.535469055175781,-6.885797023773193,-1.9431685209274292,-4.252843856811523,-10.685079574584961,-0.17159734666347504,-6.2210612297058105,-8.36983871459961,-8.034035682678223,-5.885759353637695,-4.840466499328613,-3.9711837768554688,-4.862919330596924,-7.364482879638672,-4.315253257751465,-0.035109832882881165,-2.195387840270996,-3.272723436355591,-0.599258303642273,-1.254574179649353,-1.233992338180542,-8.01000690460205,-5.908424377441406,-6.162021636962891,-1.4443522691726685,-4.551718711853027,-5.201076507568359,-8.385488510131836,-1.6819524765014648,-0.8773485422134399,-0.4669969081878662,-5.704839706420898,-1.1532936096191406,-5.618430137634277,-1.501024603843689,-9.664549827575684,-0.7256725430488586,-0.9098818302154541,-9.925256729125977,-1.5421814918518066,-0.04048475623130798,-2.209474563598633,-3.8760924339294434,-1.8545119762420654,-4.300416946411133,-4.839809417724609,-3.068394184112549,-6.810686111450195,-4.20419979095459,-0.965671718120575,-9.347689628601074,-0.4636582136154175,-0.20119792222976685,-0.18315690755844116,-1.229314923286438,-3.678189277648926,-5.980646133422852,-3.173384428024292,-0.08326192945241928,-8.51148796081543,-4.634904384613037,-2.1241507530212402,-4.524188041687012,-3.891064167022705,-8.98316764831543,-4.238117694854736,-8.050602912902832,-3.1188712120056152,-5.423854827880859,-9.359296798706055,-0.12755008041858673,-0.017551813274621964,-5.12448263168335,-1.1742507219314575,-7.3594746589660645,-2.9734411239624023,-2.7172067165374756,-8.73954963684082,-4.333459854125977,-0.20290865004062653,-0.270429402589798,-1.779132604598999,-0.3371533453464508,-1.5115268230438232,-0.8270556926727295,-4.445121765136719,-6.804965019226074,-2.5652823448181152,-4.004223823547363,-10.897811889648438,-0.45038264989852905,-12.227442741394043,-8.270185470581055,-0.5022763013839722,-1.3532873392105103,-3.335606575012207,-3.0650110244750977,-2.6228811740875244,-0.0024239225313067436,-4.339533805847168,-1.7168763875961304,-0.351129949092865,-4.299100875854492,-9.078425407409668,-0.3398228585720062,-0.19947566092014313,-3.1862645149230957,-9.955883026123047,-9.345434188842773,-0.5257409811019897,-1.6446501016616821,-2.6990082263946533,-1.1995747089385986,-4.432205677032471,-10.327812194824219,-3.2740769386291504,-1.9495759010314941,-9.862207412719727,-9.179418563842773,-3.6210451126098633,-9.283774375915527,-3.930616855621338,-0.8823705911636353,-1.9955832958221436,-7.360956192016602,-0.6119352579116821,-0.008853821083903313,-2.6361775398254395,-4.745109558105469,-6.857193470001221,-3.921144723892212,-1.4788771867752075,-2.428786277770996,-7.604803085327148,-1.0191149711608887,-7.763747692108154,-3.7715682983398438,-6.491349697113037,-2.1773102283477783,-4.655986785888672,-4.344223499298096,-0.773740291595459,-5.713171005249023,-5.147894859313965,-1.412451148033142,-1.7112374305725098,-1.8702560663223267,-3.4758739471435547,-7.259488105773926,-2.7633790969848633,-0.3387802541255951,-9.086374282836914,-3.018676996231079,-13.427108764648438,-9.64670181274414,-8.367481231689453,-1.9966142177581787,-7.216560363769531,-2.1553406715393066,-2.967214584350586,-6.515346050262451,-0.3806704580783844,-5.336893081665039,-2.9097464084625244,-7.762802600860596,-0.8102627396583557,-2.9778952598571777,-4.569418907165527,-0.22921325266361237,-0.0717146024107933,-0.24747677147388458,-1.3358612060546875,-5.914405822753906,-8.133776664733887,-4.902510643005371,-1.8255469799041748,-3.9934451580047607,-2.636056423187256,-4.155975341796875,-1.4327887296676636,-8.152803421020508,-0.8108104467391968,-3.1957550048828125,-1.2343370914459229,-1.432695746421814,-4.239981651306152,-0.30929872393608093,-6.505189895629883,-1.417873501777649,-8.450523376464844,-5.340208053588867,-1.4279181957244873,-11.406124114990234,-7.328520774841309,-0.46609318256378174,-4.36161470413208,-5.185938358306885,-0.22773343324661255,-1.459211826324463,-4.289869785308838,-2.0759739875793457,-3.0872905254364014,-3.0216565132141113,-1.3011513948440552,-1.906397819519043,-2.655954122543335,-2.117988348007202,-3.86108660697937,-0.11833950877189636,-1.0923529863357544,-1.8896195888519287,-1.382392168045044,-3.269768238067627,-4.383091449737549,-2.1280200481414795,-5.769078254699707,-2.0157971382141113,-0.05115606263279915,-0.7827892303466797,-2.01814603805542,-0.7615610361099243,-4.88661527633667,-1.0993207693099976,-1.9370125532150269,-2.6054697036743164,-4.763054847717285,-0.6369357705116272,-2.1820802688598633,-3.6672377586364746,-11.45315170288086,-3.599796772003174,-0.046964097768068314,-2.6266424655914307,-2.2148985862731934,-9.387943267822266,-7.695062637329102,-0.32404497265815735,-13.63813304901123,-2.4861717224121094,-1.8412293195724487,-1.793027639389038,-4.312119483947754,-6.794629096984863,-3.127570629119873,-1.048724889755249,-10.031847953796387,-3.7213587760925293,-0.5111039876937866,-5.742344856262207,-0.6040388345718384,-0.258836567401886,-11.514678001403809,-2.135671854019165,-2.4274821281433105,-1.9199167490005493,-3.438183307647705,-4.359144687652588,-7.150663375854492,-4.088846206665039,-1.1469639539718628,-1.7850189208984375,-4.587072372436523,-4.03653621673584,-3.3048155307769775,-4.217226982116699,-5.316999912261963,-6.248199462890625,-1.8734662532806396,-2.7215003967285156,-2.150892972946167,-0.01153832022100687,-1.1770520210266113,-1.5823966264724731,-5.393450736999512,-2.314021587371826,-8.744976043701172,-3.135997772216797,-3.1347968578338623,-1.7437100410461426,-2.076185703277588,-5.540759086608887,-3.4509334564208984,-1.247089147567749,-0.5903594493865967,-1.0093536376953125,-9.808045387268066,-1.917055368423462,-7.928602695465088,-3.752316474914551,-6.394966125488281,-1.2103266716003418,-2.918020248413086,-0.10298893600702286,-11.790082931518555,-1.3049378395080566,-3.590294122695923,-6.31539249420166,-2.1321494579315186,-0.002211745595559478,-1.0258837938308716,-2.185514450073242,-6.797455787658691,-5.28438663482666,-6.165347576141357,-2.2696003913879395,-8.078857421875,-1.8906844854354858,-2.793390989303589,-5.490406036376953,-1.3951696157455444,-11.99935531616211,-5.965693950653076,-1.4296164512634277,-7.255566596984863,-6.327967643737793,-9.7644624710083,-5.092337608337402,-4.454733848571777,-7.631986618041992,-2.5886945724487305,-6.9729461669921875,-2.6685194969177246,-1.9052033424377441,-0.045202530920505524,-0.5447935461997986,-8.900348663330078,-2.7466206550598145,-1.969204306602478,-9.25274658203125,-1.1917612552642822,-3.9008772373199463,-1.984078288078308,-6.868811130523682,-0.09858611971139908,-1.0099256038665771,-7.7979936599731445,-3.155747890472412,-8.754136085510254,-1.5917282104492188,-1.590170979499817,-0.8373681306838989,-4.586280822753906,-4.357884883880615,-2.169872283935547,-7.10923957824707,-6.700108528137207,-1.5973660945892334,-0.2948564291000366,-3.021773338317871,-2.252084732055664,-5.883697509765625,-3.7042906284332275,-5.145688056945801,-3.077763557434082,-1.151733160018921,-4.042393684387207,-1.1694226264953613,-1.9423247575759888,-7.484120845794678,-0.3584604561328888,-1.4061763286590576,-3.204638957977295,-6.8872389793396,-6.039560794830322,-3.86330509185791,-7.054738998413086,-2.888624668121338,-2.7627453804016113,-10.022449493408203,-0.21522866189479828,-8.81318187713623,-0.8549879193305969,-7.7977824211120605,-1.7552884817123413,-6.9809370040893555,-1.233609914779663,-0.5742105841636658,-5.285706996917725,-7.6541924476623535,-2.7897355556488037,-3.351857900619507,-1.6529098749160767,-2.9102323055267334,-0.5761648416519165,-8.176899909973145,-9.683972358703613,-10.987175941467285,-4.425904750823975,-0.3300049304962158,-6.685007572174072,-3.886586904525757,-5.659504413604736,-2.7079215049743652,-6.9492082595825195,-3.6214945316314697,-5.788566589355469,-2.5538713932037354,-5.153729438781738,-11.146583557128906,-6.457942008972168,-4.805428981781006,-0.8344119787216187,-10.511653900146484,-3.1658830642700195,-4.056483268737793,-3.1794984340667725,-3.0123963356018066,-0.003434000303968787,-12.866560935974121,-3.587737798690796,-1.2477004528045654,-2.5043294429779053,-2.5873770713806152,-1.9181462526321411,-3.1073193550109863,-1.2451395988464355,-1.8499451875686646,-1.7389854192733765,-2.374424695968628,-1.8550485372543335,-3.701503276824951,-5.628320693969727,-7.617840766906738,-0.571483314037323,-2.7192869186401367,-0.26908427476882935,-4.3939595222473145,-1.259324550628662,-5.062787055969238,-3.948906898498535,-0.729425847530365,-13.994866371154785,-14.223671913146973,-7.508281707763672,-7.750809669494629,-1.9262416362762451,-3.1433682441711426,-5.053383827209473,-8.397286415100098,-1.7281798124313354,-13.32927417755127,-2.734550952911377,-7.0226287841796875,-4.183746337890625,-5.488592624664307,-1.4651384353637695,-3.4879963397979736,-0.49116700887680054,-4.524519920349121,-8.136554718017578,-1.0092904567718506,-4.660487174987793,-4.789914131164551,-10.907078742980957,-4.384711742401123,-1.8599315881729126,-3.589599847793579,-4.775633811950684,-7.181646347045898,-4.346275329589844,-0.932983934879303,-3.1349101066589355,-3.9458115100860596,-1.8638019561767578,-0.05243513360619545,-0.7280094027519226,-4.866551399230957,-5.407751560211182,-14.85552978515625,-2.4500691890716553,-4.710573196411133,-1.3950353860855103,-0.2094191312789917,-2.7148749828338623,-4.6526899337768555,-7.1874918937683105,-1.4493004083633423,-2.889066696166992,-5.813836097717285,-2.1163113117218018,-1.4674113988876343,-2.9503297805786133,-2.0557000637054443,-1.3183889389038086,-0.5056212544441223,-3.014683246612549,-0.822799801826477,-7.6601057052612305,-4.191461563110352,-6.27751350402832,-2.911172866821289,-9.300002098083496,-1.7651914358139038,-4.201822280883789,-3.7572145462036133,-4.031837463378906,-8.339606285095215,-2.0532047748565674,-10.008934020996094,-1.8876948356628418,-5.829212188720703,-4.427117824554443,-7.37470817565918,-9.822811126708984,-3.0812010765075684,-8.960182189941406,-3.645644426345825,-8.059024810791016,-3.1896305084228516,-9.96102523803711,-2.1594345569610596,-10.671656608581543,-4.065796852111816,-3.599905490875244],"stop_reason":"stop","tokens":[11,1405,420,5117,6439,1457,198,791,1060,574,220,4468,16,13,358,574,220,845,1667,2362,13,358,574,6522,264,30010,3252,15438,32349,6574,304,264,42030,389,21972,596,4827,4892,45819,11,1405,358,6222,3691,323,1690,264,2294,4623,449,1063,220,1272,7941,11782,6980,13,3861,315,1124,574,16645,323,568,574,279,832,449,52021,315,6848,11,568,7263,3623,645,19737,79,598,369,1057,90398,11,7795,2442,14612,323,4018,75,727,7437,505,2646,1511,15926,323,1521,6366,11,3131,6437,11,78595,54499,449,30584,2320,316,9958,4028,1124,369,14128,49363,85059,13,1283,574,76534,323,15526,323,1047,15042,709,14624,311,32980,23139,13,1283,1047,1027,2212,323,1555,279,12047,315,4395,323,3686,568,2646,6612,14931,369,5678,13,1283,1436,12835,520,5678,1418,568,32627,520,813,1866,5435,323,52394,1274,6297,16243,813,2035,627,50554,596,7126,1047,264,2763,315,18198,323,1047,10791,459,19405,320,52566,665,59822,278,20000,11,358,1781,8,439,264,3995,893,13,1283,14264,709,304,813,6691,596,921,1900,6798,3838,1405,813,39284,11,3515,2163,279,506,8690,5590,11,12439,449,1077,4251,31717,329,4333,21630,449,3512,5859,58000,320,92109,292,7526,8,665,36022,369,1855,1023,279,13836,990,320,263,279,18341,430,3445,330,543,2574,1,439,584,682,3782,505,279,1890,11841,315,1057,21389,323,27007,4108,8,315,3794,9463,315,872,90838,1105,323,73021,13,5414,7126,2011,617,296,5412,291,1555,279,1667,3582,11,477,568,8434,956,617,13234,469,6329,3838,53324,279,75742,323,279,39679,4783,11,1606,1193,15369,323,264,6140,2586,3177,23415,555,264,33944,1732,311,4498,389,627,50554,323,358,1053,2559,520,813,50007,3321,520,3814,20149,34576,320,40,574,1193,2678,323,2744,28670,813,2162,27975,2978,61242,449,69861,12,68597,30278,311,3412,6941,1885,596,8,323,24797,13272,287,423,91591,12,10172,648,596,320,11708,528,263,859,272,9831,409,11540,383,93542,1759,8,2326,52166,408,819,320,40,19117,956,6755,1790,922,16870,3647,727,477,96415,304,1884,2919,705,320,30690,2877,6706,3935,73,325,14545,25111,1139,279,4671,89343,304,1884,2919,2103,11,539,279,59809,340,50554,3309,813,330,7678,336,2352,1,7493,922,9564,813,13378,24724,304,813,76875,1306,4848,4038,323,5108,1203,311,2033,279,8286,11,477,296,2518,1193,3116,477,4330,27474,1306,4330,1667,55154,1606,3131,389,701,23152,11,832,9221,264,3703,83985,627,1687,3131,14980,520,832,315,16645,596,3321,430,1047,264,75742,1684,11,25394,1268,330,14622,1,9822,7111,11,449,1377,15655,477,7474,1355,23581,388,55063,3770,4619,315,59002,477,6800,41168,63854,82,1437,2370,279,37401,627,23025,2919,9670,304,539,13915,2676,369,16645,1606,13378,10494,323,20149,11,34576,11,889,7020,430,433,574,28128,311,16603,30,1283,14264,304,12205,422,539,304,2890,11,6216,264,18537,11,264,4632,1080,30592,11,323,490,771,1441,15730,461,13,1283,9508,1093,264,220,1954,82,36330,7126,315,5030,9289,323,2876,279,9728,311,16376,79976,430,596,369,2771,627,47,6853,911,3394,3383,11851,21148,3131,934,6586,430,422,568,323,813,7200,330,6540,4575,276,359,8510,1,1051,63354,555,342,76299,552,279,3958,7752,1053,387,16070,555,23677,19037,13,16645,574,389,279,1023,14560,11,568,1071,568,1053,21735,872,802,325,11,1304,1124,264,3568,389,810,1972,12675,477,520,3325,636,1124,8667,709,311,813,31544,41010,9382,311,1776,731,279,35678,430,29496,1306,832,30191,11775,11,1690,11936,323,24142,430,20781,26968,279,64931,627,34004,3416,56747,374,38530,596,4731,1606,584,1205,29195,15220,323,2339,5352,7016,11,311,2586,4335,449,3446,11890,11,1524,369,2911,627,1271,19093,596,13051,85431,323,9259,3782,13544,449,18873,315,3827,16515,1306,902,16645,6244,264,1664,22015,3827,1773,347,1414,323,856,1176,3217,11890,264,364,73457,23148,6,3446,311,264,9063,3137,1501,320,1962,279,12152,11,315,3388,4390,16298,1053,2586,311,813,70864,1306,430,11,311,2610,369,8323,369,872,29658,1457,430,7281,2265,822,72093,1676,5281,14980,389,813,8356,2007,11,11497,279,55475,323,41544,279,1176,4208,315,279,2132,89785,627,3947,574,264,8792,323,264,4410,11799,11,323,1274,1317,291,311,1440,889,574,433,430,12860,279,1664,3967,27524,449,96350,11,28326,875,323,264,9501,4156,430,3287,956,2489,279,6211,315,279,3838,505,279,8761,11,1095,7636,10477,279,36760,13,9251,1047,11938,8041,369,264,330,17805,2955,1,28391,279,3492,30845,627,46,5730,36216,333,323,813,69217,34754,32594,17770,603,1234,49042,13,3082,11,16645,374,264,7126,719,568,374,1101,264,28799,1080,14504,889,3782,704,315,279,33044,1306,9099,20156,11,279,79434,2908,922,21939,9439,7795,13,362,5333,16645,1511,311,2457,3309,757,430,568,92840,1077,17659,9572,320,4908,55676,596,8,574,2216,264,22380,11,14918,1606,568,21423,10333,291,389,1124,13,5414,13219,3309,433,505,279,33552,315,1077,1450,11,1077,506,86003,10931,48907,704,1077,7493,315,5333,323,50252,13,1472,58003,1148,499,1518,11,364,9594,499,21935,55295,3300,323,5097,55295,6140,627,16366,10896,1071,279,58767,35967,24237,95869,813,45274,719,430,3287,956,2567,16645,505,16558,79574,660,31739,320,51844,31651,1543,596,19214,8,1606,6800,329,596,2766,6575,439,2403,682,21448,13,7281,2265,822,574,1101,18719,719,568,1047,16654,264,41100,1306,11039,369,16645,520,279,13378,19359,13,1283,574,279,5652,11996,315,33415,11890,6506,1050,67785,596,17563,627,40,6773,311,1505,279,20149,6166,320,708,311,6604,8,323,6818,26073,304,264,33894,279,2944,369,1455,315,433,13,358,4934,311,3237,279,70847,927,279,38748,2144,430,20149,272,1439,9572,439,433,596,1027,17033,430,433,596,1695,369,279,4851,13,2030,1148,922,1202,2515,389,279,8271,30,1115,374,1148,279,20149,6166,574,13,76093,4593,37645,574,279,3070,17293,7218,2978,11326,323,1364,3131,23415,927,264,4367,6710,315,17293,616,894,2073,92920,311,16645,323,264,3010,832,311,813,36271,323,814,527,389,1855,3885,1162,3596,2533,627,50554,7020,279,43957,323,568,7020,1268,3428,433,1436,733,13,4366,40197,689,596,520,279,4851,315,36707,323,358,2216,1541,956,1440,422,459,15155,1903,264,5780,6166,311,5155,279,18651,927,279,12700,3821,9364,449,459,13696,1093,8563,1611,45,8869,596,17781,45352,627,46830,889,358,1097,1314,1457,30,499,2351,13088,11,358,2846,4477,627,40,4250,3345,856,6548,1606,279,7493,430,84758,603,527,1884,430,584,842,709,11890,323,7231,499,459,56203,369,701,39375,311,559,359,502,6848,3445,430,499,4265,2503,1070,369,4207,389,842,20700,3060,12496,22901,477,6140,323,369,264,2771,2944,617,311,10552,2010,1022,1139,279,7693,11,902,358,1541,956,9518,1022,449,11,358,2846,14931,627,40,2846,14931,11,16645,320,76515,11,433,596,1461,8,706,5675,813,3979,24676,291,3021,323,374,279,2383,315,54108,596,20457,398,9546,13,1102,596,1193,1304,4510,1457,369,9337,5820,11,1606,439,55152,6267,11,1070,649,1193,387,832,1176,538,11410,247,236,9468,237,123,1732,2949,279,1890,4059,11,323,279,2800,315,603,649,1193,12265,627,13347,1070,4696,358,3021,433,4999,2366,18,25385,648,4487,28342,27643,1567,304,4783,198,35919,1919,30118,519,22743,19823,128001]}],"topk_prompt_logprobs":null,"type":"sample"}


==> Running examples/metrics_live.exs
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Sampled text: : 7-day rolling average of new deaths per day vs. daily new cases per day
According to our analysis the number of new COVID-19 deaths remains

=== Metrics Snapshot ===
Counters:
  tinkex_requests_success: 4
  tinkex_requests_total: 4

Latency (ms):
  count: 4
  mean: 375.44
  p50:  324.27
  p95:  627.32
  p99:  627.32

==> Running examples/telemetry_live.exs
Starting service client against https://tinker.thinkingmachines.dev/services/tinker-prod ...
Creating sampling client for meta-llama/Llama-3.1-8B ...

08:06:42.682 [info] HTTP post /api/v1/create_sampling_session start (pool=session base=https://tinker.thinkingmachines.dev/services/tinker-prod)

08:06:42.858 [info] HTTP post /api/v1/create_sampling_session ok in 175ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sending sample request ...

08:06:43.756 [info] HTTP post /api/v1/asample start (pool=sampling base=https://tinker.thinkingmachines.dev/services/tinker-prod)

08:06:44.093 [info] HTTP post /api/v1/asample ok in 336ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

08:06:44.103 [info] HTTP post /api/v1/retrieve_future start (pool=futures base=https://tinker.thinkingmachines.dev/services/tinker-prod)

08:06:44.573 [info] HTTP post /api/v1/retrieve_future ok in 470ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sampled sequences: [
  %Tinkex.Types.SampledSequence{
    tokens: [9842, 264, 3254, 11914, 922, 62137, 13, 9842, 264, 3254, 11914,
     922, 62137, 13, 9842, 264, 3254, 11914, 922, 62137, 13, 9842, 264, 3254,
     11914, 922, 62137, 13, 9842, 264, 3254, 11914],
    logprobs: [-3.8112008571624756, -0.2508602738380432, -0.08757783472537994,
     -0.005224148277193308, -0.01620127074420452, -0.26472416520118713,
     -1.0071816444396973, -0.0860191360116005, -4.627825692296028e-4,
     -0.0021759422961622477, -2.0346954988781363e-4, -6.026597693562508e-4,
     -5.87767455726862e-4, -0.1622651070356369, -0.029237089678645134,
     -1.0585224663373083e-4, -3.3182359766215086e-4, -7.068861305015162e-5,
     -1.5805903240107e-4, -1.4184899919200689e-4, -0.05803130567073822,
     -0.023145277053117752, -9.07141511561349e-5, -2.269487304147333e-4,
     -1.0918975021922961e-4, -1.6735584358684719e-4, -1.0918975021922961e-4,
     -0.04913678765296936, -0.01751362718641758, -5.9960475482512265e-5,
     -1.8785618885885924e-4, -3.5523738915799186e-5],
    stop_reason: :length
  }
]

08:06:44.597 [info] HTTP post /api/v1/telemetry start (pool=telemetry base=https://tinker.thinkingmachines.dev/services/tinker-prod)
Flushed telemetry; detach logger and exit.

08:06:44.802 [info] HTTP post /api/v1/telemetry ok in 204ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

==> Running examples/telemetry_reporter_demo.exs
==========================================
Tinkex Telemetry Reporter Demo
==========================================
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Model: meta-llama/Llama-3.1-8B


1. Starting ServiceClient and reporter...
   Reporter started: #PID<0.309.0>

2. Logging generic events...
   Logged: demo.started
   Logged events with different severity levels

3. Logging a non-fatal exception...
   Logged non-fatal exception: Simulated non-fatal error for demonstration

4. Performing live sampling (generates HTTP telemetry)...
   Sampling complete!
   Generated:  This book explains how to get started collecting telemetry data, and how to use...

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
Supported models (21 available):
  - deepseek-ai/DeepSeek-V3.1
  - deepseek-ai/DeepSeek-V3.1-Base
  - moonshotai/Kimi-K2-Thinking
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
  - Qwen/Qwen3-VL-235B-A22B-Instruct
  - Qwen/Qwen3-VL-30B-A3B-Instruct
  - openai/gpt-oss-120b
  - openai/gpt-oss-20b

Model names only: deepseek-ai/DeepSeek-V3.1, deepseek-ai/DeepSeek-V3.1-Base, moonshotai/Kimi-K2-Thinking, meta-llama/Llama-3.1-70B, meta-llama/Llama-3.1-8B, meta-llama/Llama-3.1-8B-Instruct, meta-llama/Llama-3.2-1B, meta-llama/Llama-3.2-3B, meta-llama/Llama-3.3-70B-Instruct, Qwen/Qwen3-235B-A22B-Instruct-2507, Qwen/Qwen3-30B-A3B, Qwen/Qwen3-30B-A3B-Base, Qwen/Qwen3-30B-A3B-Instruct-2507, Qwen/Qwen3-32B, Qwen/Qwen3-4B-Instruct-2507, Qwen/Qwen3-8B, Qwen/Qwen3-8B-Base, Qwen/Qwen3-VL-235B-A22B-Instruct, Qwen/Qwen3-VL-30B-A3B-Instruct, openai/gpt-oss-120b, openai/gpt-oss-20b

== Health check ==
Health: ok

== Compute prompt logprobs ==
Prompt: Hello from Tinkex!
Logprobs: [nil, -7.9737935066223145, -4.2407379150390625, -5.870687484741211, -6.7442121505737305, -11.39987564086914, -2.6687772274017334]

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
    Input:  %{metadata: %{version: "0.3.0", source: "tinkex"}, note: "Multipart demo from Tinkex"}
    Output: %{"metadata[source]" => "tinkex", "metadata[version]" => "0.3.0", "note" => "Multipart demo from Tinkex"}

[4] Multipart Encoding:
    Content-Type: multipart/form-data; boundary=d9a502d27658cf517f63016cce13a712
    Body size: 516 bytes

[5] Multipart Body Preview:
    --d9a502d27658cf517f63016cce13a712
    Content-Disposition: form-data; name="metadata[source]"

    tinkex
    --d9a502d27658cf517f63016cce13a712
    Content-Disposition: form-data; name="metadata[version]"

    0.3.0
    --d9a502d27658cf517f63016cce13a712
    Content-Disposition: form-data; name="note"

    Multipart demo from Tinkex
    --d9a502d27658cf517f63016cce13a712
    Content-Disposition: form-data; name="file"; filename="sample_upload.bin"
    Content-Type: application/octet-stream

    hello

    --d9a502d27658cf517f63016cce13a712--

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
[ok] optim_step metrics: %{"unclipped_grad_l2:mean" => 13454.48828125}
[done] AdamParams and byte-based chunking demo complete

==> Running examples/llama3_tokenizer_override_live.exs
Tokenizer ID: thinkingmachineslabinc/meta-llama-3-tokenizer
Encoded prompt token IDs (13): [128000, 80853, 71015, 445, 81101, 12, 18, 47058, 2882, 304, 832, 11914, 13]
Decoded first sequence:  More...

#include <llama3.h>

## Detailed Description

Demonstrate L

==> Running examples/queue_reasons_and_sampling_throttling.exs
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: Hello from throttling + queue reasons!
----------------------------------------


08:07:12.189 [info] The function passed as a handler with ID "queue-reasons-demo-9858" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] demonstrating server-preferred reason via QueueStateLogger
[info] simulating backoff to exercise throttled dispatch + byte penalty

08:07:12.206 [warning] Sampling is paused for a96e4c58-fdca-57be-af3b-93cc858e299f:sample:0. Reason: server says: running short on capacity (demo)
[info] dispatch acquisition order (penalized bytes): one at -576460750853
[info] estimated prompt bytes: 90
[step] running live sample...
[ok] sample returned 1 sequence(s)
[done] queue reasons + throttling demo complete

==> Running examples/multimodal_resume_and_cleanup.exs
== Multimodal sampling (image + text)
Using vision-capable model: Qwen/Qwen3-VL-30B-A3B-Instruct
Using image: examples/assets/vision_sample.png (format=png expected_tokens=nil)
Sampled 1 sequence(s) with image + text.
- tokens: [7, 16, 11, 16, 8, 311, 320, 20]

== Optimizer resume via ServiceClient helper
Restoring weights + optimizer from tinker://7894c2a1-ae93-5ac9-bb77-5eff19b82b14:train:1/weights/recovery-live-2 ...
Training client ready. Unloading...

CLI multi-delete (single confirmation):
  tinkex checkpoint delete tinker://run-1/weights/0001 tinker://run-2/weights/0002 --yes


==> Running examples/training_persistence_live.exs
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Checkpoint name: demo-checkpoint-1765649250
Saved checkpoint to tinker://700071be-b6d8-5e4e-a158-83d5dac63463:train:0/weights/demo-checkpoint-1765649250
Reloaded checkpoint with optimizer state
Created a fresh training client from checkpoint: #PID<0.335.0>

==> Running examples/checkpoint_multi_delete_live.exs
Saved checkpoint multi-delete-1765649273-a: tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-a
Saved checkpoint multi-delete-1765649273-b: tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-b
Cached default checkpoint path at tmp/checkpoints/default.path: tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-a

Deleting 2 checkpoints with one confirmation...
Deleting 1/2: tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-a
Deleted tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-a
Deleting 2/2: tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-b
Deleted tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-b

Multi-delete summary:
result: %{
  command: :checkpoint,
  action: :delete,
  failed: 0,
  paths: ["tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-a",
   "tinker://21273581-a3e9-5016-acac-bd2e1ae188d7:train:0/weights/multi-delete-1765649273-b"],
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

08:08:27.459 [info] The function passed as a handler with ID "recovery-demo-4034" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
1) Seeded checkpoint tinker://demo-run-3970/weights/0001
2) Simulated corruption flag on demo-run-3970
3) Recovery succeeded from tinker://demo-run-3970/weights/0001 -> #PID<0.313.0>
4) Checkpoints processed: tinker://demo-run-3970/weights/0001, tinker://demo-run-3970/weights/0002
Final run status: %{
  clients: [#PID<0.313.0>],
  completed: [
    %Tinkex.Types.Checkpoint{
      checkpoint_id: "cp-0001",
      checkpoint_type: "weights",
      tinker_path: "tinker://demo-run-3970/weights/0001",
      training_run_id: "demo-run-3970",
      size_bytes: nil,
      public: false,
      time: ~U[2025-12-13 18:08:27.453803Z]
    },
    %Tinkex.Types.Checkpoint{
      checkpoint_id: "cp-0002",
      checkpoint_type: "weights",
      tinker_path: "tinker://demo-run-3970/weights/0002",
      training_run_id: "demo-run-3970",
      size_bytes: nil,
      public: false,
      time: ~U[2025-12-13 18:08:27.456865Z]
    }
  ],
  last_checkpoint: "tinker://demo-run-3970/weights/0002",
  corrupted?: false
}

==> Running examples/recovery_live_injected.exs
Saved checkpoint tinker://9e89b426-4738-51bf-a5f8-a70b57a66250:train:0/weights/recovery-live-1
Recovery callback: old=#PID<0.313.0> new=#PID<0.335.0> cp=tinker://9e89b426-4738-51bf-a5f8-a70b57a66250:train:0/weights/recovery-live-1
Saved checkpoint tinker://9e89b426-4738-51bf-a5f8-a70b57a66250:train:1/weights/recovery-live-2
Recovered from tinker://9e89b426-4738-51bf-a5f8-a70b57a66250:train:0/weights/recovery-live-1
Second checkpoint saved: tinker://9e89b426-4738-51bf-a5f8-a70b57a66250:train:1/weights/recovery-live-2

==> Running examples/kimi_k2_sampling_live.exs
== Kimi K2 tokenization (tiktoken_ex)
Model: moonshotai/Kimi-K2-Thinking
Prompt: "Say hi"
Token IDs (first 32): [71079, 20910] (2 total)
Round-trip decode: "Say hi"

== Live sampling
Sampling 1 sequence(s) from moonshotai/Kimi-K2-Thinking ...
Received 1 sequence(s):
Sample 1:  to your mother for me, okay?"
He nods. "I will. And tell your dad that the Feds are still sniffing around. They were

==> Running examples/model_info_and_unload.exs
[tinkex] base_url=https://tinker.thinkingmachines.dev/services/tinker-prod
[tinkex] base_model=meta-llama/Llama-3.1-8B
[tinkex] created session_id=6ff9cc40-35bf-5aa0-ae5c-7d299401895e
[tinkex] poll #1 create_model request_id=6ff9cc40-35bf-5aa0-ae5c-7d299401895e:train:0:0
[tinkex] created model_id=6ff9cc40-35bf-5aa0-ae5c-7d299401895e:train:0
[tinkex] model_id=6ff9cc40-35bf-5aa0-ae5c-7d299401895e:train:0
- model_name: meta-llama/Llama-3.1-8B
- arch: unknown
- tokenizer_id: thinkingmachineslabinc/meta-llama-3-tokenizer
- is_lora: true
- lora_rank: 32
[tinkex] unload_model
[tinkex] unload failed: [api_status (404)] HTTP 404 status=404
[tinkex] error data: %{"detail" => "Not Found"}
````
