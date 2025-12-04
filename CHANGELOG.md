# Changelog

All notable changes to this project will be documented in this file.

# Changelog

All notable changes to this project will be documented in this file.

## [0.1.20] - 2025-12-03

### Changed
- **Default parity:** Config now defaults to Python parity (`timeout: 60_000`, `max_retries: 10`); use `parity_mode: :beam` or `TINKEX_PARITY=beam` to opt back into the 120s/2-retry defaults.
- **Datum dtype parity:** `loss_fn_inputs` lists use the Python `_key_to_type` map (`target_tokens` → int64; `weights`/`advantages`/`logprobs`/`clip_*` → float32) and raise on list values under unknown keys; typed tensors remain allowed for custom keys.

### Added
- Tests covering the key-based dtype map and error behavior for unknown list keys; docs/README bumped to 0.1.20.

## [0.1.19] - 2025-12-03

### Added
- **Metric reducer parity:** `hash_unordered` reducer in `Tinkex.MetricsReduction` for order-insensitive hash aggregation, matching Python's chunked metrics behavior.
- **ModelInput builders:** `empty/0`, `append/2`, and `append_int/2` helpers for building ModelInput incrementally. `append_int/2` is token-aware: extends the last EncodedTextChunk when possible, otherwise creates a new chunk.
- **TensorData.tolist/1:** Returns the flat data list for API parity with Python's `TensorData.tolist()`.

### Documentation
- Gap analysis docs corrected per review: parity matrices now reflect Elixir regularizer/telemetry support, sampling `retry_config`, Python-only tensor backends, and the remaining reducer/model-input gaps.
- Captured verification results in `docs/20251203/gap_analysis_claude/REVIEW_RESULTS.md` and refreshed README/install snippets/prompts to 0.1.19 for consistency.
- Updated gap analysis to mark `hash_unordered` reducer and ModelInput builders as resolved.

## [0.1.18] - 2025-12-03

### Added
- Public `Tinkex.Types.ParsedCheckpointTinkerPath` helper exposes structured `tinker://` components and user-category errors; REST helpers and CLI checkpoint commands reuse it for consistent validation.

### Changed
- `feature_gates` now default to `["async_sampling"]` when opts/app/env do not supply a value (Python parity); env snapshots/config defaults reflect the new baseline while keeping opts > app config > env precedence.
- Environment and checkpoint guides note the default gate and the new path parser; README/install snippets bump to 0.1.18.

## [0.1.17] - 2025-12-03

### Added
- Log-level parity: `TINKER_LOG` / `config :tinkex, :log_level` now set Logger at application start (Python parity) while keeping HTTP header dumps redacted unless explicitly enabled.
- Telemetry capture: Service/Training/Sampling client entrypoints wrap exceptions through `Tinkex.Telemetry.Capture/Reporter` and emit session-end events on fatal paths.
- Config knobs: Added `default_headers`, `default_query`, custom `http_client`/`http_pool` overrides, and env keys (`TINKEX_DEFAULT_HEADERS`, `TINKEX_DEFAULT_QUERY`, `TINKEX_HTTP_CLIENT`, `TINKEX_HTTP_POOL`) with opts > app config > env precedence and secret redaction for headers.

### Changed
- Session heartbeats pin a 10_000ms timeout with `max_retries: 0` for Python parity while preserving debounce/warning semantics.
- Finch pool isolation now routes per pool type (session/training/sampling/futures/telemetry) with Python-aligned sizes and deterministic pool names derived from `http_pool` + `base_url`.

## [0.1.16] - 2025-12-03

### Added
- CLI parity for checkpoint/run management: `--format json`/`--json` output with `total`/`shown` counts, checkpoint list run filters, `--limit 0` fetch-all semantics, and pagination progress indicators for lists.
- Checkpoint info now surfaces checkpoint type, size, visibility, timestamps, and training run IDs alongside base model/LoRA metadata; run list/info surface owner, LoRA rank, statuses, last checkpoints, and user metadata in both table and JSON formats.

### Changed
- Checkpoint pagination cursors now use the typed `Tinkex.Types.Cursor` struct; CLI table outputs include the richer checkpoint/run fields.
- Examples and docs updated for new CLI flags and cursor accessors; version bumped to 0.1.16 in mix/README/getting_started.

