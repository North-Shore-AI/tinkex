defmodule Tinkex.API.Rest do
  @moduledoc """
  Low-level REST API endpoints for session and checkpoint management.

  These functions provide direct access to the Tinker REST API endpoints.
  For higher-level operations, use `Tinkex.RestClient`.
  """

  alias Tinkex.API
  alias Tinkex.CheckpointTTL
  alias Tinkex.Config

  alias Tinkex.Types.{
    GetSamplerResponse,
    ParsedCheckpointTinkerPath,
    TrainingRun,
    TrainingRunsResponse,
    WeightsInfoResponse
  }

  @archive_retry_delay_ms 30_000
  @archive_max_retries 6

  @doc """
  Get session information.

  Returns training run IDs and sampler IDs associated with the session.
  """
  @spec get_session(Config.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_session(config, session_id, opts \\ []) do
    client = http_client(config)

    client.get("/api/v1/sessions/#{session_id}",
      config: config,
      pool_type: :training,
      query: access_scope_query(opts)
    )
  end

  @doc """
  List sessions with pagination.

  ## Options
    * `:limit` - Maximum number of sessions to return (default: 20)
    * `:offset` - Offset for pagination (default: 0)
  """
  @spec list_sessions(Config.t(), integer(), integer(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_sessions(config, limit \\ 20, offset \\ 0, opts \\ []) do
    query =
      [limit: limit, offset: offset]
      |> maybe_put_query(:access_scope, Keyword.get(opts, :access_scope))

    http_client(config).get("/api/v1/sessions",
      config: config,
      pool_type: :training,
      query: query
    )
  end

  @doc """
  List checkpoints for a specific training run.
  """
  @spec list_checkpoints(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_checkpoints(config, run_id) do
    http_client(config).get(
      "/api/v1/training_runs/#{run_id}/checkpoints",
      config: config,
      pool_type: :training
    )
  end

  @doc """
  List all checkpoints for the current user with pagination.

  ## Options
    * `:limit` - Maximum number of checkpoints to return (default: 100)
    * `:offset` - Offset for pagination (default: 0)
  """
  @spec list_user_checkpoints(Config.t(), integer(), integer()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def list_user_checkpoints(config, limit \\ 100, offset \\ 0) do
    path = "/api/v1/checkpoints?limit=#{limit}&offset=#{offset}"
    http_client(config).get(path, config: config, pool_type: :training)
  end

  @doc """
  Get the archive download URL for a checkpoint.

  The returned URL can be used to download the checkpoint archive.
  """
  @spec get_checkpoint_archive_url(Config.t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(config, checkpoint_path) do
    get_checkpoint_archive_url(config, checkpoint_path, [])
  end

  @spec get_checkpoint_archive_url(Config.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(config, checkpoint_path, opts)
      when is_binary(checkpoint_path) and is_list(opts) do
    with {:ok, {run_id, checkpoint_id}} <- parse_tinker_path(checkpoint_path) do
      get_checkpoint_archive_url(config, run_id, checkpoint_id, opts)
    end
  end

  @doc """
  Get the archive download URL for a checkpoint by IDs.

  The returned URL can be used to download the checkpoint archive.
  """
  @spec get_checkpoint_archive_url(Config.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(config, run_id, checkpoint_id) do
    get_checkpoint_archive_url(config, run_id, checkpoint_id, [])
  end

  @spec get_checkpoint_archive_url(Config.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(config, run_id, checkpoint_id, opts) do
    path = "/api/v1/training_runs/#{run_id}/checkpoints/#{checkpoint_id}/archive"
    get_checkpoint_archive_url_with_retry(config, path, opts)
  end

  @doc """
  Delete a checkpoint.
  """
  @spec delete_checkpoint(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint(config, checkpoint_path) do
    with {:ok, {run_id, checkpoint_id}} <- parse_tinker_path(checkpoint_path) do
      delete_checkpoint(config, run_id, checkpoint_id)
    end
  end

  @doc """
  Delete a checkpoint by training run and checkpoint ID.
  """
  @spec delete_checkpoint(Config.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint(config, run_id, checkpoint_id) do
    path = "/api/v1/training_runs/#{run_id}/checkpoints/#{checkpoint_id}"
    http_client(config).delete(path, config: config, pool_type: :training)
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

    case http_client(config).get(path, config: config, pool_type: :sampling) do
      {:ok, json} ->
        {:ok, GetSamplerResponse.from_json(json)}

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
    body = %{"tinker_path" => tinker_path}

    case http_client(config).post("/api/v1/weights_info", body,
           config: config,
           pool_type: :training
         ) do
      {:ok, json} ->
        {:ok, WeightsInfoResponse.from_json(json)}

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
  @spec get_training_run_by_tinker_path(Config.t(), String.t(), keyword()) ::
          {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
  def get_training_run_by_tinker_path(config, tinker_path, opts \\ []) do
    with {:ok, {run_id, _checkpoint_id}} <- parse_tinker_path(tinker_path) do
      get_training_run(config, run_id, opts)
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
  @spec get_training_run(Config.t(), String.t(), keyword()) ::
          {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
  def get_training_run(config, training_run_id, opts \\ []) do
    path = "/api/v1/training_runs/#{training_run_id}"

    case http_client(config).get(path,
           config: config,
           pool_type: :training,
           query: access_scope_query(opts)
         ) do
      {:ok, data} -> {:ok, TrainingRun.from_map(data)}
      {:error, _} = error -> error
    end
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
  @spec list_training_runs(Config.t(), integer(), integer(), keyword()) ::
          {:ok, TrainingRunsResponse.t()} | {:error, Tinkex.Error.t()}
  def list_training_runs(config, limit \\ 20, offset \\ 0, opts \\ []) do
    query =
      [limit: limit, offset: offset]
      |> maybe_put_query(:access_scope, Keyword.get(opts, :access_scope))

    case http_client(config).get("/api/v1/training_runs",
           config: config,
           pool_type: :training,
           query: query
         ) do
      {:ok, data} -> {:ok, TrainingRunsResponse.from_map(data)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Update checkpoint TTL from a tinker path.
  """
  @spec set_checkpoint_ttl_from_tinker_path(Config.t(), String.t(), integer() | nil) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def set_checkpoint_ttl_from_tinker_path(config, checkpoint_path, ttl_seconds) do
    with {:ok, {run_id, checkpoint_id}} <- parse_tinker_path(checkpoint_path),
         {:ok, ttl_seconds} <- CheckpointTTL.validate(ttl_seconds) do
      path = "/api/v1/training_runs/#{run_id}/checkpoints/#{checkpoint_id}/ttl"

      http_client(config).put(path, %{"ttl_seconds" => ttl_seconds},
        config: config,
        pool_type: :training
      )
    end
  end

  @doc """
  Publish a checkpoint to make it public.
  """
  @spec publish_checkpoint(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def publish_checkpoint(config, checkpoint_path) do
    with {:ok, {run_id, checkpoint_id}} <- parse_tinker_path(checkpoint_path) do
      path = "/api/v1/training_runs/#{run_id}/checkpoints/#{checkpoint_id}/publish"
      http_client(config).post(path, %{}, config: config, pool_type: :training)
    end
  end

  @doc """
  Unpublish a checkpoint to make it private.
  """
  @spec unpublish_checkpoint(Config.t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def unpublish_checkpoint(config, checkpoint_path) do
    with {:ok, {run_id, checkpoint_id}} <- parse_tinker_path(checkpoint_path) do
      path = "/api/v1/training_runs/#{run_id}/checkpoints/#{checkpoint_id}/publish"
      http_client(config).delete(path, config: config, pool_type: :training)
    end
  end

  defp http_client(config), do: API.client_module(config: config)

  defp get_checkpoint_archive_url_with_retry(config, path, opts) do
    max_retries = max(Keyword.get(opts, :max_retries, @archive_max_retries), 1)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, @archive_retry_delay_ms)
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)

    do_get_checkpoint_archive_url(config, path, max_retries, retry_delay_ms, sleep_fun, 0)
  end

  defp do_get_checkpoint_archive_url(config, path, max_retries, retry_delay_ms, sleep_fun, retry) do
    case http_client(config).get(path,
           config: config,
           pool_type: :training,
           max_retries: 0
         ) do
      {:error, %Tinkex.Error{status: 503}} when retry < max_retries - 1 ->
        sleep_fun.(retry_delay_ms)

        do_get_checkpoint_archive_url(
          config,
          path,
          max_retries,
          retry_delay_ms,
          sleep_fun,
          retry + 1
        )

      {:error, %Tinkex.Error{status: 503} = error} ->
        {:error, error}

      result ->
        result
    end
  end

  defp access_scope_query(opts) do
    maybe_put_query([], :access_scope, Keyword.get(opts, :access_scope))
  end

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, key, value), do: Keyword.put(query, key, value)

  defp parse_tinker_path(tinker_path) do
    with {:ok, parsed} <- ParsedCheckpointTinkerPath.from_tinker_path(tinker_path) do
      {:ok, {parsed.training_run_id, ParsedCheckpointTinkerPath.checkpoint_segment(parsed)}}
    end
  end
end
