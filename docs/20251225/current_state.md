# Tinkex Current State Documentation

**Date:** 2025-12-25
**Version:** 0.3.2
**Tinker SDK Version Parity Target:** 0.7.0

## Overview

Tinkex is a comprehensive Elixir SDK for the Tinker ML Training and Inference API. It provides a functional, concurrent interface to the Tinker distributed machine learning platform by Thinking Machines Lab, enabling fine-tuning of large language models using LoRA (Low-Rank Adaptation) and high-performance text generation.

## Architecture Summary

### Core Module Structure

```
lib/tinkex/
├── tinkex.ex                    # Main module (thin facade)
├── application.ex               # OTP Application supervisor
├── config.ex                    # Configuration management (647 lines)
├── service_client.ex            # Main entry point, session management (648 lines)
├── training_client.ex           # Training operations (1044 lines)
├── sampling_client.ex           # Inference/sampling operations (552 lines)
├── rest_client.ex               # REST API for checkpoints/sessions (533 lines)
├── future.ex                    # Async polling abstraction (448 lines)
├── tokenizer.ex                 # HuggingFace + Kimi tokenization (380 lines)
├── session_manager.ex           # Session lifecycle + heartbeats
├── checkpoint_download.ex       # Streaming checkpoint downloads
├── cli.ex                       # CLI entrypoint (escript)
├── cli/                         # CLI command implementations
│   ├── parser.ex
│   ├── commands/checkpoint.ex
│   ├── commands/run.ex
│   ├── commands/sample.ex
│   └── commands/version.ex
├── api/                         # Low-level HTTP API layer
│   ├── api.ex                   # Core HTTP client (317 lines)
│   ├── futures.ex
│   ├── headers.ex
│   ├── helpers.ex
│   ├── models.ex
│   ├── rest.ex
│   ├── retry.ex
│   ├── sampling.ex
│   ├── service.ex
│   ├── session.ex
│   ├── training.ex
│   ├── weights.ex
│   └── ...
├── types/                       # 65 type definition files
│   ├── adam_params.ex
│   ├── checkpoint.ex
│   ├── datum.ex
│   ├── forward_backward_output.ex
│   ├── lora_config.ex
│   ├── model_input.ex
│   ├── sample_request.ex
│   ├── sample_response.ex
│   ├── sampling_params.ex
│   ├── tensor_data.ex
│   └── ...
├── regularizers/                # Nx-based regularization primitives
│   ├── l1.ex
│   ├── l2.ex
│   ├── elastic_net.ex
│   ├── entropy.ex
│   ├── kl_divergence.ex
│   └── ...
├── regularizer/                 # Regularizer pipeline infrastructure
│   ├── pipeline.ex
│   ├── executor.ex
│   ├── gradient_tracker.ex
│   └── telemetry.ex
├── training/                    # Training support modules
│   └── custom_loss.ex
├── training_client/             # TrainingClient internals
│   ├── data_processor.ex
│   ├── observer.ex
│   ├── operations.ex
│   ├── polling.ex
│   └── tokenizer.ex
├── telemetry/                   # Observability infrastructure
│   ├── reporter.ex
│   ├── capture.ex
│   ├── provider.ex
│   └── reporter/*.ex
├── recovery/                    # Opt-in crash recovery
│   ├── policy.ex
│   ├── monitor.ex
│   ├── executor.ex
│   └── behaviours.ex
├── files/                       # File handling utilities
│   ├── reader.ex
│   ├── async_reader.ex
│   ├── transform.ex
│   └── types.ex
├── multipart/                   # Multipart form handling
│   ├── encoder.ex
│   └── form_serializer.ex
├── streaming/
│   └── sse_decoder.ex           # Server-sent events decoder
└── (supporting modules)
```

### Total Lines of Code

- **Source files (lib/):** ~20,060 lines across 150+ modules
- **Test files (test/):** ~9,500 lines across 100+ test files
- **Type definitions:** 65 specialized type modules

## Key Components

### 1. ServiceClient (`lib/tinkex/service_client.ex`)

Entry point for all Tinkex operations. GenServer-based with:
- Session management via `Tinkex.SessionManager`
- Telemetry reporter initialization
- Client factory methods for Training/Sampling/REST clients
- Sequencing counters for request ordering

**Key Functions:**
- `start_link/1` (line 34)
- `create_lora_training_client/3` (line 46)
- `create_sampling_client/2` (line 133)
- `create_rest_client/1` (line 182)
- `create_training_client_from_state/3` (line 81)

### 2. TrainingClient (`lib/tinkex/training_client.ex`)

GenServer for training operations with:
- Sequential request sending, concurrent polling
- Automatic data chunking (128 items or 500k tokens)
- Custom loss function support via `forward_backward_custom/4`
- Queue state observer pattern

**Key Functions:**
- `forward_backward/4` (line 161)
- `forward/4` (line 187)
- `forward_backward_custom/4` (line 351)
- `optim_step/3` (line 202)
- `save_weights_for_sampler/3` (line 219)
- `save_state/3` (line 272)
- `load_state/3` (line 286)
- `get_tokenizer/2` (line 100)
- `encode/3` (line 119)
- `decode/3` (line 140)

### 3. SamplingClient (`lib/tinkex/sampling_client.ex`)

Lock-free sampling via ETS with:
- Rate limiting per `{base_url, api_key}` bucket
- Configurable retry logic via `RetryConfig`
- Queue state observation and debounced logging
- Backpressure via `SamplingDispatch`

**Key Functions:**
- `sample/4` (line 103)
- `compute_logprobs/3` (line 118)
- `create_async/2` (line 93)

