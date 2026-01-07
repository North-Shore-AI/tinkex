# Manifest Reimagining: Manifest Schema Proposal

This document proposes a manifest schema that can fully encode the SDK surface and cross-cutting features identified in the inventory. The schema is designed for code generation and to be the single source of truth.

## 1. Schema Goals
- Express all endpoints with request/response types.
- Attach reusable feature blocks per endpoint.
- Support composite flows (multi-step operations).
- Provide generation metadata for client modules and method shapes.
- Allow environment-driven defaults and overrides.

## 2. Top-Level Structure (Proposed)

```yaml
schema_version: 1
service:
  name: tinker
  base_url:
    default: https://tinker.thinkingmachines.dev/services/tinker-prod
    env: TINKER_BASE_URL
  auth:
    type: api_key
    header: X-API-Key
    env: TINKER_API_KEY

clients:
  service:
    module: Tinkex.ServiceClient
    resource: service
    flows:
      - name: create_lora_training_client
        doc: Create training client with LoRA config
        steps:
          - call: models.create
          - await_future: CreateModelResponse
          - build_client: TrainingClient
  training:
    module: Tinkex.TrainingClient
    resource: training
  sampling:
    module: Tinkex.SamplingClient
    resource: sampling
  rest:
    module: Tinkex.RestClient
    resource: rest

features:
  retry_standard:
    type: retry_policy
    retry_on:
      status: [408, 409, 429, 500-599]
      exceptions: [connection_timeout, connection_error]
    backoff:
      type: exponential
      base_ms: 500
      max_ms: 30000
  retry_sampling:
    type: retry_handler
    max_connections: 100
    progress_timeout_ms: 7200000
    jitter_factor: 0.25
  futures:
    type: promise_result
    retrieve_endpoint: futures.retrieve
    try_again_field: type
    try_again_value: try_again
    error_field: error
    category_field: category
    queue_state_field: queue_state
    queue_state_reason_field: queue_state_reason

endpoints:
  service.get_server_capabilities:
    method: GET
    path: /api/v1/get_server_capabilities
    response: GetServerCapabilitiesResponse
    features: [retry_standard]

  training.forward:
    method: POST
    path: /api/v1/forward
    request: ForwardRequest
    response: ForwardBackwardOutput
    features: [retry_standard, futures]

  sampling.sample:
    method: POST
    path: /api/v1/asample
    request: SampleRequest
    response: SampleResponse
    features: [retry_sampling, futures, sampling_backpressure]
    headers:
      X-Tinker-Sampling-Backpressure: "1"

  telemetry.send:
    method: POST
    path: /api/v1/telemetry
    request: TelemetrySendRequest
    response: TelemetryResponse
    features: [retry_standard]

  futures.retrieve:
    method: POST
    path: /api/v1/retrieve_future
    request: FutureRetrieveRequest
    response: FutureRetrieveResponse
    features: [retry_standard]

  checkpoints.archive_url:
    method: GET
    path: /api/v1/training_runs/{model_id}/checkpoints/{checkpoint_id}/archive
    response: CheckpointArchiveUrlResponse
    features: [retry_standard]
    headers:
      accept: application/gzip
    response_handler: redirect_location
```

Notes:
- The manifest can be YAML or JSON, but must be parsed deterministically.
- `features` are reusable blocks applied to endpoints.
- `clients` provide codegen hints for module names and flow definitions.

## 3. Features: Declarative Building Blocks

### 3.1 Retry Policy Feature
```yaml
retry_standard:
  type: retry_policy
  retry_on:
    status: [408, 409, 429, 500-599]
    exceptions: [connection_timeout, connection_error]
  backoff:
    type: exponential
    base_ms: 500
    max_ms: 30000
```

### 3.2 Promise/Future Feature
```yaml
futures:
  type: promise_result
  retrieve_endpoint: futures.retrieve
  result_field: result
  error_field: error
  error_category_field: category
  try_again:
    field: type
    value: try_again
  queue_state:
    field: queue_state
    reason_field: queue_state_reason
```

### 3.3 Sampling Backpressure Feature
```yaml
sampling_backpressure:
  type: sampling_backpressure
  retry_status: 429
  backoff_seconds:
    small: 1
    large: 5
  header:
    X-Tinker-Sampling-Backpressure: "1"
```

### 3.4 Telemetry Feature
```yaml
telemetry:
  type: telemetry
  enabled_env: TINKER_TELEMETRY
  batch_size: 100
  flush_interval_sec: 10
  max_queue_size: 10000
```

## 4. Composite Flows in the Manifest

Some client methods are not single endpoints (e.g., create_training_client_from_state). These can be expressed as flows:

```yaml
flows:
  create_training_client_from_state:
    client: service
    doc: Create training client from existing checkpoint
    steps:
      - call: rest.get_weights_info_by_tinker_path
      - call: service.create_lora_training_client
        args:
          base_model: ${result.base_model}
          rank: ${result.lora_rank}
      - call: training.load_state
        args:
          path: ${input.path}
```

Flows can be generated into public methods without handwritten wrappers, while still preserving Tinkex shape.

## 5. Types Section

Types can be declared or imported, with codegen backends mapping to language-specific structs:

```yaml
types:
  CreateSessionRequest:
    fields:
      tags: [string]
      user_metadata: map[string,string]
      sdk_version: string
  CreateSessionResponse:
    fields:
      session_id: string
      info_message: string?
      warning_message: string?
      error_message: string?
```

This is necessary to keep generated Elixir structs aligned with the Python SDK types.

## 6. Generation Metadata

The manifest should allow module name and method name overrides to preserve the existing surface:

```yaml
clients:
  service:
    module: Tinkex.ServiceClient
    methods:
      get_server_capabilities:
        endpoint: service.get_server_capabilities
      create_lora_training_client:
        flow: create_lora_training_client
```

This avoids post-generation wrappers and keeps the public surface stable.

