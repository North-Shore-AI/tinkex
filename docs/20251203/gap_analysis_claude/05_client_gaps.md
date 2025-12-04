# Client Gaps (ServiceClient, RestClient, SamplingClient)

## ServiceClient

### Parity Status: 95%

| Method | Python | Elixir | Status |
|--------|--------|--------|--------|
| `create_lora_training_client` | Yes | Yes | Parity |
| `create_lora_training_client_async` | Yes | Yes | Parity |
| `create_training_client_from_state` | Yes | Yes | Parity |
| `create_training_client_from_state_async` | Yes | Yes | Parity |
| `create_training_client_from_state_with_optimizer` | No | Yes | Elixir extra |
| `create_sampling_client` | Yes (`retry_config` optional) | Yes (`retry_config` optional) | Parity |
| `create_sampling_client_async` | Yes | Yes | Parity |
| `create_rest_client` | Yes | Yes | Parity |
| `get_server_capabilities` | Yes | Yes | Parity |
| `get_telemetry` | Yes | Yes | Different |

### Elixir Improvements

1. **Explicit timeout control:** `call_timeout`, `load_timeout` parameters
2. **Optimizer convenience methods:** Dedicated `_with_optimizer` variants
3. **Server capability checks:** Before operations
4. **Parity mode:** Optional `parity_mode: :python`/`TINKEX_PARITY=python` to match Python retry/timeout defaults

## RestClient

### Parity Status: 95%

| Endpoint | Python | Elixir | Status |
|----------|--------|--------|--------|
| `get_training_run` | Yes | Yes | Parity |
| `get_training_run_by_tinker_path` | Yes | Yes | Parity |
| `list_training_runs` | Yes | Yes | Parity |
| `list_checkpoints` | Yes | Yes | Parity |
| `list_user_checkpoints` | Yes | Yes | Parity |
| `get_checkpoint_archive_url` | Yes | Yes | Parity |
| `delete_checkpoint` | Yes | Yes | Parity |
| `publish_checkpoint` | Yes | Yes | Parity |
| `unpublish_checkpoint` | Yes | Yes | Parity |
| `get_weights_info_by_tinker_path` | Yes | Yes | Parity |
| `get_session` | Yes | Yes | Parity |
| `list_sessions` | Yes | Yes | Parity |
| `get_sampler` | Yes | Yes | Parity |
| `get_telemetry` | Yes | Different | Different |

### Architectural Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| Return type | `ConcurrentFuture[T]` | `{:ok, T} \| {:error, E}` |
| Retry handling | `execute_with_retries` | API layer handles |
| Pool management | Pool type per request | Pool type per request |
| Error documentation | Detailed HTTP codes | Basic error types |

### Minor Gaps

1. **Retry at client level:** Python exposes `execute_with_retries`, Elixir handles in API layer
2. **Error code documentation:** Python documents specific HTTP error scenarios

## SamplingClient

### Parity Status: 100%

| Method | Python | Elixir | Status |
|--------|--------|--------|--------|
| `sample` | Yes | Yes | Parity |
| `sample_async` | Implicit | Yes | Parity |
| `compute_logprobs` | Yes | Yes | Parity |
| `get_telemetry` | Yes | Yes | Parity |

### Implementation Notes

Both implementations:
- Support `num_samples`, `sampling_params`, `prompt_logprobs`, `topk_prompt_logprobs`
- Return `SampleResponse` with `sequences` and optional logprobs
- Handle backpressure via `X-Tinker-Sampling-Backpressure` header

## HTTP Client Comparison

### Retry Strategy

| Aspect | Python | Elixir |
|--------|--------|--------|
| Initial delay | 500ms | 500ms |
| Max delay | 10s | 10s |
| Backoff | `delay * 2^attempt` | `delay * 2^attempt` |
| Jitter | 0.75-1.0x | 0.75-1.0x |
| Retryable codes | 408, 409, 429, 5xx | 408, 409, 429, 5xx |
| Max retries | 10 (defaults) | 2 by default; 10 when `parity_mode: :python` or overriding opts |

### Headers

Both send:
- `X-Stainless-*` SDK info headers
- `Authorization: Bearer <key>`
- `CF-Access-*` Cloudflare headers
- `User-Agent`
- `Content-Type: application/json`

### Connection Pooling

| Aspect | Python | Elixir |
|--------|--------|--------|
| Pool types | `TRAIN`, `SAMPLING` | `:training`, `:sampling` |
| Max connections | 1000 | Configurable |
| Keep-alive | 20 | Finch defaults |

## API Module Comparison

### Endpoint Coverage

| Module | Python | Elixir | Parity |
|--------|--------|--------|--------|
| Service | `get_server_capabilities`, `health`, `create_session` | Same | 100% |
| Models | `create_model`, `get_info`, `unload` | Same | 100% |
| Training | `forward`, `forward_backward`, `optim_step` | Same + futures | 100% |
| Sampling | `asample` | Same | 100% |
| Weights | `save`, `load`, `save_for_sampler` | Same + typed variants | 100% |
| Rest | All checkpoint/run endpoints | Same | 100% |
| Telemetry | `send_batch` | `send_batch` | Parity |

## Recommendations

### Priority 1
1. Document timeout/retry parity mode so users can match Python defaults easily.

### Priority 2
2. Document HTTP error codes in RestClient.
3. Keep `retry_config` surfaced for SamplingClient (already supported).

### Files Reference

- Python: `tinker/lib/public_interfaces/*.py`
- Elixir: `lib/tinkex/service_client.ex`, `lib/tinkex/rest_client.ex`, `lib/tinkex/sampling_client.ex`
