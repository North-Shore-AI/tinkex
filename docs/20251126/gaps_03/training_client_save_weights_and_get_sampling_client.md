# Gap: TrainingClient.save_weights_and_get_sampling_client (ephemeral sampler flow)

## Python surface
- `TrainingClient.save_weights_and_get_sampling_client(name: str | None = None, retry_config=None) -> SamplingClient`.
- If `name` is `None`, Python performs an *ephemeral* sampler save: server returns a `sampling_session_id` (no path), and the client immediately instantiates a `SamplingClient` bound to that session.
- If `name` is provided, it saves sampler weights (path) and returns a `SamplingClient` created from that path.

## Elixir state
- Exposed functions:
  - `save_weights_for_sampler/2` (returns `{:ok, Task.t()}` yielding `%SaveWeightsForSamplerResponse{path: ...}`) and
  - `create_sampling_client_async/3` (manual composition by the caller).
- Type enforces a path: `Tinkex.Types.SaveWeightsForSamplerResponse` requires `:path` (`lib/tinkex/types/save_weights_for_sampler_response.ex:6-33`); `sampling_session_id` is optional but not produced by current flow.
- No combined convenience that mirrors the Python ergonomic/ephemeral behavior.

## Impact
- Clients cannot request the ephemeral sampler flow (no support for `sampling_session_id`-only responses, no convenience to auto-create a `SamplingClient`).
- Users must manually chain save + create calls and cannot achieve the zero-path ephemeral path at all.

## Remediation sketch
1) Update `SaveWeightsForSamplerResponse` to allow `path` nil and accept `sampling_session_id` as the primary output (to model the ephemeral response).
2) Extend `TrainingClient` handling of `save_weights_for_sampler` responses to pass through `sampling_session_id` and map both shapes (path vs sampling_session_id).
3) Add `save_weights_and_get_sampling_client/2` (and async variant) that:
   - Issues the sampler save with optional `:path` override.
   - If a `sampling_session_id` is returned, call `Tinkex.SamplingClient` creation with that id (no download path).
   - If a `path` is returned, instantiate a `SamplingClient` using that `model_path`.
4) Consider small helper to surface retry config options analogous to Python.

## Testing ideas
- Unit: stub `Weights.save_weights_for_sampler` to return (a) `%{path: "tinker://..."}` and (b) `%{sampling_session_id: "sess:123"}`; assert the new convenience returns a live SamplingClient pid in both cases.
- Type/codec: ensure `SaveWeightsForSamplerResponse.from_json/1` accepts both shapes (path-only, session-id-only).
- Integration: with a fake service adapter, verify that the `sampling_session_id` path never attempts checkpoint download and passes the id through to `SamplingClient`.