### 4. RestClient (`lib/tinkex/rest_client.ex`)

Synchronous and async REST operations:
- Session listing and inspection
- Checkpoint CRUD operations
- Training run management
- Archive URL fetching

**Key Functions:**
- `list_sessions/2`, `list_sessions_async/2`
- `list_user_checkpoints/2`, `list_user_checkpoints_async/2`
- `get_checkpoint_archive_url/2`
- `delete_checkpoint/2`
- `publish_checkpoint/2`, `unpublish_checkpoint/2`
- `get_training_run/2`
- `get_weights_info_by_tinker_path/2`
- `get_sampler/2`

### 5. Future (`lib/tinkex/future.ex`)

Polling abstraction for async operations:
- Exponential backoff (1s base, 30s max)
- Queue state telemetry events
- Observer pattern for state changes
- Timeout handling

### 6. Tokenizer (`lib/tinkex/tokenizer.ex`)

HuggingFace + Kimi K2 tokenization:
- ETS-based caching
- Llama-3 gating workaround
- TikToken support via `tiktoken_ex`

### 7. Config (`lib/tinkex/config.ex`)

Configuration management with:
- Environment variable support (`TINKER_*`, `TINKEX_*`)
- Python SDK parity mode
- Proxy configuration
- Cloudflare Access support

### 8. Telemetry (`lib/tinkex/telemetry.ex`)

Comprehensive observability:
- HTTP request/response events
- Queue state changes
- Retry events
- Recovery pipeline events
- Reporter with SESSION_START/SESSION_END

### 9. Recovery (`lib/tinkex/recovery/`)

Opt-in crash recovery:
- Policy-based configuration
- Monitor for run status polling
- Executor for bounded concurrency restarts
- Checkpoint strategy selection

### 10. CLI (`lib/tinkex/cli.ex`)

Escript-based CLI:
- `checkpoint` - Save/list/delete checkpoints
- `run` - Manage training runs
- `sample` - Text generation
- `version` - Build metadata

## API Endpoints Covered

### Session Management
- `POST /api/v1/create_session`
- `POST /api/v1/session_heartbeat`
- `GET /api/v1/sessions`
- `GET /api/v1/sessions/:id`

### Model Operations
- `POST /api/v1/create_model`
- `POST /api/v1/get_info`
- `POST /api/v1/unload_model`

### Training Operations
- `POST /api/v1/forward_backward`
- `POST /api/v1/forward`
- `POST /api/v1/optim_step`
- `POST /api/v1/save_weights`
- `POST /api/v1/load_weights`

### Sampling Operations
- `POST /api/v1/create_sampling_session`
- `POST /api/v1/sample`

### Checkpoint Management
- `GET /api/v1/checkpoints`
- `GET /api/v1/user_checkpoints`
- `GET /api/v1/checkpoint_archive_url`
- `DELETE /api/v1/checkpoints/:id`
- `POST /api/v1/publish_checkpoint`
- `POST /api/v1/unpublish_checkpoint`

### Training Run Management
- `GET /api/v1/training_runs`
- `GET /api/v1/training_runs/:id`

### Futures
- `POST /api/v1/retrieve_future`

### Telemetry
- `POST /api/v1/telemetry`

### Service Discovery
- `GET /api/v1/health`
- `GET /api/v1/capabilities`

## Type System

65 type modules providing:
- Request/response serialization
- JSON encoding via `Jason.Encoder`
- Nx tensor integration via `TensorData`
- Comprehensive typespecs

Key types:
- `Datum`, `ModelInput`, `EncodedTextChunk`, `ImageChunk`
- `SamplingParams`, `SampleRequest`, `SampleResponse`
- `ForwardBackwardRequest`, `ForwardBackwardOutput`
- `AdamParams`, `OptimStepResponse`
- `LoraConfig`, `Checkpoint`, `TrainingRun`
- `QueueState`, `TryAgainResponse`
- Telemetry event types

## Dependencies

```elixir
{:finch, "~> 0.18"}           # HTTP/2 client
{:jason, "~> 1.4"}            # JSON
{:nx, "~> 0.9"}               # Tensor operations
{:exla, "~> 0.9", runtime: false}  # Optional GPU backend
{:tokenizers, "~> 0.5"}       # HuggingFace tokenizers
{:tiktoken_ex, "~> 0.1.0"}    # Kimi K2 tokenizers
{:telemetry, "~> 1.2"}        # Observability
{:semaphore, "~> 1.3"}        # Concurrency control
{:nx_penalties, "~> 0.1.2"}   # Regularization primitives
```

## Test Coverage

- 100+ test files
- ~9,500 lines of tests
- Integration tests for multi-client concurrency
- Unit tests for all major modules
- Parity tests comparing to Python SDK behavior

## Documentation

### Guides (docs/guides/)
- Getting Started
- Tokenization (HuggingFace + Kimi K2)
- Training Loop
- Forward Inference
- Custom Loss Training
- Regularizers
- Checkpoint Management
- Training Persistence
- Futures and Async
- Retry and Error Handling
- Recovery
- Telemetry
- Metrics
- Streaming
- CLI Guide
- API Reference
- Troubleshooting
- Environment Configuration
- Advanced Configuration
- File Uploads
- Model Info/Unload

### Examples (examples/)
30+ example scripts covering:
- Training loops
- Custom loss training
- Sampling
- Checkpoint management
- Recovery
- Telemetry
- Multimodal (vision)
- CLI usage

## Quality Status

- **Dialyzer:** Clean (no type errors)
- **Credo:** Strict mode passing
- **Formatter:** Consistent
- **Escript:** Builds successfully
- **ExDoc:** Generates without warnings
