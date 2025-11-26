# Changelog

All notable changes to this project will be documented in this file.

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
