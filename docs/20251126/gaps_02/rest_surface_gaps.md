# REST surface gaps (sampler + weights info)

**Status:** Closed (added to `lib/tinkex/rest_client.ex`)

- Added public wrappers:
  - `get_sampler/2` → delegates to low-level `/api/v1/samplers/{id}` and returns `Tinkex.Types.GetSamplerResponse`.
  - `get_weights_info_by_tinker_path/2` → posts to `/api/v1/weights_info` and returns `Tinkex.Types.WeightsInfoResponse`.
- Added tinker-path convenience aliases to mirror Python SDK ergonomics:
  - `get_training_run_by_tinker_path/2`
  - `delete_checkpoint_by_tinker_path/2`
  - `publish_checkpoint_from_tinker_path/2`, `unpublish_checkpoint_from_tinker_path/2`
  - `get_checkpoint_archive_url_by_tinker_path/2`
- Tests updated (`test/tinkex/rest_client_test.exs`) to cover new wrappers and alias routes.
