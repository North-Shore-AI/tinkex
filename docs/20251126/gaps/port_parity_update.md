# Confirmed Present (no gap)
- Session heartbeat implemented at `/api/v1/heartbeat` (`lib/tinkex/api/session.ex:53-63`) and kept alive via `SessionManager` (`lib/tinkex/session_manager.ex:5-116`); path differs from Python (`/api/v1/session_heartbeat`) but functionality is present.
- Tinker path parsing for checkpoint URIs exists (`lib/tinkex/api/rest.ex:249-265`).
- Custom loss/regularizer pipeline implemented (`lib/tinkex/training_client.ex:140-199` invoking `lib/tinkex/regularizer/pipeline.ex:1-120`).
- Save/load weight endpoints wired (`lib/tinkex/api/weights.ex:9-45`).
- Training run REST endpoints implemented (`lib/tinkex/api/rest.ex:201-247`).

# Confirmed Missing/Partial
- Critical – No NotGiven/omit sentinel or transform/serialization layer; Python uses sentinels and typed transforms (`tinker/src/tinker/_types.py:106-134`, `tinker/src/tinker/_utils/_transform.py:39-310`), while Elixir sends raw maps without omit handling (`lib/tinkex/api/api.ex:25-57`).
- High – Response wrappers/metadata validation absent: Python wraps responses with `APIResponse` and parsing hooks (`tinker/src/tinker/_response.py:54-200`, SSE-aware) but Elixir returns bare decoded maps with no envelope or validation (`lib/tinkex/api/api.ex:256-337`).
- Critical – Typed weight responses missing: Python defines `SaveWeightsResponse`, `SaveWeightsForSamplerResponse`, and `LoadWeightsResponse` (`tinker/src/tinker/types/save_weights_response.py:9-13`, `.../save_weights_for_sampler_response.py:10-23`, `.../load_weights_response.py:9-13`); Elixir only has request structs and raw map returns (`lib/tinkex/types/save_weights_request.ex:1-18`, `lib/tinkex/api/weights.ex:9-45`).
- Medium – Server capabilities/health endpoints not ported: Python exposes `get_server_capabilities` and `health_check` (`tinker/src/tinker/resources/service.py:21-65`); Elixir `Service` module only has create_model/create_sampling_session (`lib/tinkex/api/service.ex:8-32`).
- High – `compute_logprobs` helper missing: Python sampling client offers `compute_logprobs`/async wrapper (`tinker/src/tinker/lib/public_interfaces/sampling_client.py:258-303`); Elixir sampling client only exposes sampling (`lib/tinkex/sampling_client.ex:27-120`) with no equivalent convenience.
- Medium – Training run types not ported: Python has typed `TrainingRun` and `TrainingRunsResponse` (`tinker/src/tinker/types/training_run.py:9-38`, `.../training_runs_response.py:8-13`), while Elixir training run endpoints return untyped maps and define no `training_run*.ex` structs (`lib/tinkex/api/rest.ex:201-247`).
- Medium – CLI management commands missing: Python CLI includes checkpoint list/info/publish/unpublish/delete/download and run list/info (`tinker/src/tinker/cli/commands/checkpoint.py:257-513`, `tinker/src/tinker/cli/commands/run.py:167-257`); Elixir CLI dispatches only `checkpoint` (save) and `run` sampling plus version (`lib/tinkex/cli.ex:46-70`).
- High – SSE streaming support missing: Python provides SSE stream decoding/integration (`tinker/src/tinker/_streaming.py:21-146`), while Elixir reads full responses and JSON-decodes with no streaming/chunk iterators (`lib/tinkex/api/api.ex:256-291`).