## [0.1.15] - 2025-12-03

### Added
- Checkpoint archive responses now surface `expires`; `CheckpointArchiveUrlResponse` parses timestamps and Rest/RestClient expose ID-based archive/delete helpers alongside tinker-path variants.
- Sampling backpressure parity: dispatch semaphore (default 400) gates sampling dispatch and 429s without `Retry-After` trigger a 1s shared backoff.

### Changed
- `list_user_checkpoints/2` now defaults to `limit: 100` (Python parity).
- `RetryConfig` default `max_connections` raised to 1000 to match Python connection limits.
- ServiceClient validation requires `base_model` or `model_path` for sampling clients and at least one of `train_mlp`/`train_attn`/`train_unembed` when creating training clients.

### Documentation
- README/version bump; checkpoint management guide covers archive expirations + ID helpers; retry guide reflects the new `max_connections` default.

## [0.1.14] - 2025-12-02

### Added
- `ServiceClient.create_training_client_from_state_with_optimizer/3` (+ async) for weight+optimizer restore with documented weights-only default on the existing helper.
- CLI `checkpoint delete` now accepts multiple `tinker://` paths with upfront validation, a single confirmation prompt (`--yes` to skip), per-path progress output, and aggregated failure reporting.
- New examples:
  - `examples/multimodal_resume_and_cleanup.exs` (multimodal with `expected_tokens`, optimizer resume helper, multi-delete CLI usage)
  - `examples/checkpoint_multi_delete_live.exs` (creates two checkpoints and deletes both live with one CLI call)
  - `examples/llama3_tokenizer_override_live.exs` (live Llama-3 sampling plus encode/decode using the override tokenizer)
- DELETE HTTP responses now accept empty bodies without raising JSON decode errors, fixing CLI multi-delete against endpoints that return 204/empty responses.
- Retry handler no longer trips progress timeout before the first attempt (attempt 0 is allowed to run).

### Changed
- **Image chunks:** removed `height`/`width`/`tokens` fields from `ImageChunk` and `ImageAssetPointerChunk`, added `expected_tokens`, and made `.length/1` raise when missing; JSON encoders now match Python. ModelInput length follows the new contract and training batching counts images by base64/location length to avoid missing expected tokens.
- **Retries:** default progress timeout increased to 120 minutes and retries now run until that timeout (no attempt cap by default); RetryConfig/RetryHandler defaults and docs updated.
- **Tokenizer override:** Llama-3 models now use `thinkingmachineslabinc/meta-llama-3-tokenizer` to avoid gated downloads.
- Documentation updates for CLI multi-delete, optimizer resume helper, retry defaults, expected_tokens schema, and new example references.

## [0.1.13] - 2025-12-01

Documentation release: clarifies project status and attribution.

### Documentation

