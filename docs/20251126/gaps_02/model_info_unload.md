# Model info & unload endpoints

**Gap:** Python exposes model metadata retrieval and unload endpoints; Elixir omits both and returns “not implemented” for `get_info`.

- **Python feature set**
  - `/api/v1/get_info` via `AsyncModelsResource.get_info`; `TrainingClient.get_info` would call this to fetch model metadata (tokenizer id, etc.).
  - `/api/v1/unload_model` via `AsyncModelsResource.unload` to release weights/end session.
- **Elixir port status**
  - No `GetInfoRequest/Response` or `UnloadModel*` types in `lib/tinkex/types`.
  - `Tinkex.TrainingClient.get_info/1` replies with a validation error (“get_info not implemented”, `lib/tinkex/training_client.ex:436`).
  - `API` layer has no model info or unload routes.
- **Impact**
  - Clients cannot inspect model metadata (e.g., tokenizer id) and cannot explicitly unload models; reliance on session teardown may leak capacity.
- **Suggested alignment**
  1) Port `GetInfo*` and `UnloadModel*` types.
  2) Add `Tinkex.API.Models.get_info/2` and `unload/2` (or fold into `API.Service`).
  3) Implement `Tinkex.TrainingClient.get_info/1` to call `/api/v1/get_info`.
  4) Expose unload in the appropriate client (Training or Service) with optional idempotency key.
