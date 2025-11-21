defmodule Tinkex.API.Rest do
  @moduledoc """
  Low-level REST API endpoints for session and checkpoint management.

  These functions provide direct access to the Tinker REST API endpoints.
  For higher-level operations, use `Tinkex.RestClient`.
  """

  alias Tinkex.API
  alias Tinkex.Config

  @doc """
  Get session information.

  Returns training run IDs and sampler IDs associated with the session.
  """
  @spec get_session(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_session(config, session_id) do
    API.get("/api/v1/sessions/#{session_id}", config: config, pool_type: :training)
  end

  @doc """
  List sessions with pagination.

  ## Options
    * `:limit` - Maximum number of sessions to return (default: 20)
    * `:offset` - Offset for pagination (default: 0)
  """
  @spec list_sessions(Config.t(), integer(), integer()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_sessions(config, limit \\ 20, offset \\ 0) do
    path = "/api/v1/sessions?limit=#{limit}&offset=#{offset}"
    API.get(path, config: config, pool_type: :training)
  end

  @doc """
  List checkpoints for a specific training run.
  """
  @spec list_checkpoints(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_checkpoints(config, run_id) do
    API.get("/api/v1/training_runs/#{run_id}/checkpoints", config: config, pool_type: :training)
  end

  @doc """
  List all checkpoints for the current user with pagination.

  ## Options
    * `:limit` - Maximum number of checkpoints to return (default: 50)
    * `:offset` - Offset for pagination (default: 0)
  """
  @spec list_user_checkpoints(Config.t(), integer(), integer()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_user_checkpoints(config, limit \\ 50, offset \\ 0) do
    path = "/api/v1/checkpoints?limit=#{limit}&offset=#{offset}"
    API.get(path, config: config, pool_type: :training)
  end

  @doc """
  Get the archive download URL for a checkpoint.

  The returned URL can be used to download the checkpoint archive.
  """
  @spec get_checkpoint_archive_url(Config.t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(config, checkpoint_path) do
    with {:ok, {run_id, checkpoint_id}} <- parse_tinker_path(checkpoint_path) do
      # Archive endpoint issues a redirect to the signed URL
      path = "/api/v1/training_runs/#{run_id}/checkpoints/#{checkpoint_id}/archive"
      API.get(path, config: config, pool_type: :training)
    end
  end

  @doc """
  Delete a checkpoint.
  """
  @spec delete_checkpoint(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint(config, checkpoint_path) do
    with {:ok, {run_id, checkpoint_id}} <- parse_tinker_path(checkpoint_path) do
      path = "/api/v1/training_runs/#{run_id}/checkpoints/#{checkpoint_id}"
      API.delete(path, config: config, pool_type: :training)
    end
  end

  defp parse_tinker_path("tinker://" <> rest) do
    case String.split(rest, "/") do
      [run_id, part1, part2] ->
        {:ok, {run_id, Path.join(part1, part2)}}

      _ ->
        {:error,
         Tinkex.Error.new(:validation, "Invalid checkpoint path: #{rest}", category: :user)}
    end
  end

  defp parse_tinker_path(other) do
    {:error,
     Tinkex.Error.new(:validation, "Checkpoint path must start with tinker://, got: #{other}",
       category: :user
     )}
  end
end