- Added disclaimer clarifying Tinkex is an independent, community-maintained project not affiliated with or endorsed by Thinking Machines Lab.
- Added links to official [Thinking Machines Lab](https://thinkingmachines.ai/) homepage and [Tinker documentation](https://tinker-docs.thinkingmachines.ai/).
- Improved intro section clarity around Tinker's provenance.

## [0.1.12] - 2025-11-27

Custom loss training now mirrors the Python SDK while adding multipart uploads, proxy-aware HTTP, streaming checkpoint downloads, queue observers, and richer capabilities metadata.

### Added

- **Custom loss training parity**: `TrainingClient.forward_backward_custom/4` preserves per-datum logprobs as Nx tensors, computes gradients locally, sends them back as synthetic weights so the backend trains, and returns `ForwardBackwardOutput` ready for `optim_step/2`.
- **Structured capabilities metadata**: Capabilities responses expose `SupportedModel` structs with `model_id`, `model_name`, and `arch`; `model_names/1` offers backward-compatible name extraction and the capabilities example now prints the full metadata.
- **Multipart uploads**: Tinkex.API.post/3 normalizes file inputs, flattens nested bodies into bracketed form fields, generates multipart boundaries, and sets `Content-Type` automatically when `:files` are present. Added path-based upload helpers and a runnable multipart demo.
- **Queue observers**: Sampling and training clients register queue state observers that integrate with `Future.poll/2`, emitting debounced warnings with human-readable reasons for rate limiting or capacity throttling, aligned with the Python SDK.
- **Proxy-aware HTTP**: `Tinkex.Config` now wires proxy settings through Finch pool configuration, supporting tuple proxies plus `TINKEX_PROXY` and `TINKEX_PROXY_HEADERS` while masking credentials in inspect/log output.

### Changed

- **Checkpoint downloads**: Archive downloads stream via Finch instead of loading into memory, maintaining O(1) memory usage while preserving progress callbacks and extraction semantics.

### Documentation

- Guides and examples refreshed for custom loss training, streaming checkpoint downloads, multipart uploads, async client creation, and the richer server capabilities response.

## [0.1.11] - 2025-11-27

Achieves full behavioral parity with Python SDK (tinker v1.x) across retry semantics, HTTP connection pooling, and missing type definitions.

### Breaking Changes

- **`ServiceClient.create_lora_training_client/2` → `/3`**: `base_model` is now a required second argument instead of being passed in opts:
  ```elixir
  # Before (0.1.10)
  create_lora_training_client(service, base_model: "meta-llama/Llama-3.1-8B")

  # After (0.1.11)
  create_lora_training_client(service, "meta-llama/Llama-3.1-8B", opts)
  ```

- **`TrainingClient.save_weights_for_sampler/2` → `/3`**: `name` is now a required second argument mapping to the server `path` field:
  ```elixir
  # Before (0.1.10)
  save_weights_for_sampler(training, name: "checkpoint-001")

  # After (0.1.11)
  save_weights_for_sampler(training, "checkpoint-001", opts)
  ```

### Added

#### Python SDK Retry Parity
- HTTP retry now matches Python `_base_client.py` behavior:
  - Retries on 408/409/429/5xx (added 409 Conflict support)
  - Uses Python jitter formula (0.75–1.0 range) instead of ±25%
  - Caps delay at 10s instead of 8s
  - Removes 30s wall-clock timeout; `max_retries` governs retry attempts
- New `Tinkex.API.RetryConfig` module with Python parity formulas

#### HTTP Pool Parity
- Pool defaults now align with Python's `httpx.Limits`:
  - `pool_size: 50`, `pool_count: 20` for 1000 total connections
  - Matches Python `max_connections=1000`
- `Tinkex.Env.pool_size/1` and `pool_count/1` for `TINKEX_POOL_SIZE`/`TINKEX_POOL_COUNT` env vars
- `Tinkex.Application.default_pool_size/0` and `default_pool_count/0` exposed; `Application.start/2` respects pool config from env or app config

#### Missing Type Structs
- `FutureRetrieveRequest` - request type for future polling
- `RequestFailedResponse` - structured error response type
- `SessionHeartbeatRequest` / `SessionHeartbeatResponse` - heartbeat wire types
- `TelemetryResponse` - telemetry send response type
- `Tinkex.Types.TypeAliases` module for `ModelInputChunk`, `LossFnInputs`, `LossFnOutput` union types
- `SupportedModel` - structured model metadata with `model_id`, `model_name`, and `arch` fields

#### Server Capabilities Type Improvement
- `GetServerCapabilitiesResponse.supported_models` now returns `[SupportedModel.t()]` instead of `[String.t()]`
- Preserves full model metadata (`model_id`, `model_name`, `arch`) from the API response
- Added `GetServerCapabilitiesResponse.model_names/1` convenience helper for backward-compatible name extraction
- Backward compatible: parser handles both object and string formats

#### API Helpers
- `Tinkex.API.Helpers.with_raw_response/1` - Python-style raw response access pattern
- `Tinkex.API.Helpers.with_streaming_response/1` - Python-style streaming response access pattern

#### TensorDtype Helpers
- `TensorDtype.from_nx_type/1` now emits warnings for float64→float32 downcast and u64→int64 overflow
- `TensorDtype.from_nx_type_quiet/1` - silent conversion without warnings
- `TensorDtype.check_precision_loss/1` - explicit precision loss checking

### Fixed

- **Sampling nil-field fix**: `SampleRequest` JSON encoder now omits `nil` for optional fields like `prompt_logprobs` instead of encoding as `null` (server rejects null). Uses `drop_nil?: true` in Transform layer.
- **Tokenizer resolution**: Now strips `/variant` suffix from three-part model names; added Kimi K2 tokenizer with pinned revision
- **CLI checkpoint command**: Generates default checkpoint names from `base_model` when `--name` not provided
- **Example bug fixes**:
  - Fixed `.samples` → `.sequences` in examples and docs (field was renamed in response type)
  - Fixed `prompt.tokens` → `prompt.chunks[0].tokens` access pattern in `telemetry_live.exs`

### Changed

- Training loop example adds detailed step timing and clearer output formatting

### Documentation

- Updated all guides to use new `create_lora_training_client/3` and `save_weights_for_sampler/3` signatures
- Added `docs/20251126/gaps_05/gap-analysis-python-to-elixir.md`: comprehensive gap analysis showing feature-complete parity with Python SDK
- Added `docs/20251126/gaps_05/remaining_gaps_fix_plan.md`: concrete remaining gaps and fixes to reach 100% parity
- Updated version references from 0.1.10 to 0.1.11 in README and mix.exs

### Tests

- Added `test/tinkex/api/retry_parity_test.exs`: validates Python retry formula, jitter range (0.75–1.0), 10s delay cap, and 409 retry support
- Added `test/tinkex/pool_config_parity_test.exs`: verifies `pool_size × pool_count = 1000` matching Python `max_connections`
- Added `test/tinkex/types/missing_types_parity_test.exs`: round-trip tests for new type structs
- Added `test/tinkex/api/helpers_test.exs`: `with_raw_response` and `with_streaming_response` helpers
- Updated integration tests for new TrainingClient API signatures

## [0.1.10] - 2025-11-27

### Added

#### RestClient Async API
- All REST methods now have `*_async` variants returning `Task.t()` for parallel requests:
  - `get_session_async/2`, `list_sessions_async/2`, `get_sampler_async/2`
  - `get_weights_info_by_tinker_path_async/2`, `list_checkpoints_async/2`
  - `list_user_checkpoints_async/2`, `get_checkpoint_archive_url_async/2`
  - `delete_checkpoint_async/2`, `get_training_run_async/2`
  - `get_training_run_by_tinker_path_async/2`, `list_training_runs_async/2`
  - `publish_checkpoint_async/2`, `unpublish_checkpoint_async/2`
  - Plus convenience aliases (`delete_checkpoint_by_tinker_path_async/2`, `publish_checkpoint_from_tinker_path_async/2`, etc.)

#### TrainingClient Tokenizer Helpers
- `TrainingClient.get_tokenizer/2` - fetches tokenizer using model info with ETS caching
- `TrainingClient.encode/3` - convenience wrapper for tokenizer encoding from training client
- `TrainingClient.decode/3` - convenience wrapper for tokenizer decoding from training client

#### Config Parity Mode
- New `parity_mode: :python` option to align timeout/retry defaults with Python SDK:
  - Set via options: `Tinkex.Config.new(parity_mode: :python)`
  - Set via application config: `config :tinkex, parity_mode: :python`
  - Set via environment variable: `TINKEX_PARITY=python`
- Python parity defaults: `timeout: 60_000` (1 min), `max_retries: 10` (11 total attempts)
- BEAM-conservative defaults (unchanged): `timeout: 120_000` (2 min), `max_retries: 2` (3 total attempts)
- New helper functions: Tinkex.Config.default_timeout/0, Tinkex.Config.default_max_retries/0, Tinkex.Config.python_timeout/0, Tinkex.Config.python_max_retries/0
- `Tinkex.Env.parity_mode/1` - reads `TINKEX_PARITY` environment variable

#### Typed Telemetry Events
- New structs under `Tinkex.Types.Telemetry`:
  - `EventType` - enum for SESSION_START, SESSION_END, UNHANDLED_EXCEPTION, GENERIC_EVENT
  - `Severity` - enum for DEBUG, INFO, WARNING, ERROR, CRITICAL
  - `GenericEvent`, `SessionStartEvent`, `SessionEndEvent`, `UnhandledExceptionEvent` - typed event structs
  - `TelemetryEvent` - union type with `to_map/1`, `from_map/1`, `event_type/1` dispatch helpers
  - `TelemetryBatch` - batch grouping with `to_list/1`, `from_list/2`, `size/1`
  - `TelemetrySendRequest` - request structure for API transmission

### Changed

- `Tinkex.Telemetry.Reporter` now emits typed structs internally and converts to wire format maps on send
- `Tinkex.Env.snapshot/1` now includes `parity_mode` field

### Tests

- Added `test/tinkex/types/telemetry_types_test.exs` - 53 tests for telemetry type round-trips and conversions
- Added `test/tinkex/rest_client_async_test.exs` - 14 tests for async REST client with Bypass
- Added `test/tinkex/training_client_tokenizer_test.exs` - 11 tests for tokenizer helper wiring
- Added `test/tinkex/config_parity_test.exs` - 10 tests for parity mode configuration
- Extended `test/tinkex/env_test.exs` - 4 tests for `parity_mode/1`

## [0.1.9] - 2025-11-26

### Added

#### Env and Configuration Parity
- **Tinkex.Env**: Introduced as the single source of truth for environment-driven configuration knobs.
- **Config precedence**: Wired `Tinkex.Config.new/1` to use opts > app config > env > defaults.
- **New env vars**: Support for `TINKER_TAGS`, `TINKER_FEATURE_GATES`, `TINKER_TELEMETRY`, `TINKER_LOG`, `TINKEX_DUMP_HEADERS`, `CLOUDFLARE_ACCESS_CLIENT_ID`, and `CLOUDFLARE_ACCESS_CLIENT_SECRET`.
- **Secret masking**: Added masking for API key and Cloudflare secrets in inspect and HTTP dumps.
- **Config accessors**: Exposed `tags`, `feature_gates`, `telemetry_enabled?`, `log_level`, `dump_headers?` on `Tinkex.Config`; documented in `environment_configuration.md`.

#### Cloudflare Access and Header Redaction
- **CF headers**: Inject `CF-Access-Client-Id` and `CF-Access-Client-Secret` from config/env into all requests via `build_headers/4`.
- **Redaction**: Redact both `x-api-key` and `cf-access-client-secret` in request dump logs.
- **Tests**: Added tests asserting Cloudflare headers are present when configured and that secrets never appear in logs.

#### Heartbeat Path and SessionManager Robustness
- **Heartbeat alignment**: Changed Elixir heartbeat endpoint to POST `/api/v1/session_heartbeat` (matching Python) instead of `/api/v1/heartbeat`.
- **Warning threshold**: Introduced `heartbeat_warning_after_ms` (default 120,000 ms) and emit warnings when heartbeats have failed for longer than this window.
- **Resilient sessions**: Stop silently dropping sessions on 4xx; keep sessions alive and continue retrying while surfacing failures via logs.
- **ETS persistence**: Persist session state in a protected ETS table `:tinkex_sessions` and reload on `SessionManager` init so restarts preserve heartbeat state.
- **Timer cleanup**: Ensure heartbeat timers are tracked and cancelled on terminate.

#### Sampling Retries, Backpressure, and Connection Limiting
- **RetryConfig**: Added `Tinkex.RetryConfig` with `max_retries`, `base_delay_ms`, `max_delay_ms`, `jitter_pct`, `progress_timeout_ms`, `max_connections`, and `enable_retry_logic`.
- **SamplingClient integration**: Integrated `RetryConfig` into `SamplingClient`; allow per-client configs and a simple keyword shorthand `retry_config: [...]`.
- **RetryHandler**: Use `RetryHandler.from_config/1` to wrap sampling requests with retry logic matching Python semantics (0.5s base, 10s cap, 25% jitter, long progress timeout).
- **RetrySemaphore**: Introduced `Tinkex.RetrySemaphore` to cap concurrent sampling attempts per client using an ETS-backed semaphore and `max_connections`.
- **Retry defaults**: Removed hardcoded `max_retries: 0` in Sampling API; now respects configured `max_retries` from `RetryConfig` or opts.
- **Tests**: Added tests for `RetryConfig`, `RetryHandler` jitter, `RetrySemaphore`, and integration cases for enabled/disabled retries.

#### Training Persistence and Checkpoint Workflows
- **LoadWeightsRequest fix**: Fixed wire protocol by renaming `load_optimizer_state` to `optimizer` to match Python and server expectations.
- **TrainingClient.save_state/3**: Implemented to save training checkpoints via `/api/v1/save_weights`, returning `SaveWeightsResponse` with `tinker://` path.
- **TrainingClient.load_state/3**: Implemented to load weights via `/api/v1/load_weights`.
- **TrainingClient.load_state_with_optimizer/3**: Implemented to load weights with optimizer state.
- **ServiceClient.create_training_client_from_state/3**: Uses `RestClient.get_weights_info_by_tinker_path/2` to derive base_model and LoRA rank, creates a `TrainingClient`, then loads the checkpoint.
- **SaveWeightsForSamplerResponse**: Extended to support both `path` and `sampling_session_id`-only responses, matching ephemeral sampler flows.
- **TrainingClient.save_weights_and_get_sampling_client/2**: Added to save sampler weights or ephemeral sessions and return a `SamplingClient`.
- **TrainingClient.save_weights_and_get_sampling_client_sync/2**: Synchronous helper variant.
- **Docs & examples**: Added `training_persistence.md` guide and examples `training_persistence_live.exs` and `save_weights_and_sample.exs`.

#### Model Info and Unload Endpoints
- **Types**: Added `ModelData`, `GetInfoRequest`, `GetInfoResponse`, `UnloadModelRequest`, and `UnloadModelResponse` types.
- **API endpoints**: Implemented `Tinkex.API.Models.get_info/2` and `unload_model/2` on top of `/api/v1/get_info` and `/api/v1/unload_model`.
- **TrainingClient.get_info/1**: Wired to the typed `get_info` endpoint, returning `GetInfoResponse` for tokenizer_id and architecture.
- **TrainingClient.unload_model/1**: Wired to the `unload_model` endpoint with support for both immediate and future-based responses.
- **Example & guide**: Added `model_info_and_unload.exs` example and `model_info_unload.md` guide.

#### REST Surface Parity and Tinker-Path Helpers
- **RestClient.get_sampler/2**: Exposed on top of `Rest.get_sampler/2`, returning typed `GetSamplerResponse`.
- **RestClient.get_weights_info_by_tinker_path/2**: Returns `WeightsInfoResponse`.
- **New helpers**:
  - `get_training_run_by_tinker_path/2`
  - `delete_checkpoint_by_tinker_path/2`
  - `publish_checkpoint_from_tinker_path/2`
  - `unpublish_checkpoint_from_tinker_path/2`
  - `get_checkpoint_archive_url_by_tinker_path/2`
- **Docs**: Extended `checkpoint_management.md` to use the new helpers.

#### Telemetry and Task Supervision
- **Task.Supervisor**: Introduced top-level `Tinkex.TaskSupervisor` and route telemetry HTTP sends through it instead of `Task.start/1`.
- **Child specs**: Made `SamplingClient` and `TrainingClient` `child_spec` use `restart: :temporary` to avoid restart storms and match user-managed lifecycle semantics.
- **Telemetry toggle**: Keep `telemetry_enabled?` driven by `Tinkex.Config.telemetry_enabled?` with `TINKER_TELEMETRY` as the env fallback.

#### Docs, Guides, and Examples
- **New guides**: `environment_configuration.md`, advanced configuration updates describing env precedence, Cloudflare Access, and heartbeat tuning.
- **Retry guide**: Extended `retry_and_error_handling.md` with `SamplingClient` `retry_config` details and connection limiting behavior.
- **Persistence guides**: Added `training_persistence.md` and `model_info_unload.md` focused on checkpoints, optimizer state, and model metadata APIs.
- **Examples README**: Updated `examples/README.md` and `run_all.sh` to include new examples: `heartbeat_probe.exs`, `model_info_and_unload.exs`, `training_persistence_live.exs`, `save_weights_and_sample.exs`.

### Tests

- Added unit tests for `Env`, `Config` precedence, Cloudflare redaction, `RetryConfig`, `RetryHandler`, `RetrySemaphore`, `ModelInfo` and `Unload` types, `LoadWeightsRequest` wire format, and updated rate limiter behavior.
- Added integration tests covering:
  - Multi-client concurrency with `retry_config` enabled/disabled
  - Sampling workflows under rate limits and transient errors
  - Training loop + checkpoint flows with save/load and `from_state`
  - `SessionManager` heartbeat path and warning behavior

## [0.1.8] - 2025-11-26

### Added

- **NotGiven + transform layer**: Introduced omit/not-given sentinels and request transformation with aliasing/formatting to mirror Python serialization semantics.
- **REST client parity**: Added `RestClient.get_sampler/2`, `RestClient.get_weights_info_by_tinker_path/2`, and tinker-path convenience aliases (training run, delete/archive/publish/unpublish) to match Python ergonomics.
- **Response wrappers & SSE**: Added `Tinkex.API.Response` with metadata (headers, status, URL, elapsed, retries) plus SSE decoding helpers and streaming response support for event-stream endpoints.
- **Typed responses**: New structs for weight save/load responses, training runs, cursors, server capabilities, and health checks; REST training run endpoints now decode into typed structs.
- **Service endpoints**: Implemented `/api/v1/get_server_capabilities` and `/api/v1/healthz` in `Tinkex.API.Service`.
- **Sampling helper**: Added `SamplingClient.compute_logprobs/3` convenience for prompt token logprobs.
- **CLI management**: Added checkpoint management subcommands (list/info/publish/unpublish/delete/download) and run management subcommands (list/info) with corresponding tests and docs.
- **Live example**: New `examples/live_capabilities_and_logprobs.exs` showing capabilities + health probes and prompt logprobs; included in `examples/run_all.sh`.
- **Centralized env + Cloudflare headers**: `Tinkex.Env` feeds `Tinkex.Config`/HTTP defaults (API key, base URL, tags, feature gates, telemetry, log level, dump headers, Cloudflare Access) with redaction helpers, matching Python env behavior and ADR-002.

### Fixed

- `RestClient` training run endpoints now return typed structs, and publish/unpublish checkpoint helpers are wired through REST with CLI wrappers.
- **Session heartbeat parity**: Heartbeats now POST to `/api/v1/session_heartbeat` (matching Python), continue retrying on all errors, and emit warnings after sustained failure windows instead of silently dropping sessions on 4xx. Added a guarded probe script to verify `/api/v1/session_heartbeat` = 200 and `/api/v1/heartbeat` = 404 against a real server.

## [0.1.7] - 2025-11-26

### Added

- **Telemetry Reporter**: New `Tinkex.Telemetry.Reporter` batches client-side telemetry (session start/end, HTTP, queue, custom events, exceptions) with configurable flush interval/threshold, HTTP timeout, and retry/backoff, plus wait-until-drained semantics and fatal-exception flushing. `ServiceClient` boots a reporter automatically and exposes it via `telemetry_reporter/1`; telemetry can be disabled with `TINKER_TELEMETRY=0`.
- **Telemetry examples**: Added `examples/telemetry_live.exs` and `examples/telemetry_reporter_demo.exs`, documented in READMEs and included in `examples/run_all.sh`, showcasing reporter lifecycle, custom events, retries, drain/wait, and graceful shutdown.
- **Coverage**: Added `test/tinkex/telemetry_reporter_test.exs` for reporter lifecycle, backoff, exception handling, and drain semantics; tests disable backend telemetry via `TINKER_TELEMETRY=0`.

### Changed

- **Telemetry attribution**: Sampling/training/client APIs now merge optional `:telemetry_metadata` (including session, sampling session, and model sequence IDs) into HTTP telemetry so backend events are session-scoped; telemetry POSTs honor configurable timeouts.
- **Docs**: README highlights the telemetry reporter, backend shipping flow, and metadata tagging; installation snippet bumped to `~> 0.1.7`.

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
