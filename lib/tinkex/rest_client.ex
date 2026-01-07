defmodule Tinkex.RestClient do
  @moduledoc false

  alias Tinkex.Domain.Rest.Client

  @type t :: Client.t()

  defdelegate new(session_id, config_or_context), to: Client
  defdelegate get_session(client, session_id), to: Client
  def list_sessions(client, opts \\ []), do: Client.list_sessions(client, opts)
  defdelegate get_sampler(client, sampler_id), to: Client
  defdelegate get_weights_info_by_tinker_path(client, tinker_path), to: Client
  defdelegate list_checkpoints(client, run_id), to: Client
  def list_user_checkpoints(client, opts \\ []), do: Client.list_user_checkpoints(client, opts)
  defdelegate get_checkpoint_archive_url(client, checkpoint_path), to: Client
  defdelegate get_checkpoint_archive_url(client, run_id, checkpoint_id), to: Client
  defdelegate delete_checkpoint(client, checkpoint_path), to: Client
  defdelegate delete_checkpoint(client, run_id, checkpoint_id), to: Client
  defdelegate delete_checkpoint_by_tinker_path(client, checkpoint_path), to: Client
  defdelegate get_training_run(client, run_id), to: Client
  defdelegate get_training_run_by_tinker_path(client, tinker_path), to: Client
  def list_training_runs(client, opts \\ []), do: Client.list_training_runs(client, opts)
  defdelegate publish_checkpoint(client, checkpoint_path), to: Client
  defdelegate publish_checkpoint_from_tinker_path(client, checkpoint_path), to: Client
  defdelegate unpublish_checkpoint(client, checkpoint_path), to: Client
  defdelegate unpublish_checkpoint_from_tinker_path(client, checkpoint_path), to: Client
  defdelegate get_checkpoint_archive_url_by_tinker_path(client, checkpoint_path), to: Client

  defdelegate get_session_async(client, session_id), to: Client
  def list_sessions_async(client, opts \\ []), do: Client.list_sessions_async(client, opts)
  defdelegate get_sampler_async(client, sampler_id), to: Client
  defdelegate get_weights_info_by_tinker_path_async(client, tinker_path), to: Client
  defdelegate list_checkpoints_async(client, run_id), to: Client

  def list_user_checkpoints_async(client, opts \\ []),
    do: Client.list_user_checkpoints_async(client, opts)

  defdelegate get_checkpoint_archive_url_async(client, checkpoint_path), to: Client
  defdelegate get_checkpoint_archive_url_async(client, run_id, checkpoint_id), to: Client
  defdelegate delete_checkpoint_async(client, checkpoint_path), to: Client
  defdelegate delete_checkpoint_async(client, run_id, checkpoint_id), to: Client
  defdelegate get_training_run_async(client, run_id), to: Client
  defdelegate get_training_run_by_tinker_path_async(client, tinker_path), to: Client

  def list_training_runs_async(client, opts \\ []),
    do: Client.list_training_runs_async(client, opts)

  defdelegate publish_checkpoint_async(client, checkpoint_path), to: Client
  defdelegate unpublish_checkpoint_async(client, checkpoint_path), to: Client
  defdelegate delete_checkpoint_by_tinker_path_async(client, checkpoint_path), to: Client
  defdelegate publish_checkpoint_from_tinker_path_async(client, checkpoint_path), to: Client
  defdelegate unpublish_checkpoint_from_tinker_path_async(client, checkpoint_path), to: Client

  defdelegate get_checkpoint_archive_url_by_tinker_path_async(client, checkpoint_path),
    to: Client
end
