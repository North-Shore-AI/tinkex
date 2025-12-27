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

==> Running examples/sampling_basic.exs [2025-12-26 22:51:11 HST]
Compiling 12 files (.ex)
Compiling 5 files (.ex)
Generated tinkex app
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Received 1 sequence(s):
Sample 1:  We are a family owned and operated business built on a passion for pets and a commitment to excellence. We have been in business since 2011 and have a strong reputation for high quality pet products and outstanding service. We strive to make our customers feel like family, and we can't wait to show you what we’re
==> Finished examples/sampling_basic.exs [2025-12-26 22:51:16 HST | 00:05]

==> Running examples/training_loop.exs [2025-12-26 22:51:16 HST]
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: 'Fine-tuning sample prompt'
Sample after training: false

[step] creating ServiceClient...
[step] creating ServiceClient completed in 350ms
[step] creating TrainingClient (LoRA rank=16)...
[note] this may take 30-120s on first run (model loading)...
[step] creating TrainingClient (LoRA rank=16) completed in 246ms
[step] building model input...
[step] got 6 tokens: [128000, 64816, 2442, 38302, 6205, 10137]
[step] building model input completed in 1.5s
[step] running forward_backward...
[step] forward_backward completed in 1.66s
[metrics] forward_backward: %{"clock_cycle:unique" => 1477253.0, "loss:sum" => 85.29592895507812}
[step] running optim_step...
[step] optim_step completed in 899ms
[metrics] optim_step: (none - optimizer doesn't compute metrics)
[step] saving weights for sampler...
[step] save_weights_for_sampler completed in 2.21s
[result] save_weights: %{"path" => "tinker://79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0/sampler_weights/sampler-weights", "sampling_session_id" => nil, "size_bytes" => nil, "type" => "save_weights_for_sampler"}

[done] Training loop finished in 4.78s
==> Finished examples/training_loop.exs [2025-12-26 22:51:24 HST | 00:08]

==> Running examples/custom_loss_training.exs [2025-12-26 22:51:24 HST]
================================================================================
Custom Loss Training (Live)
================================================================================

Base URL : https://tinker.thinkingmachines.dev/services/tinker-prod
Base model : meta-llama/Llama-3.1-8B

Creating training client...
Preparing training datum for prompt: Name three planets in the solar system.

Running forward_backward_custom...
Custom loss completed in 6144 ms

Running optim_step...
optim_step succeeded.

=== ForwardBackwardOutput ===
loss_fn_output_type: CrossEntropyLossReturn
metrics: %{"clock_cycle:unique" => 1477266.0, "custom_perplexity" => 201762.703125, "loss:sum" => 12.214847564697266}
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
==> Finished examples/custom_loss_training.exs [2025-12-26 22:51:33 HST | 00:09]

==> Running examples/forward_inference.exs [2025-12-26 22:51:33 HST]
=== Forward Inference Example ===
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: Hello from forward inference!

Creating training client...
Building model input from prompt...
Token count: 6

Running forward pass (inference only, no backward)...

Forward pass completed in 14991ms
Output type: CrossEntropyLossReturn
Metrics: %{"clock_cycle:unique" => 5414551.0, "loss:sum" => 71.73094177246094}
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
==> Finished examples/forward_inference.exs [2025-12-26 22:51:53 HST | 00:20]

==> Running examples/structured_regularizers.exs [2025-12-26 22:51:53 HST]
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
  Parallel: 785 μs
  Sequential: 454 μs
  Results match: true

--- 8. Async Regularizers (for I/O-bound operations) ---

Created async regularizer (simulates external API call)
Async regularizer result:
  loss_total: 1.1016
  async_external_validation contribution: 0.0216
  Execution time: 11130 μs

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


22:51:53.987 [info] The function passed as a handler with ID "tinkex-regularizer-22" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
Attached telemetry handler: tinkex-regularizer-22

Running pipeline with telemetry (watch for log output):

22:51:53.992 [info] Custom loss starting: regularizers=1 track_grad_norms=true

22:51:53.993 [info] Regularizer l1_sparsity starting

22:51:53.993 [info] Regularizer l1_sparsity value=10.8 contribution=0.108 in 0ms grad_norm=3.1623

22:51:53.993 [info] Custom loss computed in 0ms total=1.188 regularizer_total=0.108 regularizers=1
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

==> Finished examples/structured_regularizers.exs [2025-12-26 22:51:54 HST | 00:01]

==> Running examples/structured_regularizers_live.exs [2025-12-26 22:51:54 HST]
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

Completed in 6992ms

=== Metrics ===
base_nll: 12.02071
clock_cycle:unique: 1477279.0
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
==> Finished examples/structured_regularizers_live.exs [2025-12-26 22:52:03 HST | 00:09]

==> Running examples/sessions_management.exs [2025-12-26 22:52:03 HST]
=== Tinkex Session Management Example ===

Starting ServiceClient...
Creating RestClient...

--- Listing Sessions ---
Found 10 sessions:
  • f8d35714-fc00-5a89-9663-f273ef6f5084
  • 182029f2-a7b5-506c-a9b3-d6bddab03be8
  • f3909fbd-b422-5c2b-9ec3-07a6f2af032d
  • 8def6eef-968c-55fa-ab0d-b61a71b9dbb9
  • 79db3d29-8bda-515f-a3c3-f9c1a8806642
  • a34b0b0c-4890-5026-8e95-0bbfcb580488
  • 87133dfa-e4b5-5d6f-bc6b-fbaa0302c99a
  • 562111c5-00b8-591a-992f-d5951b0c69df
  • 6b65fe15-50a4-5378-8cd1-560d415aa1b2
  • 5f7a66a7-5ca0-5b05-bbcd-7f283f2946a6

--- Session Details: f8d35714-fc00-5a89-9663-f273ef6f5084 ---
Training Runs: 0
Samplers: 0

=== Example Complete ===
==> Finished examples/sessions_management.exs [2025-12-26 22:52:05 HST | 00:02]

==> Running examples/checkpoints_management.exs [2025-12-26 22:52:05 HST]
=== Tinkex Checkpoint Management Example ===

--- All User Checkpoints ---
Found 20 of 225 checkpoints:

  sampler_weights/sampler-weights
    Path: tinker://79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-27 08:51:24.966034Z

  weights/recovery-live-2
    Path: tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 05:39:53.893145Z

  weights/recovery-live-1
    Path: tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 05:39:33.868033Z

  weights/demo-checkpoint-1766813722
    Path: tinker://7dacb44e-8314-5b15-a1ff-f86f7f75d17c:train:0/weights/demo-checkpoint-1766813722
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 05:35:36.226629Z

  weights/async_demo_checkpoint
    Path: tinker://5062a5d4-c072-5ac5-b596-9d0dfc782dad:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-27 05:34:17.457968Z

  sampler_weights/sampler-weights
    Path: tinker://2d57b556-4961-5e2d-8ae8-2d1354d016ca:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-27 05:32:55.744841Z

  weights/recovery-live-2
    Path: tinker://d15e3de0-3435-5c3f-8aa2-be0f93fa6ebb:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:37:18.082789Z

  weights/recovery-live-1
    Path: tinker://d15e3de0-3435-5c3f-8aa2-be0f93fa6ebb:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:36:57.015857Z

  weights/recovery-live-2
    Path: tinker://7df8f4be-77ab-5046-99ef-690c1cf79b53:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:35:46.650401Z

  weights/recovery-live-1
    Path: tinker://7df8f4be-77ab-5046-99ef-690c1cf79b53:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:35:35.343873Z

  weights/demo-checkpoint-1766795675
    Path: tinker://05a835f8-911f-5e54-bf9e-c5c7401955d8:train:0/weights/demo-checkpoint-1766795675
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:34:45.935964Z

  weights/async_demo_checkpoint
    Path: tinker://bc35896c-af8d-5a51-9200-3d1e8fa11bfe:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-27 00:33:05.711501Z

  sampler_weights/sampler-weights
    Path: tinker://0e9a8a1a-df5a-5df1-84ef-a844dd15a120:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-27 00:31:53.793967Z

  weights/async_demo_checkpoint
    Path: tinker://10c70329-f588-5d04-baba-a0070dcd2a57:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 23:53:39.734980Z

  sampler_weights/sampler-weights
    Path: tinker://a3a1e210-f9e5-55ad-9e8c-8244c4b864b0:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 23:51:36.609844Z

  weights/recovery-live-2
    Path: tinker://6b78cb4c-dc4b-5496-885d-52af33cc386b:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:46:41.213283Z

  weights/recovery-live-1
    Path: tinker://6b78cb4c-dc4b-5496-885d-52af33cc386b:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:46:30.143639Z

  weights/demo-checkpoint-1766792404
    Path: tinker://2608821d-9c30-572d-8e1d-86d88d573d40:train:0/weights/demo-checkpoint-1766792404
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:40:44.706048Z

  weights/demo-checkpoint-1766792226
    Path: tinker://24ab644a-a546-5fa9-a3d2-bbe4e95c2360:train:0/weights/demo-checkpoint-1766792226
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:37:40.360040Z

  weights/async_demo_checkpoint
    Path: tinker://891164d3-4ace-58dd-8791-f0cbce00a1d2:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 23:30:58.958213Z


--- All User Checkpoints (paginated) ---
Fetched 50 (225 total)
  sampler_weights/sampler-weights
    Path: tinker://79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-27 08:51:24.966034Z

  weights/recovery-live-2
    Path: tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 05:39:53.893145Z

  weights/recovery-live-1
    Path: tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 05:39:33.868033Z

  weights/demo-checkpoint-1766813722
    Path: tinker://7dacb44e-8314-5b15-a1ff-f86f7f75d17c:train:0/weights/demo-checkpoint-1766813722
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 05:35:36.226629Z

  weights/async_demo_checkpoint
    Path: tinker://5062a5d4-c072-5ac5-b596-9d0dfc782dad:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-27 05:34:17.457968Z

  sampler_weights/sampler-weights
    Path: tinker://2d57b556-4961-5e2d-8ae8-2d1354d016ca:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-27 05:32:55.744841Z

  weights/recovery-live-2
    Path: tinker://d15e3de0-3435-5c3f-8aa2-be0f93fa6ebb:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:37:18.082789Z

  weights/recovery-live-1
    Path: tinker://d15e3de0-3435-5c3f-8aa2-be0f93fa6ebb:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:36:57.015857Z

  weights/recovery-live-2
    Path: tinker://7df8f4be-77ab-5046-99ef-690c1cf79b53:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:35:46.650401Z

  weights/recovery-live-1
    Path: tinker://7df8f4be-77ab-5046-99ef-690c1cf79b53:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:35:35.343873Z

  weights/demo-checkpoint-1766795675
    Path: tinker://05a835f8-911f-5e54-bf9e-c5c7401955d8:train:0/weights/demo-checkpoint-1766795675
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-27 00:34:45.935964Z

  weights/async_demo_checkpoint
    Path: tinker://bc35896c-af8d-5a51-9200-3d1e8fa11bfe:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-27 00:33:05.711501Z

  sampler_weights/sampler-weights
    Path: tinker://0e9a8a1a-df5a-5df1-84ef-a844dd15a120:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-27 00:31:53.793967Z

  weights/async_demo_checkpoint
    Path: tinker://10c70329-f588-5d04-baba-a0070dcd2a57:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 23:53:39.734980Z

  sampler_weights/sampler-weights
    Path: tinker://a3a1e210-f9e5-55ad-9e8c-8244c4b864b0:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 23:51:36.609844Z

  weights/recovery-live-2
    Path: tinker://6b78cb4c-dc4b-5496-885d-52af33cc386b:train:1/weights/recovery-live-2
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:46:41.213283Z

  weights/recovery-live-1
    Path: tinker://6b78cb4c-dc4b-5496-885d-52af33cc386b:train:0/weights/recovery-live-1
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:46:30.143639Z

  weights/demo-checkpoint-1766792404
    Path: tinker://2608821d-9c30-572d-8e1d-86d88d573d40:train:0/weights/demo-checkpoint-1766792404
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:40:44.706048Z

  weights/demo-checkpoint-1766792226
    Path: tinker://24ab644a-a546-5fa9-a3d2-bbe4e95c2360:train:0/weights/demo-checkpoint-1766792226
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:37:40.360040Z

  weights/async_demo_checkpoint
    Path: tinker://891164d3-4ace-58dd-8791-f0cbce00a1d2:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 23:30:58.958213Z

  sampler_weights/sampler-weights
    Path: tinker://cc2f5859-cb01-5d2d-96d2-d3bddcb69e0d:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 23:29:22.399260Z

  weights/demo-checkpoint-1766791741
    Path: tinker://f5d393e7-6c78-5e21-a0d6-320b278181c4:train:0/weights/demo-checkpoint-1766791741
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 23:29:14.265464Z

  weights/demo-checkpoint-1766789480
    Path: tinker://1008d5e4-f4f8-56b3-8c43-efce7c1e1a55:train:0/weights/demo-checkpoint-1766789480
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 22:51:28.351800Z

  weights/async_demo_checkpoint
    Path: tinker://16dd1dc2-1649-5125-9781-4a43845076be:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 22:50:30.925978Z

  sampler_weights/sampler-weights
    Path: tinker://509535c6-37e3-5807-84af-e5d52c511ecb:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 22:49:31.009307Z

  weights/demo-checkpoint-1766788810
    Path: tinker://96861bd1-2446-5be2-b04f-351978173759:train:0/weights/demo-checkpoint-1766788810
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 22:40:23.882777Z

  weights/async_demo_checkpoint
    Path: tinker://94341190-8bc5-551d-af40-bac044c4f8b1:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 22:39:20.746580Z

  sampler_weights/sampler-weights
    Path: tinker://fa707edb-b377-5b65-8099-791b5ebc03a3:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 22:37:50.904815Z

  weights/demo-checkpoint-1766787850
    Path: tinker://38d913a6-fec9-599d-88c7-88085ab7916d:train:0/weights/demo-checkpoint-1766787850
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 22:24:22.346649Z

  weights/demo-checkpoint-1766787838
    Path: tinker://17392615-1223-5aed-8b5d-97aab19546cd:train:0/weights/demo-checkpoint-1766787838
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 22:24:15.703267Z

  weights/demo-checkpoint-1766787651
    Path: tinker://8400dc39-62cc-566c-9c2a-0d71fd698bfe:train:0/weights/demo-checkpoint-1766787651
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 22:20:56.684205Z

  weights/async_demo_checkpoint
    Path: tinker://0fba80d0-b3d5-526c-802a-a84bb80cbaf1:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 22:19:51.111184Z

  sampler_weights/sampler-weights
    Path: tinker://22bdb539-f88d-530e-9743-eb3c8db5d68d:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 22:18:00.289799Z

  weights/demo-checkpoint-1766785649
    Path: tinker://b9ad4782-6cd7-567e-a479-177545a2a7a8:train:0/weights/demo-checkpoint-1766785649
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 21:48:05.060665Z

  weights/demo-checkpoint-1766785351
    Path: tinker://6019cf25-fc76-5801-87d9-1bc97bd6aa99:train:0/weights/demo-checkpoint-1766785351
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 21:42:35.603907Z

  weights/demo-checkpoint-1766785247
    Path: tinker://97e9bb38-67dd-56b3-8830-3a4225de8453:train:0/weights/demo-checkpoint-1766785247
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 21:41:01.471198Z

  weights/demo-checkpoint-1766785253
    Path: tinker://b8a7b4e4-9650-5e00-b651-6c1d765dea16:train:0/weights/demo-checkpoint-1766785253
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 21:40:59.658213Z

  weights/demo-checkpoint-1766784917
    Path: tinker://0dcbe124-3e12-5e0a-b46e-692de2e09e9c:train:0/weights/demo-checkpoint-1766784917
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 21:35:34.869897Z

  weights/demo-checkpoint-1766784888
    Path: tinker://52b659bf-425b-5b31-956b-2f5f2ff95afe:train:0/weights/demo-checkpoint-1766784888
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 21:34:56.061253Z

  weights/demo-checkpoint-1766784593
    Path: tinker://861a669e-bf2e-5bf3-8a4a-5f08cb6aadb5:train:0/weights/demo-checkpoint-1766784593
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 21:30:01.933712Z

  weights/async_demo_checkpoint
    Path: tinker://9e7b8fd6-eae2-5788-babc-90a8c1a834f9:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 21:28:47.520398Z

  sampler_weights/sampler-weights
    Path: tinker://4644f0fd-ce5e-502a-bf8a-273970209032:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 21:26:54.577082Z

  weights/async_demo_checkpoint
    Path: tinker://f5de7abe-2cdc-598c-a61f-88824727a30c:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 21:25:07.126598Z

  weights/async_demo_checkpoint
    Path: tinker://488d0c30-6473-5e4d-8b9b-50524ddbc7b7:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 21:24:18.170169Z

  weights/async_demo_checkpoint
    Path: tinker://7c68f5b2-631d-5c62-8740-8b753888df28:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 15:25:49.829614Z

  sampler_weights/sampler-weights
    Path: tinker://44cdce08-c565-5dab-a917-058f1b54ed1a:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 15:21:37.657041Z

  weights/async_demo_checkpoint
    Path: tinker://799fb44a-3ec8-5e26-bcda-8d79d1cbacf0:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 08:27:35.710834Z

  sampler_weights/sampler-weights
    Path: tinker://3e05316f-ae98-5977-8e26-fabf23bf4a53:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 08:26:16.325584Z

  weights/async_demo_checkpoint
    Path: tinker://4eb01b53-102d-5dcb-98fd-de93e0f3c67e:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 08:23:27.692193Z

  sampler_weights/sampler-weights
    Path: tinker://3dc81e9c-0a80-5228-8b3a-e6abae6843a0:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 08:20:26.096096Z

Fetched 50 (225 total)
  weights/demo-checkpoint-1766730052
    Path: tinker://dbd357fc-f197-59c1-9ebf-d39d9e8dd07c:train:0/weights/demo-checkpoint-1766730052
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 06:21:02.209024Z

  weights/demo-checkpoint-1766729859
    Path: tinker://10d48b85-fb50-5990-9545-89237de1bc47:train:0/weights/demo-checkpoint-1766729859
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 06:17:51.985937Z

  weights/async_demo_checkpoint
    Path: tinker://120858d7-a500-5b34-b0e6-a1f3459282e7:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 06:15:18.061063Z

  sampler_weights/sampler-weights
    Path: tinker://fe6ed022-b223-5db7-9aca-b9be772eae95:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 06:13:53.977848Z

  sampler_weights/sampler-weights
    Path: tinker://7cb62e42-07fb-5ee6-ba05-fe21356fb71a:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 06:13:16.468198Z

  sampler_weights/sampler-weights
    Path: tinker://4ba054ae-6764-5886-acbd-3a88d3a0919f:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 06:12:53.060241Z

  weights/async_demo_checkpoint
    Path: tinker://78334590-5eda-5ff3-8863-69c3adea0b9e:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 06:11:02.430602Z

  weights/async_demo_checkpoint
    Path: tinker://67d4acfa-cfdf-5166-a91f-b88d7d7fcd2a:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 06:10:59.258711Z

  weights/async_demo_checkpoint
    Path: tinker://0efe4627-c27e-592c-93c3-8c7c066889f0:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 06:09:42.253710Z

  weights/async_demo_checkpoint
    Path: tinker://02f4f496-6382-5a08-addc-7d48d76251fb:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 06:08:31.400453Z

  sampler_weights/sampler-weights
    Path: tinker://05aa6deb-127e-5651-828d-c601a89d92e7:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 06:07:31.090866Z

  sampler_weights/sampler-weights
    Path: tinker://70ad1b55-9aa8-5fc0-bee7-60322a90523a:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 06:06:54.166066Z

  weights/demo-checkpoint-1766728772
    Path: tinker://5bd4d444-1c7a-5ae9-a700-6e446844a1f5:train:0/weights/demo-checkpoint-1766728772
    Type: training
    Size: 252.3 MB
    Public: false
    Created: 2025-12-26 05:59:44.256915Z

  weights/async_demo_checkpoint
    Path: tinker://c13a0019-2c62-5b00-a589-9fe821f6759d:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-26 05:58:08.253149Z

  sampler_weights/sampler-weights
    Path: tinker://658cf83c-3c06-5637-bb98-ba3cda4d3e79:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-26 05:56:52.205183Z

  sampler_weights/final_weights
    Path: tinker://8537193d-7420-55d0-9385-b0a1c946e8bf:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:59:05.883441Z

  sampler_weights/final
    Path: tinker://6675ab84-bddc-570a-841c-6431654e5762:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:58:45.175700Z

  weights/final
    Path: tinker://6675ab84-bddc-570a-841c-6431654e5762:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 22:58:40.582593Z

  sampler_weights/final
    Path: tinker://5ce450c9-b794-5d5b-bc74-8345434508dc:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:57:40.671199Z

  weights/final
    Path: tinker://5ce450c9-b794-5d5b-bc74-8345434508dc:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 22:57:34.374430Z

  sampler_weights/final_weights
    Path: tinker://6dcd923d-90fe-5270-ba05-7e7907a48ad5:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:50:14.830815Z

  sampler_weights/final
    Path: tinker://c3791f31-4a51-5373-a89e-0a5f69b9aaef:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:49:58.682972Z

  weights/final
    Path: tinker://c3791f31-4a51-5373-a89e-0a5f69b9aaef:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 22:49:54.160373Z

  sampler_weights/final_weights
    Path: tinker://0ff85be5-4290-5c03-bb2d-7496cfdcca03:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:35:44.544923Z

  sampler_weights/final
    Path: tinker://f461b62d-31ac-5c96-a6d2-67b59b1a9ce5:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:35:26.800836Z

  weights/final
    Path: tinker://f461b62d-31ac-5c96-a6d2-67b59b1a9ce5:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 22:35:23.118483Z

  sampler_weights/final_weights
    Path: tinker://39676dfe-a61d-53b3-a33f-41a016f1e589:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:16:32.222251Z

  sampler_weights/final
    Path: tinker://b5e6a735-ee55-5732-ab50-325939c041f9:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:13:40.111677Z

  weights/final
    Path: tinker://b5e6a735-ee55-5732-ab50-325939c041f9:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 22:13:12.271708Z

  sampler_weights/final_weights
    Path: tinker://5adae7c6-2920-5eaa-9fc0-be8e4590722d:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:10:07.273375Z

  sampler_weights/final
    Path: tinker://4643276f-9f20-5cd1-920d-f4125d7e12cf:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 22:09:53.274468Z

  weights/final
    Path: tinker://4643276f-9f20-5cd1-920d-f4125d7e12cf:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 22:09:49.712668Z

  sampler_weights/final_weights
    Path: tinker://87947c6f-3448-5876-831c-93e8aee878d4:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 21:01:26.745171Z

  sampler_weights/final
    Path: tinker://05403950-33cb-5b57-b202-b5a43d6ccc86:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 21:00:17.847659Z

  weights/final
    Path: tinker://05403950-33cb-5b57-b202-b5a43d6ccc86:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 21:00:13.120445Z

  sampler_weights/final_weights
    Path: tinker://e6bcd454-b7cf-57fb-b1c2-984c6428f2c4:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 20:59:33.930582Z

  sampler_weights/final
    Path: tinker://d7eedec0-5135-58b9-8637-9c7a63309407:train:0/sampler_weights/final
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 20:58:48.050098Z

  weights/final
    Path: tinker://d7eedec0-5135-58b9-8637-9c7a63309407:train:0/weights/final
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 20:58:43.272161Z

  sampler_weights/000040
    Path: tinker://7c640925-f5ea-5961-af43-3958de870f80:train:0/sampler_weights/000040
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 20:56:51.487233Z

  weights/000040
    Path: tinker://7c640925-f5ea-5961-af43-3958de870f80:train:0/weights/000040
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 20:56:48.657136Z

  weights/000020
    Path: tinker://7c640925-f5ea-5961-af43-3958de870f80:train:0/weights/000020
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 20:56:07.598637Z

  sampler_weights/000020
    Path: tinker://7c640925-f5ea-5961-af43-3958de870f80:train:0/sampler_weights/000020
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 20:56:04.724378Z

  sampler_weights/final_weights
    Path: tinker://9d93a036-5490-5518-bdcd-204f824ec998:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 19:53:14.044010Z

  weights/step_000059
    Path: tinker://9d93a036-5490-5518-bdcd-204f824ec998:train:0/weights/step_000059
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 19:52:05.138163Z

  weights/step_000039
    Path: tinker://9d93a036-5490-5518-bdcd-204f824ec998:train:0/weights/step_000039
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 19:50:42.129565Z

  weights/step_000019
    Path: tinker://9d93a036-5490-5518-bdcd-204f824ec998:train:0/weights/step_000019
    Type: training
    Size: 1008.7 MB
    Public: false
    Created: 2025-12-24 19:49:15.513306Z

  sampler_weights/final_weights
    Path: tinker://ab35ff6b-112b-52f2-990d-e61e3a7944dd:train:0/sampler_weights/final_weights
    Type: sampler
    Size: 336.2 MB
    Public: false
    Created: 2025-12-24 09:19:12.271299Z

  weights/recovery-live-2
    Path: tinker://7dd71ed9-6710-545e-b53a-a11b06072f9c:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 05:22:04.123822Z

  weights/recovery-live-1
    Path: tinker://7dd71ed9-6710-545e-b53a-a11b06072f9c:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 05:21:44.011093Z

  weights/demo-checkpoint-1765776020
    Path: tinker://dea2c1d0-84c4-50b9-ac75-dcac8d28ae83:train:0/weights/demo-checkpoint-1765776020
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 05:20:36.690700Z

Fetched 50 (225 total)
  weights/async_demo_checkpoint
    Path: tinker://679b8336-c230-5339-a88a-2441cf1471ff:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-15 05:19:06.922166Z

  sampler_weights/sampler-weights
    Path: tinker://eeb21593-19bc-56bf-9c01-df4c677fa5c8:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-15 05:17:35.679145Z

  weights/recovery-live-2
    Path: tinker://37f9ab42-b333-5a89-84c6-156a3106265f:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 04:39:03.219096Z

  weights/recovery-live-1
    Path: tinker://37f9ab42-b333-5a89-84c6-156a3106265f:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 04:38:52.478217Z

  weights/demo-checkpoint-1765773452
    Path: tinker://c25b668d-0399-53e5-9652-b4a57b92bfa7:train:0/weights/demo-checkpoint-1765773452
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 04:37:49.561786Z

  weights/async_demo_checkpoint
    Path: tinker://b27c0aab-a1c3-56d8-9cd0-ae6a05055bbc:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-15 04:36:25.701150Z

  sampler_weights/sampler-weights
    Path: tinker://9c035be3-7675-5324-a74b-f32128ea3da5:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-15 04:35:21.888455Z

  weights/multi-delete-1765772555-b
    Path: tinker://d334da2f-e1a2-5cea-a962-bbda7a9cd3ac:train:0/weights/multi-delete-1765772555-b
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 04:25:01.768171Z

  weights/multi-delete-1765772555-a
    Path: tinker://d334da2f-e1a2-5cea-a962-bbda7a9cd3ac:train:0/weights/multi-delete-1765772555-a
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 04:22:45.041867Z

  weights/demo-checkpoint-1765772524
    Path: tinker://b45501f0-d533-5b24-86f2-cb1b050f9125:train:0/weights/demo-checkpoint-1765772524
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-15 04:22:21.936869Z

  weights/async_demo_checkpoint
    Path: tinker://24da6d1f-34a1-55e2-a40a-4408f23e1735:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-15 04:20:56.341412Z

  sampler_weights/sampler-weights
    Path: tinker://8cf79ad3-9abb-5cfa-9880-90b087082964:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-15 04:19:43.753113Z

  weights/async_demo_checkpoint
    Path: tinker://a4e7cbd8-ce1c-563c-a1a7-522ebcc7380a:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-15 03:21:51.550950Z

  sampler_weights/sampler-weights
    Path: tinker://48714780-6131-5c1b-bd1c-955fb52b55f5:train:0/sampler_weights/sampler-weights
    Type: sampler
    Size: 168.1 MB
    Public: false
    Created: 2025-12-15 03:20:37.561808Z

  weights/recovery-live-2
    Path: tinker://9e89b426-4738-51bf-a5f8-a70b57a66250:train:1/weights/recovery-live-2
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-13 18:08:54.760162Z

  weights/recovery-live-1
    Path: tinker://9e89b426-4738-51bf-a5f8-a70b57a66250:train:0/weights/recovery-live-1
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-13 18:08:36.742817Z

  weights/demo-checkpoint-1765649250
    Path: tinker://700071be-b6d8-5e4e-a158-83d5dac63463:train:0/weights/demo-checkpoint-1765649250
    Type: training
    Size: 252.2 MB
    Public: false
    Created: 2025-12-13 18:07:42.229612Z

  weights/async_demo_checkpoint
    Path: tinker://fea7a6c0-cb47-585a-bf33-f2b6d7cdd42a:train:0/weights/async_demo_checkpoint
    Type: training
    Size: 305.8 MB
    Public: false
    Created: 2025-12-13 18:06:05.321883Z

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

Fetched 50 (225 total)
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

Fetched 25 (225 total)
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
==> Finished examples/checkpoints_management.exs [2025-12-26 22:52:08 HST | 00:03]

==> Running examples/weights_inspection.exs [2025-12-26 22:52:08 HST]
=== Tinkex Weights Inspection Example ===

--- Training Runs ---
Found 10 training runs:

  182029f2-a7b5-506c-a9b3-d6bddab03be8:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  f3909fbd-b422-5c2b-9ec3-07a6f2af032d:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  8def6eef-968c-55fa-ab0d-b61a71b9dbb9:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 16
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  5f7a66a7-5ca0-5b05-bbcd-7f283f2946a6:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 32
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  a0064b37-1013-58f5-88be-e8ddac91ea1b:train:1
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:1/weights/recovery-live-2
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  a0064b37-1013-58f5-88be-e8ddac91ea1b:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:0/weights/recovery-live-1
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  013c0962-718f-5deb-965b-46a512bb2738:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  dadf976e-bf2f-54c8-8e53-71e010efb6fe:train:0
    Base Model: Qwen/Qwen3-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

  66093a2f-643f-53f9-849a-591481c73834:train:0
    Base Model: meta-llama/Llama-3.1-8B
    Is LoRA: true, Rank: 8
    Corrupted: false
    Last Checkpoint: none
    Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5


--- Training Run Details: 182029f2-a7b5-506c-a9b3-d6bddab03be8:train:0 ---
  ID: 182029f2-a7b5-506c-a9b3-d6bddab03be8:train:0
  Base Model: meta-llama/Llama-3.1-8B
  Is LoRA: true
  LoRA Rank: 16
  Corrupted: false
  Last Checkpoint: none
  Last Sampler Checkpoint: none
  Last Request: 2025-12-27 08:52:03.361867Z
  Owner: tml:organization_user:274df404-aecf-449f-aae2-6a9ba92a62b5

--- User Checkpoints ---
Found 10 checkpoint(s):

  tinker://79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 168.14 MB
    Time: 2025-12-27 08:51:24.966034Z

  tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:1/weights/recovery-live-2
    Type: training
    ID: weights/recovery-live-2
    Size: 252.34 MB
    Time: 2025-12-27 05:39:53.893145Z

  tinker://a0064b37-1013-58f5-88be-e8ddac91ea1b:train:0/weights/recovery-live-1
    Type: training
    ID: weights/recovery-live-1
    Size: 252.34 MB
    Time: 2025-12-27 05:39:33.868033Z

  tinker://7dacb44e-8314-5b15-a1ff-f86f7f75d17c:train:0/weights/demo-checkpoint-1766813722
    Type: training
    ID: weights/demo-checkpoint-1766813722
    Size: 252.34 MB
    Time: 2025-12-27 05:35:36.226629Z

  tinker://5062a5d4-c072-5ac5-b596-9d0dfc782dad:train:0/weights/async_demo_checkpoint
    Type: training
    ID: weights/async_demo_checkpoint
    Size: 305.84 MB
    Time: 2025-12-27 05:34:17.457968Z

  tinker://2d57b556-4961-5e2d-8ae8-2d1354d016ca:train:0/sampler_weights/sampler-weights
    Type: sampler
    ID: sampler_weights/sampler-weights
    Size: 168.14 MB
    Time: 2025-12-27 05:32:55.744841Z

  tinker://d15e3de0-3435-5c3f-8aa2-be0f93fa6ebb:train:1/weights/recovery-live-2
    Type: training
    ID: weights/recovery-live-2
    Size: 252.34 MB
    Time: 2025-12-27 00:37:18.082789Z

  tinker://d15e3de0-3435-5c3f-8aa2-be0f93fa6ebb:train:0/weights/recovery-live-1
    Type: training
    ID: weights/recovery-live-1
    Size: 252.34 MB
    Time: 2025-12-27 00:36:57.015857Z

  tinker://7df8f4be-77ab-5046-99ef-690c1cf79b53:train:1/weights/recovery-live-2
    Type: training
    ID: weights/recovery-live-2
    Size: 252.34 MB
    Time: 2025-12-27 00:35:46.650401Z

  tinker://7df8f4be-77ab-5046-99ef-690c1cf79b53:train:0/weights/recovery-live-1
    Type: training
    ID: weights/recovery-live-1
    Size: 252.34 MB
    Time: 2025-12-27 00:35:35.343873Z


=== Example Complete ===
==> Finished examples/weights_inspection.exs [2025-12-26 22:52:10 HST | 00:02]

==> Running examples/checkpoint_download.exs [2025-12-26 22:52:10 HST]
=== Tinkex Checkpoint Download Example ===

TINKER_CHECKPOINT_PATH not provided; downloading first available checkpoint:
  tinker://79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0/sampler_weights/sampler-weights

Downloading checkpoint: tinker://79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0/sampler_weights/sampler-weights
Output directory: /tmp/tinkex_checkpoints

Progress: 100.0% (168.1 MB / 168.1 MB)

Download complete!
Extracted to: /tmp/tinkex_checkpoints/79db3d29-8bda-515f-a3c3-f9c1a8806642:train:0_sampler_weights_sampler-weights

Extracted files (3):
  • adapter_config.json (736 B)
  • adapter_model.safetensors (168.1 MB)
  • checkpoint_complete (0 B)

=== Example Complete ===
==> Finished examples/checkpoint_download.exs [2025-12-26 22:52:25 HST | 00:15]

==> Running examples/async_client_creation.exs [2025-12-26 22:52:25 HST]
=== Tinkex Async Client Creation Example ===

Creating sampling client asynchronously...
Task created, awaiting result...
✓ Sampling client created: #PID<0.311.0>

Creating LoRA training client asynchronously...
Task created, awaiting result...
✓ LoRA training client created: #PID<0.318.0>

Saving training state to create checkpoint...
✓ Saved state to: tinker://639aa93e-0a2d-5e62-ab57-059fa1367fd0:train:0/weights/async_demo_checkpoint

Restoring training client from checkpoint asynchronously...
✓ Training client restored: #PID<0.329.0>

=== Example Complete ===
==> Finished examples/async_client_creation.exs [2025-12-26 22:55:36 HST | 03:11]

==> Running examples/cli_run_text.exs [2025-12-26 22:55:36 HST]
Running CLI with args: run --base-model meta-llama/Llama-3.1-8B --prompt Hello from the CLI runner --max-tokens 64 --temperature 0.7 --num-samples 1 --api-key tml-mIf5gSt5tyewbDuXjwgeTkbdcgCZUpntGFyVBfKvmfGpb2FpJbfJ9tcFyYC5DXjcrAAAA
Starting sampling...
Sample 1:
!
I’m a CLI runner, not a human. I can run commands from the command line.
stop_reason=stop | avg_logprob=-1.33
Sampling complete (1 sequences)
sampling response: %Tinkex.Types.SampleResponse{
  sequences: [
    %Tinkex.Types.SampledSequence{
      tokens: [4999, 40, 4344, 264, 40377, 23055, 11, 539, 264, 3823, 13, 358,
       649, 1629, 11545, 505, 279, 3290, 1584, 13, 128001],
      logprobs: [-1.7039800882339478, -0.9429042935371399, -1.2703665494918823,
       -0.961822509765625, -0.8671809434890747, -0.1349903792142868,
       -1.0829825401306152, -4.924363136291504, -0.08803850412368774,
       -2.345918655395508, -0.8143548369407654, -0.24336232244968414,
       -2.5298006534576416, -1.1569310426712036, -1.4486631155014038,
       -3.094890594482422, -0.30952608585357666, -0.13307300209999084,
       -0.05042807385325432, -1.6772618293762207, -2.1457810401916504],
      stop_reason: :stop
    }
  ],
  prompt_logprobs: nil,
  topk_prompt_logprobs: nil,
  type: "sample"
}
==> Finished examples/cli_run_text.exs [2025-12-26 22:55:42 HST | 00:06]

==> Running examples/cli_run_prompt_file.exs [2025-12-26 22:55:42 HST]
Running CLI with prompt file /tmp/tinkex_prompt_6914.txt
Starting sampling...
Sampling complete (1 sequences)
JSON output written to /tmp/tinkex_output_6978.json
Preview:
{"prompt_logprobs":null,"sequences":[{"logprobs":[-5.27569580078125,-10.374618530273438,-5.468890190124512,-2.242182731628418,-1.9724485874176025,-0.1817384958267212,-0.17381711304187775,-0.2708265781402588,-0.13859817385673523,-0.014828816056251526,-0.10750778019428253,-0.01133266557008028,-0.21675319969654083,-1.8209550380706787,-0.10067127645015717,-0.05220174044370651,-0.04446905106306076,-0.029804455116391182,-0.0030083658639341593,-0.028614724054932594,-0.0069880131632089615,-0.11324502527713776,-2.5411789417266846,-4.273069381713867,-0.11049313098192215,-1.9300283193588257,-0.3664964735507965,-7.4886980056762695,-4.8042707443237305,-2.965291976928711,-2.966186046600342,-4.723921775817871,-8.037775039672852,-4.310561180114746,-6.066646575927734,-3.4062461853027344,-7.177375316619873,-1.9730761051177979,-3.8308680057525635,-3.0595343112945557,-1.3044060468673706,-8.56329345703125,-7.261374473571777,-11.300914764404297,-4.584809303283691,-4.313467502593994,-0.1856364756822586,-5.489373207092285,-2.7932090759277344,-2.1348814964294434,-1.4058653116226196,-3.5692877769470215,-1.4944021701812744,-3.0765228271484375,-0.5594513416290283,-1.0083893537521362,-6.316531181335449,-2.8534111976623535,-3.5815656185150146,-4.259769916534424,-6.205373287200928,-5.528190612792969,-5.092067718505859,-7.48106575012207,-4.280478477478027,-2.9598705768585205,-5.413959503173828,-2.999992847442627,-6.418670177459717,-5.7546467781066895,-3.978476047515869,-1.850548267364502,-1.524477481842041,-3.3664820194244385,-4.7062554359436035,-0.6260383129119873,-0.8682599067687988,-1.0464085340499878,-0.3436969518661499,-5.009876728057861,-6.859804630279541,-4.763156890869141,-2.2372288703918457,-6.187899112701416,-2.936605930328369,-2.6879959106445312,-8.86846923828125,-2.9940547943115234,-2.4285595417022705,-2.026658058166504,-5.891566753387451,-3.767258882522583,-2.7441539764404297,-0.3189750015735626,-0.8857313394546509,-13.287609100341797,-3.935161590576172,-5.881660461425781,-0.7247801423072815,-0.11568168550729752,-2.637317657470703,-1.6259779930114746,-3.221168041229248,-0.688012957572937,-4.127092361450195,-2.788898229598999,-3.3539834022521973,-0.27087894082069397,-8.132743835449219,-0.9102909564971924,-6.887807846069336,-6.886058330535889,-0.19700641930103302,-0.8879414200782776,-2.5034217834472656,-0.784678041934967,-6.936424732208252,-1.0271612405776978,-1.1869003772735596,-0.37621670961380005,-0.5141271352767944,-4.7572832107543945,-1.2327898740768433,-0.5382661819458008,-0.22427359223365784,-2.6727616786956787,-2.5752196311950684,-1.9472531080245972,-6.865103244781494,-10.401057243347168,-3.370760202407837,-5.067884922027588,-3.4571213722229004,-5.646816730499268,-2.732724666595459,-2.204920768737793,-4.514756202697754,-7.729701519012451,-2.338411569595337,-6.307875156402588,-1.7209446430206299,-0.9811694622039795,-0.06853990256786346,-2.657954692840576,-2.3170197010040283,-4.309113025665283,-1.4940454959869385,-2.328704595565796,-9.824291229248047,-1.6283060312271118,-0.7631666660308838,-3.2942323684692383,-0.24480149149894714,-0.7923314571380615,-13.087167739868164,-1.274814486503601,-1.361557126045227,-9.048754692077637,-0.4442644715309143,-11.880378723144531,-3.7118382453918457,-0.7129030227661133,-9.672172546386719,-0.28257593512535095,-10.198905944824219,-7.132627010345459,-0.028136510401964188,-2.941995620727539,-1.2455912828445435,-3.5219428539276123,-0.5969013571739197,-9.27713394165039,-4.5840959548950195,-1.242086410522461,-0.5698148012161255,-2.088693618774414,-3.410943031311035,-0.19930915534496307,-1.2433934211730957,-8.331989288330078,-3.0549917221069336,-3.4449105262756348,-6.084895610809326,-2.7237682342529297,-10.0631103515625,-0.6866054534912109,-0.08658558130264282,-2.3576462268829346,-7.193586349487305,-3.4701497554779053,-3.0116183757781982,-0.0710466280579567,-2.0253748893737793,-3.451186180114746,-0.631603479385376,-0.8628828525543213,-0.8262298107147217,-10.315898895263672,-2.5811679363250732,-1.045590877532959,-4.684721946716309,-1.2794976234436035,-3.6131908893585205,-2.2136802673339844,-2.726907253265381,-15.421165466308594,-2.458648681640625,-12.073125839233398,-0.4036262333393097,-1.7391350269317627,-6.62839412689209,-3.2534379959106445,-3.240854263305664,-11.217552185058594,-4.301013946533203,-7.266594886779785,-6.19437837600708,-4.192384719848633,-2.103503704071045,-8.245220184326172,-4.256715297698975,-8.146679878234863,-1.2419102191925049,-4.12857723236084,-9.633506774902344,-4.497567653656006,-7.779937267303467,-0.7746698260307312,-1.7914036512374878,-0.00520434370264411,-0.008769807405769825,-0.00436282716691494,-0.01625569351017475,-0.028027789667248726,-0.022654185071587563,-0.0011689979583024979,-0.0038576724473387003,-0.0025322535075247288,-0.0021378775127232075,-0.0036311899311840534,-0.003248178865760565,-0.005824616644531488,-0.0034298421815037727,-0.002864545676857233,-0.0022178117651492357,-0.2062721997499466,-0.04561639204621315,-0.13938017189502716,-0.10496566444635391,-2.9344654083251953,-1.6286039352416992,-3.160975694656372,-3.901233196258545,-0.28524458408355713,-4.44502067565918,-0.27637603878974915,-0.21153931319713593,-1.407059669494629,-3.9296910762786865,-0.04723760485649109,-1.7684409618377686,-9.790748596191406,-3.4761404991149902,-0.9351071715354919,-1.0017746686935425,-5.96834659576416,-6.483475685119629,-1.0786856412887573,-4.0599236488342285,-2.885263681411743,-9.320743560791016,-4.49216890335083,-3.718838930130005,-3.9795520305633545,-7.293780326843262,-4.790480613708496,-2.6851539611816406,-13.57805061340332,-3.453535556793213,-4.221673965454102,-5.18251371383667,-5.408858299255371,-6.654249668121338,-2.7304465770721436,-0.013367082923650742,-1.6082730293273926,-1.2795484066009521,-0.23299939930438995,-0.6140340566635132,-2.799628734588623,-5.30613899230957,-2.937034845352173,-0.08421114087104797,-3.032155752182007,-5.074977874755859,-0.4451277554035187,-1.294545292854309,-3.3785102367401123,-0.754737138748169,-1.069941520690918,-5.53989315032959,-5.898508071899414,-5.7961955070495605,-3.4793262481689453,-7.42454719543457,-4.3387451171875,-6.8724565505981445,-1.314049243927002,-4.16993522644043,-2.2341089248657227,-7.519648551940918,-7.052326679229736,-3.8442447185516357,-4.720657825469971,-4.114276885986328,-9.431167602539062,-0.8577254414558411,-8.368484497070312,-3.5643820762634277,-1.8123639822006226,-1.8671398162841797,-4.279262542724609,-5.140724182128906,-4.996221542358398,-13.211864471435547,-7.05010986328125,-10.531527519226074,-2.9575753211975098,-8.542649269104004,-1.584722876548767,-7.318744659423828,-0.6441121697425842,-4.6781792640686035,-4.337019920349121,-2.3348841667175293,-7.842293739318848,-1.1212514638900757,-5.608838081359863,-2.508542060852051,-7.227900505065918,-4.844590663909912,-0.9696269035339355,-4.5067853927612305,-6.92105770111084,-4.8564605712890625,-0.7762866020202637,-7.8511881828308105,-6.054555892944336,-0.16647367179393768,-0.7132852673530579,-5.523770809173584,-3.7452449798583984,-7.9311981201171875,-4.768733978271484,-1.9209918975830078,-9.290238380432129,-1.5224847793579102,-2.580310106277466,-2.7577872276306152,-1.4252148866653442,-2.841061592102051,-3.487053632736206,-5.3080363273620605,-0.5782409310340881,-3.2172486782073975,-1.4243265390396118,-7.06377649307251,-2.406130313873291,-4.892093658447266,-3.821444034576416,-3.6797289848327637,-3.385397434234619,-12.046207427978516,-7.759655952453613,-0.6895061135292053,-0.01658158004283905,-3.254154682159424,-1.8216079473495483,-2.132683515548706,-7.240069389343262,-4.612937927246094,-8.2116117477417,-0.020589781925082207,-2.4608113765716553,-1.505293607711792,-2.34698224067688,-8.87820816040039,-3.3859362602233887,-4.841828346252441,-8.215027809143066,-0.4588411748409271,-6.564416885375977,-9.872349739074707,-2.5419623851776123,-1.6586239337921143,-2.389707565307617,-3.4816501140594482,-4.185169696807861,-7.546990394592285,-1.9154202938079834,-0.320158988237381,-7.740602970123291,-5.972745895385742,-0.06275106966495514,-9.648091316223145,-10.041494369506836,-6.422736167907715,-4.226327896118164,-7.647392749786377,-5.464744567871094,-6.731523513793945,-2.846590280532837,-0.7084823250770569,-3.2444310188293457,-7.729715824127197,-3.266801357269287,-4.296902656555176,-7.4777421951293945,-5.629633903503418,-3.202415943145752,-4.392049789428711,-2.4587831497192383,-2.0637662410736084,-0.18884673714637756,-0.7506406307220459,-0.4098205864429474,-4.983615398406982,-1.996457576751709,-3.126744508743286,-5.777035713195801,-1.4806872606277466,-3.497980833053589,-6.941856861114502,-5.20454216003418,-2.349872589111328,-5.320303916931152,-6.7682952880859375,-2.416031837463379,-0.8736810088157654,-3.4193241596221924,-1.503678321838379,-9.276354789733887,-0.8042037487030029,-5.5288825035095215,-5.897404193878174,-2.644697666168213,-2.9995174407958984,-8.554388046264648,-3.1519947052001953,-7.188206672668457,-5.17527437210083,-2.9560863971710205,-0.39483004808425903,-0.6163228750228882,-0.06071695685386658,-1.1864746809005737,-5.9598774909973145,-8.56528091430664,-10.082101821899414,-7.154913902282715,-3.081890821456909,-3.0204291343688965,-0.7773385047912598,-6.915142059326172,-8.948409080505371,-2.4384889602661133,-6.792929172515869,-0.8778348565101624,-7.19598388671875,-2.551642656326294,-1.3689091205596924,-2.0846354961395264,-13.102997779846191,-9.769428253173828,-8.517953872680664,-2.452303647994995,-7.7958221435546875,-1.570223331451416,-1.8800816535949707,-2.6449317932128906,-0.01982726901769638,-3.2772815227508545,-0.16953818500041962,-3.7734668254852295,-0.01081851962953806,-4.035872459411621,-0.0257493294775486,-4.116490840911865,-8.152315139770508,-2.9689176082611084,-2.0410380363464355,-10.113080978393555,-10.990042686462402,-5.366037845611572,-1.8669006824493408,-2.3299050331115723,-3.9012560844421387,-1.539359211921692,-5.128627777099609,-2.2966394424438477,-0.7368577122688293,-0.3560831546783447,-0.003055786481127143,-5.352256703190506e-4,-0.006126907654106617,-3.987947420682758e-4,-0.008026606403291225,-0.0015595904551446438,-0.005345575045794249,-2.8701478731818497e-4,-1.6295487880706787,-9.681067313067615e-4,-1.227504849433899,-4.998983383178711,-0.6368153095245361,-9.368577003479004,-1.14678156375885,-3.2051937580108643,-4.45891809463501,-0.6323785185813904,-0.1515049934387207,-0.0026529375463724136,-0.0142061123624444,-0.0017445358680561185,-3.16212244797498e-4,-0.006207589991390705,-4.378790326882154e-4,-0.0017854715697467327,-3.671578815556131e-5,-0.04766744375228882,-2.236116270069033e-4,-1.1334068775177002,-5.074376106262207,-1.0975961685180664,-2.7018039226531982,-6.842090606689453,-3.487889051437378,-10.26683235168457,-4.036980628967285,-7.125828742980957,-2.614515781402588,-10.94272518157959,-4.921099662780762,-6.913968086242676,-0.2402971386909485,-0.0015845850575715303,-0.0013508014380931854,-0.0015791100449860096,-1.3791563105769455e-4,-0.00348912226036191,-5.249790847301483e-4,-0.0016976482002064586,-6.83045873302035e-5,-0.02887001633644104,-1.3565097469836473e-4,-0.4325732886791229,-11.733955383300781,-4.063713073730469,-4.849687099456787,-0.10840217024087906,-10.240082740783691,-2.178670644760132,-0.16257236897945404,-0.0012900849105790257,-3.6244976217858493e-4,-9.213017183355987e-4,-0.0020494903437793255,-0.00305459788069129,-9.029601933434606e-4,-7.35608336981386e-4,-8.999896090244874e-5,-0.011769027449190617,-8.391981828026474e-5,-0.19889993965625763,-5.701568603515625,-7.983204364776611,-3.295431613922119,-0.06733611226081848,-9.091534884646535e-4,-4.1166413575410843e-4,-6.176709430292249e-4,-4.172238186583854e-5,-9.147512027993798e-4,-4.704084130935371e-4,-6.467396160587668e-4,-6.282132380874828e-5,-0.01015118695795536,-7.068861305015162e-5,-0.11491207033395767,-8.68721866607666,-0.014857121743261814,-6.164605140686035,-2.419625759124756,-1.4318492412567139,-6.098430633544922,-9.025938034057617,-7.517061710357666,-0.8324383497238159,-0.028120169416069984,-1.611384391784668,-10.998791694641113,-1.053964376449585,-12.556164741516113,-3.1570353507995605,-4.58857536315918,-7.829287528991699,-4.4024810791015625,-4.675086975097656,-0.0927567332983017,-0.004182995297014713,-0.05977683886885643,-0.9332582950592041,-1.4591010808944702,-0.0027942920569330454,-7.199982064776123e-5,-0.0023520919494330883,-0.004137646406888962,-0.006723874714225531,-7.5049843871966e-4,-0.004893469624221325,-4.053033626405522e-5,-0.05007811263203621,-2.1252757869660854e-4,-2.3378729820251465,-5.919879913330078,-7.6139068603515625,-2.3727173805236816,-1.1844217777252197,-6.045281410217285,-4.95627498626709,-1.76914644241333,-0.10792029649019241,-9.95974289253354e-4,-4.09161759307608e-4,-5.656072753481567e-4,-2.821285743266344e-4,-9.285667329095304e-4,-3.8211196078918874e-4,-4.651656490750611e-4,-2.547178009990603e-4,-0.005911367479711771,-8.427741704508662e-5,-0.1537201702594757,-3.50280499458313,-3.877180814743042,-2.7779037952423096,-5.708392143249512,-4.3457112312316895,-4.145150661468506,-3.047473430633545,-2.956191062927246,-2.0397605895996094,-7.092214584350586,-2.038416624069214,-0.11504585295915604,-7.074952009133995e-4,-2.1491125517059118e-4,-3.8723601028323174e-4,-6.460934673668817e-5,-8.083889842964709e-4,-1.1193125828867778e-4,-4.377598816063255e-4,-3.099393507000059e-5,-0.005600001662969589,-1.811964830267243e-5,-0.22322803735733032,-4.1729278564453125,-0.09316994994878769,-0.7103066444396973,-0.26707983016967773,-0.06511162221431732,-0.0948757529258728,-0.008120378479361534,-0.03296651318669319,-0.03177442029118538,-0.4316885769367218,-0.0034185561817139387,-0.06882882863283157,-0.018195733428001404,-2.86657246761024e-4,-9.667406266089529e-5,-1.9107422849629074e-4,-9.775113539944869e-6,-2.8951745480298996e-4,-6.115249561844394e-5,-1.9107422849629074e-4,-7.510157047363464e-6,-0.0017861855449154973,-1.3947389561508317e-5,-0.04642857611179352,-0.12809012830257416,-0.012023121118545532,-8.091434478759766,-4.46502161026001,-0.7405239343643188,-0.039547644555568695,-0.038081347942352295,-5.932478234171867e-4,-7.533743337262422e-5,-3.6173476837575436e-4,-7.152555099310121e-7,-4.371640970930457e-4,-5.507317473529838e-5,-2.2456508304458112e-4,-1.07287787614041e-5,-0.001842707279138267,-3.8265450712060556e-5,-0.05189529433846474,-2.3317654132843018,-0.004706732928752899,-0.3264574408531189,-3.447481393814087,-0.12454804033041,-2.4442806243896484,-0.6924120187759399,-0.005402963142842054,-0.0013453251449391246,-0.06900318711996078,-8.770751953125,-9.163949012756348,-1.7600388526916504,-3.4195351600646973,-11.052719116210938,-8.869243621826172,-5.75404167175293,-2.5364341735839844,-2.381793737411499,-3.74813175201416,-1.4073866605758667,-0.6091034412384033,-4.128382682800293,-10.755293846130371,-11.007604598999023,-1.7584811449050903,-0.9194117784500122,-0.006577863823622465,-0.0010873125866055489,-0.0017874945187941194,-2.586808113846928e-5,-0.005432248581200838,-5.212855176068842e-4,-0.005290911067277193,-3.731181277544238e-5,-4.0407586097717285,-6.843847222626209e-4,-4.126222610473633,-6.639579772949219,-1.852990746498108,-5.242619037628174,-4.929143905639648,-5.128513813018799,-3.211723804473877,-7.734898567199707,-1.8736369609832764,-4.823245525360107,-0.5157297253608704,-0.006785091012716293,-0.001806057756766677,-0.30728211998939514,-0.07511671632528305,-9.845414897426963e-4,-1.436368766007945e-4,-4.892344586551189e-4,-8.821448318485636e-6,-5.758534534834325e-4,-8.77341881277971e-5,-7.905219099484384e-4,-6.437280717364047e-6,-0.026590343564748764,-5.352353764465079e-5,-0.3135254979133606,-4.591992378234863,-8.994415283203125,-5.183854579925537,-4.859254360198975,-4.190775394439697,-3.219926118850708,-4.350008964538574,-0.4833912253379822,-0.17843428254127502,-8.299481705762446e-4,-2.0418466010596603e-4,-6.355411605909467e-4,-8.868777513271198e-5,-7.674132939428091e-4,-4.0725519647821784e-4,-9.299959056079388e-4,-7.271740287251305e-6,-0.03753691911697388,-5.447716102935374e-5,-5.273833274841309,-7.407142639160156,-3.784395694732666,-8.184242248535156,-3.0232059955596924,-2.230001926422119,-7.687091827392578,-1.7348065376281738,-0.12310329079627991,-5.447572330012918e-4,-2.9213930247351527e-4,-7.317964336834848e-4,-2.264974000354414e-6,-8.332832949236035e-4,-4.146431456319988e-4,-9.615565068088472e-4,-2.658331868587993e-5,-0.06781210005283356,-6.23445157543756e-5,-5.134552001953125,-6.329146385192871,-6.9026594161987305,-4.335853099822998,-11.744982719421387,-6.149043083190918,-12.037620544433594,-6.408080577850342,-2.2174549102783203,-0.09915672242641449,-5.890780012123287e-4,-4.5313104055821896e-4,-0.001259606215171516,-2.4676019165781327e-5,-0.0016462358180433512,-9.476689592702314e-5,-0.001329015358351171,-7.986990567587782e-6,-0.10411921888589859,-6.151010165922344e-5,-2.0344691276550293,-3.580446243286133,-0.03187534585595131,-0.12974289059638977,-0.03042561747133732,-0.013237803243100643,-0.014945559203624725,-0.0013036570744588971,-0.00543414568528533,-0.008683539927005768,-0.14845141768455505,-0.001670038211159408,-0.024877026677131653,-0.01351457554847002,-1.839230244513601e-4,-2.706014311115723e-5,-1.6711745411157608e-4,-2.3841830625315197e-6,-2.2623363474849612e-4,-5.8412379075889476e-6,-2.150304353563115e-4,-1.9073468138230965e-6,-0.007271964568644762,-2.372236667724792e-5,-0.056194599717855453,-0.16263143718242645,-0.07720840722322464,-3.0664119720458984,-0.04476592689752579,-3.152989625930786,-0.8355976343154907,-0.021549368277192116,-0.037850894033908844,-4.786299541592598e-4,-3.957670196541585e-5,-4.861365014221519e-4,-7.152555099310121e-7,-2.2182388056535274e-4,-1.1169286881340668e-4,-4.6302087139338255e-4,-2.264974000354414e-6,-0.014901400543749332,-2.7417760065873154e-5,-0.10665448009967804,-9.478694915771484,-0.20354732871055603,-4.065758228302002,-0.6771824955940247,-0.9119210243225098,-0.480272114276886,-11.062314987182617,-8.593223571777344,-2.1740288734436035,-0.9438577890396118,-0.021741967648267746,-3.1716562807559967e-4,-2.7894584491150454e-5,-6.952252588234842e-4,-1.2040065485052764e-5,-3.069168305955827e-4,-4.273931554052979e-4,-5.229535745456815e-4,-6.198863957251888e-6,-0.01714937388896942,-3.111314072157256e-5,-0.21543291211128235,-0.5352171063423157,-0.021615050733089447,-0.0013892533024773002,-0.22624161839485168,-0.009006352163851261,-0.910345733165741,-0.01572600193321705,-4.774744987487793,-8.349312782287598,-4.189340114593506,-4.224117279052734,-4.643091201782227,-8.724292755126953,-12.731547355651855,-6.686172008514404,-3.9118943214416504,-3.0933754444122314,-7.147934913635254,-2.7883358001708984,-12.036880493164062,-4.4783477783203125,-2.074282646179199,-6.936887264251709,-3.07914662361145,-6.265895366668701,-3.631598949432373,-0.012595626525580883,-1.9152801036834717,-4.8374738693237305,-5.008179187774658,-2.4825379848480225,-9.88802719116211,-8.533178329467773,-4.247980117797852,-3.4009809494018555,-0.898485004901886,-6.648138999938965,-8.810046195983887,-1.519619345664978,-6.369327545166016,-4.487227439880371,-7.430335998535156,-3.2258987426757812,-7.959870338439941,-4.806174278259277,-10.137550354003906,-10.095032691955566,-0.04830669239163399,-1.1846792697906494,-3.171760320663452,-0.8723790645599365,-1.1682610511779785,-0.006312550511211157,-6.210067658685148e-4,-0.012786074541509151,-9.65590606938349e-6,-0.012587739154696465,-5.988473421894014e-4,-5.014493942260742,-5.851463647559285e-4,-4.308937072753906,-6.124289939180017e-4,-4.09194278717041,-8.642463684082031,-7.752562046051025,-3.402097225189209,-10.79477310180664,-4.703570365905762,-4.952272891998291,-0.20063674449920654,-0.00130353809799999,-3.7698791129514575e-4,-0.0027646913658827543,-2.8967437174287625e-5,-0.004288168158382177,-2.461368858348578e-4,-0.00957881473004818,-5.7338023907504976e-5,-0.05692515894770622,-1.6689160474925302e-5,-0.3704017400741577,-7.7442121505737305,-5.495388507843018,-3.3693108558654785,-11.935283660888672,-0.25807127356529236,-0.0880097895860672,-6.465504169464111,-1.414448857307434,-0.8279524445533752,-3.906838893890381,-2.037909507751465,-0.2291441559791565,-0.0015653035370633006,-4.0546778473071754e-4,-0.002267410745844245,-2.622600959512056e-6,-0.001487697591073811,-2.348147245356813e-4,-0.008904745802283287,-2.0503786799963564e-5,-0.04016714170575142,-5.864924969500862e-5,-0.27102822065353394,-9.464700698852539,-12.665184020996094,-6.293385028839111,-2.1202378273010254,-0.4714869260787964,-2.6838018894195557,-0.6038880348205566,-0.09676847606897354,-6.098079611547291e-4,-8.630380034446716e-5,-6.375664379447699e-4,-2.1219027985353023e-5,-3.3241944038309157e-4,-1.764281842042692e-5,-0.0023842023219913244,-5.245195097813848e-6,-0.013992894440889359,-5.018585216021165e-5,-0.1539946049451828,-6.676959037780762,-3.514115571975708,-3.6017162799835205,-0.22191007435321808,-1.574530839920044,-0.0997994989156723,-4.903068183921278e-4,-1.0895135346800089e-4,-4.5348849380388856e-4,-5.8412379075889476e-6,-4.978132783435285e-4,-6.12716976320371e-5,-0.0012994902208447456,-9.179073458653875e-6,-5.259530067443848,-3.7245964631438255e-4,-4.59886360168457,-7.122314453125,-3.7933602333068848,-2.917968273162842,-0.8675024509429932,-5.439358711242676,-1.5241484642028809,-0.19289037585258484,-5.719843864440918,-0.14274464547634125,-1.158937931060791,-0.05449777469038963,-4.658307075500488,-2.8253817558288574,-1.2983872890472412,-0.19616301357746124,-1.4381461143493652,-6.133765697479248,-0.591081976890564,-0.09367319941520691,-0.09597527235746384,-0.06668069958686829,-0.006688706111162901,-0.0039033901412039995,-0.015384221449494362,-0.004152960609644651,-0.001574349240399897,-0.0010402749758213758,-0.015099981799721718,-0.0030787233263254166,-0.0026238083373755217,-0.0027973828837275505,-0.13685791194438934,-8.390676498413086,-1.2562822103500366,-0.9322735071182251,-7.66512393951416,-7.193349838256836,-14.256004333496094,-7.800593852996826,-4.572505474090576,-3.7583882808685303,-5.757612228393555,-1.964946985244751,-12.274988174438477,-6.344348907470703,-6.042970657348633,-5.153913497924805,-7.768986701965332,-8.596375465393066,-3.1235530376434326,-3.427034616470337],"stop_reason":"stop","tokens":[1887,1893,1567,198,9906,505,264,10137,1052,1887,1893,1567,198,9906,505,264,10137,1052,1887,1893,1567,198,40,1390,311,1893,264,2242,5429,902,649,1005,1401,12928,16792,11,3350,279,7039,304,279,7257,315,26120,304,1401,12928,422,539,3118,323,1893,279,1401,12928,422,1205,311,11,1005,856,4443,10137,3977,400,2465,575,369,8106,198,2028,5429,374,16070,15716,264,502,1052,1887,574,11096,1139,264,445,2843,11,27378,389,433,11,650,16810,389,433,11,99443,3932,4613,389,433,5099,13,5099,627,333,499,1541,956,33316,279,3770,12,37691,7482,304,701,1650,311,279,5429,11,872,2819,690,387,743,9651,512,37,10754,6715,429,1213,61996,12821,10982,26691,46371,702,4110,279,1401,12928,323,923,311,279,7257,6376,315,279,1401,12928,279,11847,3977,400,5589,285,96781,902,374,15691,279,5649,445,2843,2686,198,4110,279,31576,311,387,1511,555,1401,12928,198,4291,1401,6323,9886,11,20839,575,716,11,6606,279,445,2843,323,5249,279,8106,198,60179,311,279,4264,279,8106,323,6125,20705,198,29316,7623,264,3465,369,6968,75138,53827,14,25658,26711,311,50977,449,1522,1555,5718,30,482,12761,198,29316,7623,264,3465,369,6968,75138,53827,14,25658,26711,311,50977,449,1522,1555,5718,30,482,12761,198,40,617,311,743,709,1522,1555,5718,389,4027,87396,369,36721,220,679,15,612,5000,327,3932,11,4691,505,264,21390,1063,7526,323,93566,6946,315,8292,505,73381,12,3204,220,23,13,15,198,2520,5000,327,279,3575,374,430,1070,374,912,2867,1217,1638,779,3515,682,25461,9629,5108,311,34986,315,3932,4871,2883,8866,13,955,284,220,21,505,50977,477,55671,18749,7389,584,2103,617,6812,2599,5507,4401,323,23330,369,28555,627,9906,1578,505,701,33762,8427,198,42,94890,8663,12694,369,459,917,2663,330,46042,1,311,1893,264,3465,389,3290,1584,902,690,26711,682,20946,1555,26384,477,925,11716,818,839,1555,75138,198,12834,304,52298,3200,358,617,279,296,784,80,27221,2690,2612,3940,555,264,3465,2663,198,2201,1205,311,2216,3568,449,5852,27378,1070,779,345,2675,682,2359,617,701,6037,369,10923,8029,8403,11,1095,757,1501,499,1268,311,1095,279,3465,902,374,3940,320,28272,439,5429,499,617,311,4685,8,6678,279,4460,6933,2686,198,288,1498,5822,403,284,220,10290,18,198,16,69,49,26711,1337,28,25658,3932,8507,82,1673,82,308,796,28,90440,33066,10847,11389,198,679,24,14,1721,14,966,220,1691,25,1114,25,2946,4800,6968,279,1888,2807,71,4440,311,6920,701,26711,9629,198,679,24,14,1721,14,966,220,1691,25,972,25,410,20638,709,76563,369,26384,26542,198,679,24,14,1721,14,966,220,1691,25,972,25,410,2052,24060,279,5419,8403,2865,315,14564,311,802,33686,627,679,24,14,1721,14,966,220,1691,25,972,25,410,7940,28,43893,964,25006,198,679,24,14,1721,14,966,220,1691,25,972,25,410,34637,50319,198,679,24,14,1721,14,966,220,1691,25,972,25,410,27221,2690,320,28260,8,1795,31111,13,8035,275,198,7072,2771,17067,374,4613,1448,609,8507,82,1673,82,198,679,24,14,1721,14,966,220,1691,25,972,25,1721,25274,4741,6037,369,330,2485,702,679,24,14,1721,14,966,220,1691,25,972,25,1721,3788,4741,13233,26384,62,7283,62,17,62,6889,198,679,24,14,1721,14,966,220,1691,25,972,25,1721,2052,24060,279,5419,8403,2865,315,14564,311,802,33686,627,679,24,14,1721,14,966,220,1691,25,972,25,1721,7940,28,94597,23416,25006,198,679,24,14,1721,14,966,220,1691,25,972,25,1721,27221,2690,320,32201,8,3788,13,8035,275,198,13397,10179,430,422,3361,20797,539,3118,499,2011,4685,1124,20684,10950,7677,198,679,24,14,1721,14,966,220,1691,25,777,25,845,18242,279,68859,5137,320,39765,35588,8,3788,13,8035,275,198,679,24,14,1721,14,966,220,1691,25,777,25,845,42754,5729,6683,323,68859,10950,6992,198,679,24,14,1721,14,966,220,1691,25,777,25,1627,97218,57479,25605,5137,369,13594,198,679,24,14,1721,14,966,220,1691,25,777,25,1758,51269,4259,7821,9749,482,15062,4741,198,679,24,14,1721,14,966,220,1691,25,777,25,1927,2052,24060,279,5419,8403,2865,315,14564,311,802,33686,627,679,24,14,1721,14,966,220,1691,25,777,25,1927,7940,28,12615,49045,60165,25006,198,679,24,14,1721,14,966,220,1691,25,777,25,1927,14882,287,4741,6037,369,330,58121,4306,599,702,679,24,14,1721,14,966,220,1691,25,777,25,1927,12288,4306,599,4741,13233,29977,49045,198,34,12092,13594,68859,11805,6920,459,68859,13594,3318,304,30313,34637,198,94597,33878,6037,29977,49045,60165,449,955,284,8730,9629,449,2700,220,9079,551,220,24,374,11054,323,1063,2700,538,67514,9296,527,5068,198,679,24,14,1721,14,966,220,1313,25,1544,25,1313,12382,73381,54,35480,3788,198,679,24,14,1721,14,966,220,1313,25,1544,25,1313,682,3476,320,10784,575,716,2442,41392,8,13594,198,679,24,14,1721,14,966,220,1313,25,1544,25,1313,11107,34004,926,284,220,16,198,679,24,14,1721,14,966,220,1313,25,1544,25,1313,1401,28,509,2690,198,679,24,14,1721,14,966,220,1313,25,1591,25,2137,13170,220,7507,25,5324,1889,794,22,1359,2037,3332,7507,482,2876,12595,17122,3767,220,7507,25,5324,1889,794,22,1359,2037,3332,7507,482,2876,12595,17122,13966,220,16,5,6,54574,3427,330,25658,13741,13233,68522,7363,69,1030,10344,2576,1,128001]}],"topk_prompt_logprobs":null,"type":"sample"}

==> Finished examples/cli_run_prompt_file.exs [2025-12-26 22:55:57 HST | 00:15]

==> Running examples/metrics_live.exs [2025-12-26 22:55:57 HST]
Sampling 1 sequence(s) from meta-llama/Llama-3.1-8B ...
Sampled text: . I’m starting a new habit of checking these metrics once per week.
I have a few hypotheses about why I’m not making money. I’ll test them

=== Metrics Snapshot ===
Counters:
  tinkex_requests_success: 4
  tinkex_requests_total: 4

Latency (ms):
  count: 4
  mean: 344.77
  p50:  289.75
  p95:  650.54
  p99:  650.54
==> Finished examples/metrics_live.exs [2025-12-26 22:55:59 HST | 00:02]

==> Running examples/telemetry_live.exs [2025-12-26 22:55:59 HST]
Starting service client against https://tinker.thinkingmachines.dev/services/tinker-prod ...
Creating sampling client for meta-llama/Llama-3.1-8B ...

22:56:00.989 [info] HTTP post /api/v1/create_sampling_session start (pool=session base=https://tinker.thinkingmachines.dev/services/tinker-prod)

22:56:01.163 [info] HTTP post /api/v1/create_sampling_session ok in 173ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sending sample request ...

22:56:02.217 [info] HTTP post /api/v1/asample start (pool=sampling base=https://tinker.thinkingmachines.dev/services/tinker-prod)

22:56:02.532 [info] HTTP post /api/v1/asample ok in 315ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod

22:56:02.536 [info] HTTP post /api/v1/retrieve_future start (pool=futures base=https://tinker.thinkingmachines.dev/services/tinker-prod)

22:56:03.274 [info] HTTP post /api/v1/retrieve_future ok in 737ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
Sampled sequences: [
  %Tinkex.Types.SampledSequence{
    tokens: [4427, 4860, 499, 2643, 1005, 311, 1520, 198, 8144, 264, 3254,
     11914, 922, 62137, 13, 4427, 4860, 499, 2643, 1005, 311, 1520, 499, 4320,
     420, 3488, 527, 25, 3639, 753, 264, 3756],
    logprobs: [-8.454058647155762, -4.894715309143066, -1.9592195749282837,
     -0.6610857248306274, -6.2186737060546875, -0.20134851336479187,
     -1.1865514516830444, -9.553085327148438, -0.36333197355270386,
     -1.8487652414478362e-4, -1.0334911348763853e-4, -1.971527235582471e-4,
     -4.959068610332906e-4, -2.321927313460037e-4, -0.09772798418998718,
     -7.800396997481585e-4, -4.60137271147687e-5, -3.6000557884108275e-5,
     -8.439661905867979e-5, -4.9828242481453344e-5, -4.8874615458771586e-5,
     -9.727005090098828e-5, -0.1042296439409256, -3.0561513900756836,
     -0.2025538682937622, -0.2020752727985382, -0.42497727274894714,
     -0.5233827233314514, -0.27265551686286926, -6.990358352661133,
     -4.157001972198486, -6.182711124420166],
    stop_reason: :length
  }
]

22:56:03.298 [info] HTTP post /api/v1/telemetry start (pool=telemetry base=https://tinker.thinkingmachines.dev/services/tinker-prod)
Flushed telemetry; detach logger and exit.

22:56:03.516 [info] HTTP post /api/v1/telemetry ok in 217ms retries=0 base=https://tinker.thinkingmachines.dev/services/tinker-prod
==> Finished examples/telemetry_live.exs [2025-12-26 22:56:03 HST | 00:04]

==> Running examples/telemetry_reporter_demo.exs [2025-12-26 22:56:03 HST]
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
   Generated:  How do I use it?
Why should I use telemetry?
What is a telemetry channel?
Why c...

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

==> Finished examples/telemetry_reporter_demo.exs [2025-12-26 22:56:07 HST | 00:04]

==> Running examples/retry_and_capture.exs [2025-12-26 22:56:07 HST]
Telemetry reporter started for live session.
[retry start] attempt=0
[retry retry] attempt=0 delay=200ms duration=0ms error=[api_status (500)] synthetic 500 for retry demo
[retry start] attempt=1
[retry retry] attempt=1 delay=400ms duration=0ms error=[api_status (500)] synthetic 500 for retry demo
[retry start] attempt=2
[retry stop] attempt=2 duration=0ms result=ok
Final result: "succeeded on attempt 3"
==> Finished examples/retry_and_capture.exs [2025-12-26 22:56:09 HST | 00:02]

==> Running examples/live_capabilities_and_logprobs.exs [2025-12-26 22:56:09 HST]
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
==> Finished examples/live_capabilities_and_logprobs.exs [2025-12-26 22:56:13 HST | 00:04]

==> Running examples/file_upload_multipart.exs [2025-12-26 22:56:13 HST]
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
    Input:  %{metadata: %{version: "0.3.4", source: "tinkex"}, note: "Multipart demo from Tinkex"}
    Output: %{"metadata[source]" => "tinkex", "metadata[version]" => "0.3.4", "note" => "Multipart demo from Tinkex"}

[4] Multipart Encoding:
    Content-Type: multipart/form-data; boundary=5f79aa0da66c9e52260a19485b79660d
    Body size: 516 bytes

[5] Multipart Body Preview:
    --5f79aa0da66c9e52260a19485b79660d
    Content-Disposition: form-data; name="metadata[source]"

    tinkex
    --5f79aa0da66c9e52260a19485b79660d
    Content-Disposition: form-data; name="metadata[version]"

    0.3.4
    --5f79aa0da66c9e52260a19485b79660d
    Content-Disposition: form-data; name="note"

    Multipart demo from Tinkex
    --5f79aa0da66c9e52260a19485b79660d
    Content-Disposition: form-data; name="file"; filename="sample_upload.bin"
    Content-Type: application/octet-stream

    hello

    --5f79aa0da66c9e52260a19485b79660d--

    ... (16 more bytes)

[6] API Integration:
    API key present but TINKER_UPLOAD_ENDPOINT not set
    Note: The Tinker API has no file upload endpoints currently.
    Set TINKER_UPLOAD_ENDPOINT to test against a custom endpoint.

============================================================
Demo complete. Multipart encoding is working correctly.
============================================================
==> Finished examples/file_upload_multipart.exs [2025-12-26 22:56:15 HST | 00:02]

==> Running examples/adam_and_chunking_live.exs [2025-12-26 22:56:15 HST]
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
[ok] optim_step metrics: %{"unclipped_grad_l2:mean" => 10577.1015625}
[done] AdamParams and byte-based chunking demo complete
==> Finished examples/adam_and_chunking_live.exs [2025-12-26 22:56:25 HST | 00:10]

==> Running examples/llama3_tokenizer_override_live.exs [2025-12-26 22:56:25 HST]
Tokenizer ID: thinkingmachineslabinc/meta-llama-3-tokenizer
Encoded prompt token IDs (13): [128000, 80853, 71015, 445, 81101, 12, 18, 47058, 2882, 304, 832, 11914, 13]
Decoded first sequence:  I will write a longer sentence in the future and explain everything in detail.
The
==> Finished examples/llama3_tokenizer_override_live.exs [2025-12-26 22:56:29 HST | 00:04]

==> Running examples/queue_reasons_and_sampling_throttling.exs [2025-12-26 22:56:29 HST]
----------------------------------------
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Prompt: Hello from throttling + queue reasons!
----------------------------------------


22:56:30.396 [info] The function passed as a handler with ID "queue-reasons-demo-9858" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] demonstrating server-preferred reason via QueueStateLogger
[info] simulating backoff to exercise throttled dispatch + byte penalty

22:56:30.405 [warning] Sampling is paused for d3bd4b32-bcf8-562c-ab85-e5505e6858c5:sample:0. Reason: server says: running short on capacity (demo)
[info] dispatch acquisition order (penalized bytes): one at -576460750967
[info] estimated prompt bytes: 90
[step] running live sample...
[ok] sample returned 1 sequence(s)
[done] queue reasons + throttling demo complete
==> Finished examples/queue_reasons_and_sampling_throttling.exs [2025-12-26 22:56:32 HST | 00:03]

==> Running examples/multimodal_resume_and_cleanup.exs [2025-12-26 22:56:32 HST]
== Multimodal sampling (image + text)
Using vision-capable model: Qwen/Qwen3-VL-30B-A3B-Instruct
Using image: examples/assets/vision_sample.png (format=png expected_tokens=nil)
Sampled 1 sequence(s) with image + text.
- tokens: [7, 17, 15, 15, 11, 17, 15, 15]

== Optimizer resume via ServiceClient helper
Restoring weights + optimizer from tinker://66093a2f-643f-53f9-849a-591481c73834:train:0/weights/multi-delete-1766813750-a ...
Resume failed: %Tinkex.Error{message: "HTTP 400", type: :api_status, status: 400, category: :user, data: %{"detail" => "Invalid checkpoint tinker path tinker://66093a2f-643f-53f9-849a-591481c73834:train:0/weights/multi-delete-1766813750-a."}, retry_after_ms: 1000}

CLI multi-delete (single confirmation):
  tinkex checkpoint delete tinker://run-1/weights/0001 tinker://run-2/weights/0002 --yes

==> Finished examples/multimodal_resume_and_cleanup.exs [2025-12-26 22:56:36 HST | 00:04]

==> Running examples/training_persistence_live.exs [2025-12-26 22:56:36 HST]
Base URL: https://tinker.thinkingmachines.dev/services/tinker-prod
Base model: meta-llama/Llama-3.1-8B
Checkpoint name: demo-checkpoint-1766825797
Saved checkpoint to tinker://c10b5421-163f-50bf-951c-a1fa8d35e2c2:train:0/weights/demo-checkpoint-1766825797
Reloaded checkpoint with optimizer state
Created a fresh training client from checkpoint: #PID<0.329.0>
==> Finished examples/training_persistence_live.exs [2025-12-26 22:56:56 HST | 00:20]

==> Running examples/checkpoint_multi_delete_live.exs [2025-12-26 22:56:56 HST]
Saved checkpoint multi-delete-1766825816-a: tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-a
Saved checkpoint multi-delete-1766825816-b: tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-b
Cached default checkpoint path at tmp/checkpoints/default.path: tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-a

Deleting 2 checkpoints with one confirmation...
Deleting 1/2: tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-a
Deleted tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-a
Deleting 2/2: tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-b
Deleted tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-b

Multi-delete summary:
result: %{
  command: :checkpoint,
  action: :delete,
  failed: 0,
  paths: ["tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-a",
   "tinker://4564f60f-d7e9-517e-937e-8af5445f3c44:train:0/weights/multi-delete-1766825816-b"],
  failures: [],
  deleted: 2
}
==> Finished examples/checkpoint_multi_delete_live.exs [2025-12-26 22:57:05 HST | 00:09]

==> Running examples/save_weights_and_sample.exs [2025-12-26 22:57:05 HST]
[setup] base_model=Qwen/Qwen3-8B
[setup] prompt="Hello from Tinkex!"
[setup] max_tokens=32 lora_rank=8
[save] saving weights and creating a SamplingClient (sync helper)...
[error] save_weights_and_get_sampling_client_sync failed: [validation] Either model_path or base_model must be provided data=nil
==> Finished examples/save_weights_and_sample.exs [2025-12-26 22:57:27 HST | 00:22]

==> Running examples/queue_state_observer_demo.exs [2025-12-26 22:57:27 HST]
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
==> Finished examples/queue_state_observer_demo.exs [2025-12-26 22:57:31 HST | 00:04]

==> Running examples/recovery_simulated.exs [2025-12-26 22:57:31 HST]
1) Seeded checkpoint tinker://demo-run-8133/weights/0001
2) Simulated corruption flag on demo-run-8133
3) Recovery succeeded from tinker://demo-run-8133/weights/0001 -> #PID<0.313.0>
4) Checkpoints processed: tinker://demo-run-8133/weights/0001, tinker://demo-run-8133/weights/0002
Final run status: %{
  clients: [#PID<0.313.0>],
  completed: [
    %Tinkex.Types.Checkpoint{
      checkpoint_id: "cp-0001",
      checkpoint_type: "weights",
      tinker_path: "tinker://demo-run-8133/weights/0001",
      training_run_id: "demo-run-8133",
      size_bytes: nil,
      public: false,
      time: ~U[2025-12-27 08:57:32.096488Z]
    },
    %Tinkex.Types.Checkpoint{
      checkpoint_id: "cp-0002",
      checkpoint_type: "weights",
      tinker_path: "tinker://demo-run-8133/weights/0002",
      training_run_id: "demo-run-8133",
      size_bytes: nil,
      public: false,
      time: ~U[2025-12-27 08:57:32.099824Z]
    }
  ],
  last_checkpoint: "tinker://demo-run-8133/weights/0002",
  corrupted?: false
}
==> Finished examples/recovery_simulated.exs [2025-12-26 22:57:32 HST | 00:01]

==> Running examples/recovery_live_injected.exs [2025-12-26 22:57:32 HST]
Saved checkpoint tinker://aa73d734-ed2d-5fb1-9200-536073b0c61e:train:0/weights/recovery-live-1
Recovery callback: old=#PID<0.313.0> new=#PID<0.331.0> cp=tinker://aa73d734-ed2d-5fb1-9200-536073b0c61e:train:0/weights/recovery-live-1
Saved checkpoint tinker://aa73d734-ed2d-5fb1-9200-536073b0c61e:train:1/weights/recovery-live-2
Recovered from tinker://aa73d734-ed2d-5fb1-9200-536073b0c61e:train:0/weights/recovery-live-1
Second checkpoint saved: tinker://aa73d734-ed2d-5fb1-9200-536073b0c61e:train:1/weights/recovery-live-2
==> Finished examples/recovery_live_injected.exs [2025-12-26 23:01:08 HST | 03:36]

==> Running examples/kimi_k2_sampling_live.exs [2025-12-26 23:01:08 HST]
== Kimi K2 tokenization (tiktoken_ex)
Model: moonshotai/Kimi-K2-Thinking
Prompt: "Say hi"
Token IDs (first 32): [71079, 20910] (2 total)
Round-trip decode: "Say hi"

== Live sampling
Sampling 1 sequence(s) from moonshotai/Kimi-K2-Thinking ...
Received 1 sequence(s):
Sample 1:  to your brother for me.”
She crossed her arms. “I don’t think so.”
He was right, she thought as she watched him walk away
==> Finished examples/kimi_k2_sampling_live.exs [2025-12-26 23:01:14 HST | 00:06]

==> Running examples/model_info_and_unload.exs [2025-12-26 23:01:14 HST]
[tinkex] base_url=https://tinker.thinkingmachines.dev/services/tinker-prod
[tinkex] base_model=meta-llama/Llama-3.1-8B
[tinkex] created session_id=f629aa6f-d12e-5ebc-b4e9-633b4ce5bc19
[tinkex] poll #1 create_model request_id=f629aa6f-d12e-5ebc-b4e9-633b4ce5bc19:train:0:0
[tinkex] created model_id=f629aa6f-d12e-5ebc-b4e9-633b4ce5bc19:train:0
[tinkex] model_id=f629aa6f-d12e-5ebc-b4e9-633b4ce5bc19:train:0
- model_name: meta-llama/Llama-3.1-8B
- arch: unknown
- tokenizer_id: thinkingmachineslabinc/meta-llama-3-tokenizer
- is_lora: true
- lora_rank: 32
[tinkex] unload_model
[tinkex] unload failed: [api_status (404)] HTTP 404 status=404
[tinkex] error data: %{"detail" => "Not Found"}
==> Failed examples/model_info_and_unload.exs [2025-12-26 23:01:22 HST | 00:08]
````
