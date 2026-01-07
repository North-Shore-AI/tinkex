# Manifest Reimagining: Surface Inventory

This document inventories the public SDK surface and server endpoints based on the Tinker Python SDK and the Tinkex examples. This is the baseline for manifest-driven parity.

## 1. Public Client Surface (Python SDK)

### ServiceClient
Primary entry point. Creates sessions, training clients, sampling clients, and rest client.

Key methods (sync + async):
- get_server_capabilities()
- create_lora_training_client(base_model, rank, seed, train_mlp, train_attn, train_unembed, user_metadata)
- create_training_client_from_state(path, user_metadata)
- create_training_client_from_state_with_optimizer(path, user_metadata)
- create_sampling_client(model_path | base_model, retry_config)
- create_rest_client()

Observed behaviors:
- Initializes a session on construction.
- Uses env headers for auth and Cloudflare Access.
- Uses telemetry provider.

### TrainingClient
Represents a model training session. Handles chunking, queue state, custom loss, and optimizer steps.

Key methods (sync + async):
- forward(data, loss_fn, loss_fn_config)
- forward_backward(data, loss_fn, loss_fn_config)
- forward_backward_custom(data, loss_fn)
- optim_step(adam_params)
- save_state(name)
- load_state(path)
- load_state_with_optimizer(path)
- save_weights_for_sampler(name)
- save_weights_and_get_sampling_client(name?, retry_config?)
- create_sampling_client(model_path, retry_config)
- get_info()
- get_tokenizer()

Observed behaviors:
- Chunking by byte size and max chunk length.
- Sequential request ordering via request_id and turn-taking.
- Queue state observer for server backpressure.
- Custom loss uses logprobs to compute gradients client-side.

### SamplingClient
Sampling and logprobs client with retry handling and backpressure.

Key methods (sync + async):
- sample(prompt, num_samples, sampling_params, include_prompt_logprobs, topk_prompt_logprobs)
- compute_logprobs(prompt)

Observed behaviors:
- Sampling backpressure handling (429 returns None, triggers backoff).
- Per-sample retry handler with connection limiting and progress timeout.
- Feature gates via env (`TINKER_FEATURE_GATES`).
- Queue state observer support.

### RestClient
REST operations for runs, checkpoints, sessions, and sampler metadata.

Key methods (sync + async):
- get_training_run(training_run_id)
- get_training_run_by_tinker_path(tinker_path)
- get_weights_info_by_tinker_path(tinker_path)
- list_training_runs(limit, offset)
- list_checkpoints(training_run_id)
- delete_checkpoint(training_run_id, checkpoint_id)
- delete_checkpoint_from_tinker_path(tinker_path)
- get_checkpoint_archive_url(training_run_id, checkpoint_id)
- get_checkpoint_archive_url_from_tinker_path(tinker_path)
- publish_checkpoint_from_tinker_path(tinker_path)
- unpublish_checkpoint_from_tinker_path(tinker_path)
- list_user_checkpoints(limit, offset)
- get_session(session_id)
- list_sessions(limit, offset)
- get_sampler(sampler_id)

### Shared/Support Types
- APIFuture: awaitable future with result() and result_async()
- AwaitableConcurrentFuture: wraps concurrent.futures.Future
- QueueState and QueueStateObserver
- Telemetry and TelemetryProvider
- RetryConfig and RetryHandler

## 2. Public Surface (Elixir Examples)

The examples exercise additional modules beyond the Python SDK:
- Tinkex.ServiceClient, Tinkex.TrainingClient, Tinkex.SamplingClient
- Tinkex.RestClient and Tinkex.API.* (direct REST helpers)
- Tinkex.Telemetry (Reporter, Capture, attach_logger, flush, snapshot)
- Tinkex.Metrics (reset, snapshot, flush)
- Tinkex.QueueStateObserver and QueueStateLogger
- Tinkex.Recovery (Executor, Monitor, Policy)
- Tinkex.Regularizer (Pipeline, Executor, GradientTracker, Telemetry)
- Tinkex.Multipart (Encoder, FormSerializer)
- Tinkex.Files.Transform (multipart demo)
- Tinkex.CLI (programmatic CLI run)
- Tinkex.Tokenizer (encode/decode, model-specific overrides)
- Tinkex.ByteEstimator and ModelInput helpers

These must be preserved in shape and behavior via manifest + Pristine + domain modules.

## 3. Endpoint Inventory

Endpoints observed from `tinker/src/tinker/resources` and RestClient implementation:

