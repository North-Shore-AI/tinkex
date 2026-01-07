# Manifest Reimagining: Generation and Surface Compatibility

This document explains how manifest-driven codegen can preserve the existing Tinkex public surface without handwritten wrappers.

## 1. Public Modules to Preserve

These modules are used in examples and must remain available:
- Tinkex.ServiceClient
- Tinkex.TrainingClient
- Tinkex.SamplingClient
- Tinkex.RestClient
- Tinkex.API.* (direct REST helpers)
- Tinkex.Telemetry (Reporter, Capture, attach_logger)
- Tinkex.Metrics
- Tinkex.QueueStateObserver, QueueStateLogger
- Tinkex.Recovery (Executor, Monitor, Policy)
- Tinkex.Regularizer (Pipeline, Executor, GradientTracker, Telemetry)
- Tinkex.Multipart (Encoder, FormSerializer)
- Tinkex.Files.Transform
- Tinkex.CLI

Generated clients should map directly to these names or provide thin domain wrappers (only if unavoidable).

## 2. Manifest-Driven Generation Strategy

### 2.1 Client Modules
Each client module maps to either:
- A manifest `resource` with endpoints.
- A manifest `flow` for multi-step operations.

Example mapping:
- Tinkex.ServiceClient.get_server_capabilities -> endpoint `service.get_server_capabilities`
- Tinkex.ServiceClient.create_lora_training_client -> flow `create_lora_training_client`
- Tinkex.TrainingClient.forward_backward -> endpoint `training.forward_backward` (future feature)

### 2.2 Flow Definitions
Flows are needed for operations that combine endpoints or require local logic:
- create_training_client_from_state
- create_training_client_from_state_with_optimizer
- save_weights_and_get_sampling_client

Flow steps can be declarative with local hooks:
- call endpoint
- wait future
- build client instance
- execute local domain hook

### 2.3 Client State and Session Propagation
Generated clients should allow state injection:
- ServiceClient holds session_id and user_metadata.
- TrainingClient holds model_id and model_seq_id.
- SamplingClient holds sampling_session_id.

The manifest should declare required state fields and how they are populated.

### 2.4 Types Namespace
The manifest should declare a canonical types namespace:
- Tinkex.Types.* should be either generated or aliased to generated types.
- Avoid forcing callers to use Tinkex.Generated.Types.*

This is critical for example parity.

## 3. Compatibility Without Handwritten Wrappers

The preferred path is to generate modules that match the legacy API shapes:
- Use manifest generation metadata to control module names and method names.
- Use flow definitions for composite methods.
- Use adapters for telemetry, retry, futures, queue state, etc.

Handwritten wrappers should only exist for domain-specific behavior (tokenizer, model input helpers, custom loss). All endpoint-driven behavior must be manifest-driven.

## 4. Error Compatibility

Ensure generated clients raise/return errors that match prior behavior:
- APIStatusError variants for HTTP
- RequestFailedError for promise failure
- Error categories should map to prior enum values

Manifest should encode error types and mapping rules.

## 5. Examples Parity Checklist (Generation Requirements)

The following example-driven requirements must be covered by codegen + features:
- Sampling with prompt logprobs and top-k logprobs
- Training forward/forward_backward/optim_step futures
- Save/load weights, save weights for sampler
- Rest endpoints for runs, checkpoints, sessions, and samplers
- Checkpoint archive download (redirect handling)
- Telemetry reporter and capture macros
- Metrics snapshot + percentiles
- Queue state observer and logger
- Recovery and regularizer pipelines
- Multipart encoding demo
- CLI command equivalents

If any of these require custom code, the manifest must allow flow hooks or feature flags rather than manual compatibility layers.

