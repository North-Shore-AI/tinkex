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

  @doc """
  Get sampler information.

  Retrieves details about a sampler, including the base model and any
  custom weights that are loaded.

  ## Parameters

  - `config` - The Tinkex configuration
  - `sampler_id` - The sampler ID (sampling_session_id) to query

  ## Returns

  - `{:ok, %GetSamplerResponse{}}` - On success
  - `{:error, Tinkex.Error.t()}` - On failure

  ## Examples

      iex> {:ok, resp} = Rest.get_sampler(config, "session-id:sample:0")
      iex> resp.base_model
      "Qwen/Qwen2.5-7B"

  ## See Also

  - `Tinkex.Types.GetSamplerResponse`
  """
  @spec get_sampler(Config.t(), String.t()) ::
          {:ok, Tinkex.Types.GetSamplerResponse.t()} | {:error, Tinkex.Error.t()}
  def get_sampler(config, sampler_id) do
    encoded_id = URI.encode(sampler_id, &URI.char_unreserved?/1)
    path = "/api/v1/samplers/#{encoded_id}"

    case API.get(path, config: config, pool_type: :sampling) do
      {:ok, json} ->
        {:ok, Tinkex.Types.GetSamplerResponse.from_json(json)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get checkpoint information from a tinker path.

  Retrieves metadata about a checkpoint, including the base model,
  whether it uses LoRA, and the LoRA rank.

  ## Parameters

  - `config` - The Tinkex configuration
  - `tinker_path` - The tinker path to the checkpoint
    (e.g., `"tinker://run-id/weights/checkpoint-001"`)

  ## Returns

  - `{:ok, %WeightsInfoResponse{}}` - On success
  - `{:error, Tinkex.Error.t()}` - On failure

  ## Examples

      iex> path = "tinker://run-id/weights/checkpoint-001"
      iex> {:ok, resp} = Rest.get_weights_info_by_tinker_path(config, path)
      iex> resp.base_model
      "Qwen/Qwen2.5-7B"
      iex> resp.is_lora
      true
      iex> resp.lora_rank
      32

  ## Use Cases

  ### Validating Checkpoint Compatibility

      def validate_checkpoint(config, path, expected_rank) do
        case Rest.get_weights_info_by_tinker_path(config, path) do
          {:ok, %{is_lora: true, lora_rank: ^expected_rank}} ->
            :ok
          {:ok, %{is_lora: true, lora_rank: actual}} ->
            {:error, {:rank_mismatch, expected: expected_rank, actual: actual}}
          {:ok, %{is_lora: false}} ->
            {:error, :not_lora}
          {:error, _} = error ->
            error
        end
      end

  ## See Also

  - `Tinkex.Types.WeightsInfoResponse`
  """
  @spec get_weights_info_by_tinker_path(Config.t(), String.t()) ::
          {:ok, Tinkex.Types.WeightsInfoResponse.t()} | {:error, Tinkex.Error.t()}
  def get_weights_info_by_tinker_path(config, tinker_path) do
    encoded_path = URI.encode(tinker_path, &URI.char_unreserved?/1)
    path = "/api/v1/weights/info?path=#{encoded_path}"

    case API.get(path, config: config, pool_type: :training) do
      {:ok, json} ->
        {:ok, Tinkex.Types.WeightsInfoResponse.from_json(json)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get training run information by tinker path.

  ## Parameters

  - `config` - The Tinkex configuration
  - `tinker_path` - The tinker path to the checkpoint

  ## Returns

  - `{:ok, map()}` - Training run information on success
  - `{:error, Tinkex.Error.t()}` - On failure
  """
  @spec get_training_run_by_tinker_path(Config.t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_training_run_by_tinker_path(config, tinker_path) do
    with {:ok, {run_id, _checkpoint_id}} <- parse_tinker_path(tinker_path) do
      get_training_run(config, run_id)
    end
  end

  @doc """
  Get training run information by ID.

  ## Parameters

  - `config` - The Tinkex configuration
  - `training_run_id` - The training run ID

  ## Returns

  - `{:ok, map()}` - Training run information on success
  - `{:error, Tinkex.Error.t()}` - On failure
  """
  @spec get_training_run(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_training_run(config, training_run_id) do
    path = "/api/v1/training_runs/#{training_run_id}"
    API.get(path, config: config, pool_type: :training)
  end

  @doc """
  List training runs with pagination.

  ## Parameters

  - `config` - The Tinkex configuration
  - `limit` - Maximum number of training runs to return (default: 20)
  - `offset` - Offset for pagination (default: 0)

  ## Returns

  - `{:ok, map()}` - List of training runs on success
  - `{:error, Tinkex.Error.t()}` - On failure
  """
  @spec list_training_runs(Config.t(), integer(), integer()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_training_runs(config, limit \\ 20, offset \\ 0) do
    path = "/api/v1/training_runs?limit=#{limit}&offset=#{offset}"
    API.get(path, config: config, pool_type: :training)
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