| Endpoint | Method | Request Type | Response Type | Notes |
| --- | --- | --- | --- | --- |
| /api/v1/get_server_capabilities | GET | None | GetServerCapabilitiesResponse | Basic capabilities + model list |
| /api/v1/healthz | GET | None | HealthResponse | Health check |
| /api/v1/create_session | POST | CreateSessionRequest | CreateSessionResponse | Idempotency key supported |
| /api/v1/session_heartbeat | POST | SessionHeartbeatRequest | SessionHeartbeatResponse | Heartbeat loop |
| /api/v1/create_sampling_session | POST | CreateSamplingSessionRequest | CreateSamplingSessionResponse | Creates sampling session |
| /api/v1/create_model | POST | CreateModelRequest | UntypedAPIFuture | Future resolves to CreateModelResponse |
| /api/v1/get_info | POST | GetInfoRequest | GetInfoResponse | Direct response |
| /api/v1/unload_model | POST | UnloadModelRequest | UntypedAPIFuture | Future resolves to UnloadModelResponse |
| /api/v1/forward | POST | ForwardRequest | UntypedAPIFuture | Future resolves to ForwardBackwardOutput |
| /api/v1/forward_backward | POST | ForwardBackwardRequest | UntypedAPIFuture | Future resolves to ForwardBackwardOutput |
| /api/v1/optim_step | POST | OptimStepRequest | UntypedAPIFuture | Future resolves to OptimStepResponse |
| /api/v1/asample | POST | SampleRequest | UntypedAPIFuture | Future resolves to SampleResponse |
| /api/v1/load_weights | POST | LoadWeightsRequest | UntypedAPIFuture | Future resolves to LoadWeightsResponse |
| /api/v1/save_weights | POST | SaveWeightsRequest | UntypedAPIFuture | Future resolves to SaveWeightsResponse |
| /api/v1/save_weights_for_sampler | POST | SaveWeightsForSamplerRequest | UntypedAPIFuture | Future resolves to SaveWeightsForSamplerResponse |
| /api/v1/retrieve_future | POST | FutureRetrieveRequest | FutureRetrieveResponse | Used by APIFuture |
| /api/v1/telemetry | POST | TelemetrySendRequest | TelemetryResponse | Telemetry batch ingestion |
| /api/v1/training_runs | GET | None | TrainingRunsResponse | Pagination via limit/offset |
| /api/v1/training_runs/{id} | GET | None | TrainingRun | RestClient get_training_run |
| /api/v1/weights_info | POST | {tinker_path} | WeightsInfoResponse | RestClient get_weights_info_by_tinker_path |
| /api/v1/training_runs/{id}/checkpoints | GET | None | CheckpointsListResponse | List checkpoints |
| /api/v1/training_runs/{id}/checkpoints/{ckpt} | DELETE | None | None | Delete checkpoint |
| /api/v1/training_runs/{id}/checkpoints/{ckpt}/archive | GET | None | CheckpointArchiveUrlResponse | Returns 302 Location; Accept: application/gzip |
| /api/v1/training_runs/{id}/checkpoints/{ckpt}/publish | POST | None | None | Publish checkpoint |
| /api/v1/training_runs/{id}/checkpoints/{ckpt}/publish | DELETE | None | None | Unpublish checkpoint |
| /api/v1/checkpoints | GET | None | CheckpointsListResponse | User-wide checkpoints, paginated |
| /api/v1/sessions | GET | None | ListSessionsResponse | List sessions, paginated |
| /api/v1/sessions/{id} | GET | None | GetSessionResponse | Session detail |
| /api/v1/samplers/{id} | GET | None | GetSamplerResponse | Sampler detail |

Additional endpoint mentioned in examples:
- /api/v1/heartbeat (expected to return 404 in heartbeat_probe example)

## 4. Types Inventory (Python)

Grouped by domain:

Service/session:
- CreateSessionRequest/Response
- SessionHeartbeatRequest/Response
- CreateSamplingSessionRequest/Response
- GetServerCapabilitiesResponse
- HealthResponse
- GetSessionResponse
- ListSessionsResponse
- GetSamplerResponse

Model/training/run metadata:
- CreateModelRequest/Response
- GetInfoRequest/Response
- UnloadModelRequest/Response
- TrainingRun
- TrainingRunsResponse
- Checkpoint
- CheckpointsListResponse
- CheckpointArchiveUrlResponse
- WeightsInfoResponse

Training operations:
- ForwardRequest
- ForwardBackwardRequest
- ForwardBackwardInput
- ForwardBackwardOutput
- OptimStepRequest
- OptimStepResponse
- LossFnType
- LossFnInputs / LossFnOutput
- Adam params types (in Elixir examples)

Sampling operations:
- SampleRequest
- SampleResponse
- SampledSequence
- SamplingParams
- StopReason

Shared infrastructure:
- UntypedAPIFuture
- FutureRetrieveRequest/Response
- RequestID
- RequestFailedResponse
- RequestErrorCategory
- TryAgainResponse

Model input and tensor data:
- ModelInput
- ModelInputChunk
- EncodedTextChunk
- ImageChunk
- ImageAssetPointerChunk
- Datum
- TensorData
- TensorDType

Telemetry:
- TelemetrySendRequest
- TelemetryResponse
- TelemetryBatch
- TelemetryEvent
- GenericEvent
- SessionStartEvent
- SessionEndEvent
- UnhandledExceptionEvent
- Severity
- EventType

## 5. Environment Knobs (Python + Elixir parity)

- TINKER_API_KEY
- TINKER_BASE_URL
- TINKER_TAGS
- TINKER_FEATURE_GATES
- TINKER_TELEMETRY
- TINKER_LOG
- CLOUDFLARE_ACCESS_CLIENT_ID
- CLOUDFLARE_ACCESS_CLIENT_SECRET

Examples also reference:
- TINKER_PROMPT, TINKER_MAX_TOKENS, TINKER_TEMPERATURE, TINKER_NUM_SAMPLES
- TINKER_BASE_MODEL, TINKER_IMAGE_PATH, TINKER_IMAGE_EXPECTED_TOKENS
- TINKER_CHECKPOINT_PATH
- TINKER_UPLOAD_ENDPOINT, TINKER_UPLOAD_FILE

## 6. CLI Surface (Python)

Python CLI commands:
- tinker checkpoint list/info/download
- tinker run list/info
- tinker version

These commands map directly to RestClient endpoints and checkpoint download logic, and should be considered when designing manifest-driven CLI generation.

