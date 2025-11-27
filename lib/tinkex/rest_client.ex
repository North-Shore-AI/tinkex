defmodule Tinkex.RestClient do
  @moduledoc """
  REST client for synchronous Tinker API operations.

  Provides checkpoint and session management functionality.

  ## Usage

      {:ok, service_pid} = Tinkex.ServiceClient.start_link(config: config)
      {:ok, rest_client} = Tinkex.ServiceClient.create_rest_client(service_pid)

      # List sessions
      {:ok, sessions} = Tinkex.RestClient.list_sessions(rest_client)

      # List checkpoints
      {:ok, checkpoints} = Tinkex.RestClient.list_user_checkpoints(rest_client)
  """

  alias Tinkex.API.Rest
  alias Tinkex.Config

  alias Tinkex.Types.{
    CheckpointsListResponse,
    CheckpointArchiveUrlResponse,
    GetSessionResponse,
    GetSamplerResponse,
    ListSessionsResponse,
    TrainingRun,
    TrainingRunsResponse,
    WeightsInfoResponse
  }

  @type t :: %__MODULE__{
          session_id: String.t(),
          config: Config.t()
        }

  defstruct [:session_id, :config]

  @doc """
  Create a new RestClient.

  ## Parameters
    * `session_id` - The session ID for this client
    * `config` - The Tinkex configuration
  """
  @spec new(String.t(), Config.t()) :: t()
  def new(session_id, config) do
    %__MODULE__{session_id: session_id, config: config}
  end

  # Session APIs

  @doc """
  Get session information.

  Returns training run IDs and sampler IDs associated with the session.

  ## Examples

      {:ok, response} = RestClient.get_session(client, "session-123")
      IO.inspect(response.training_run_ids)
      IO.inspect(response.sampler_ids)
  """
  @spec get_session(t(), String.t()) :: {:ok, GetSessionResponse.t()} | {:error, Tinkex.Error.t()}
  def get_session(%__MODULE__{config: config}, session_id) do
    case Rest.get_session(config, session_id) do
      {:ok, data} -> {:ok, GetSessionResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  List sessions with pagination.

  ## Options
    * `:limit` - Maximum number of sessions to return (default: 20)
    * `:offset` - Offset for pagination (default: 0)

  ## Examples

      {:ok, response} = RestClient.list_sessions(client)
      {:ok, response} = RestClient.list_sessions(client, limit: 50, offset: 100)
  """
  @spec list_sessions(t(), keyword()) ::
          {:ok, ListSessionsResponse.t()} | {:error, Tinkex.Error.t()}
  def list_sessions(%__MODULE__{config: config}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    case Rest.list_sessions(config, limit, offset) do
      {:ok, data} -> {:ok, ListSessionsResponse.from_map(data)}
      error -> error
    end
  end

  # Checkpoint APIs
  @doc """
  Get sampler information.

  Returns details about a sampler, including the base model and any loaded
  custom weights.

  ## Examples

      {:ok, response} = RestClient.get_sampler(client, "session-id:sample:0")
      IO.inspect(response.base_model)
      IO.inspect(response.model_path)
  """
  @spec get_sampler(t(), String.t()) ::
          {:ok, GetSamplerResponse.t()} | {:error, Tinkex.Error.t()}
  def get_sampler(%__MODULE__{config: config}, sampler_id) do
    Rest.get_sampler(config, sampler_id)
  end

  @doc """
  Get checkpoint information from a tinker path.

  Returns metadata about a checkpoint such as base model and LoRA details.

  ## Examples

      path = "tinker://run-id/weights/checkpoint-001"
      {:ok, response} = RestClient.get_weights_info_by_tinker_path(client, path)
      IO.inspect(response.base_model)
      IO.inspect(response.is_lora)
      IO.inspect(response.lora_rank)
  """
  @spec get_weights_info_by_tinker_path(t(), String.t()) ::
          {:ok, WeightsInfoResponse.t()} | {:error, Tinkex.Error.t()}
  def get_weights_info_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
    Rest.get_weights_info_by_tinker_path(config, tinker_path)
  end

  # Checkpoint APIs

  @doc """
  List checkpoints for a specific training run.

  ## Examples

      {:ok, response} = RestClient.list_checkpoints(client, "run-123")
      for checkpoint <- response.checkpoints do
        IO.puts(checkpoint.tinker_path)
      end
  """
  @spec list_checkpoints(t(), String.t()) ::
          {:ok, CheckpointsListResponse.t()} | {:error, Tinkex.Error.t()}
  def list_checkpoints(%__MODULE__{config: config}, run_id) do
    case Rest.list_checkpoints(config, run_id) do
      {:ok, data} -> {:ok, CheckpointsListResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  List all checkpoints for the current user with pagination.

  ## Options
    * `:limit` - Maximum number of checkpoints to return (default: 50)
    * `:offset` - Offset for pagination (default: 0)

  ## Examples

      {:ok, response} = RestClient.list_user_checkpoints(client)
      {:ok, response} = RestClient.list_user_checkpoints(client, limit: 100, offset: 50)
  """
  @spec list_user_checkpoints(t(), keyword()) ::
          {:ok, CheckpointsListResponse.t()} | {:error, Tinkex.Error.t()}
  def list_user_checkpoints(%__MODULE__{config: config}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    case Rest.list_user_checkpoints(config, limit, offset) do
      {:ok, data} -> {:ok, CheckpointsListResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  Get the archive download URL for a checkpoint.

  ## Examples

      {:ok, response} = RestClient.get_checkpoint_archive_url(client, "tinker://run-123/weights/0001")
      IO.puts(response.url)
  """
  @spec get_checkpoint_archive_url(t(), String.t()) ::
          {:ok, CheckpointArchiveUrlResponse.t()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url(%__MODULE__{config: config}, checkpoint_path) do
    case Rest.get_checkpoint_archive_url(config, checkpoint_path) do
      {:ok, data} -> {:ok, CheckpointArchiveUrlResponse.from_map(data)}
      error -> error
    end
  end

  @doc """
  Delete a checkpoint.

  ## Examples

      {:ok, _} = RestClient.delete_checkpoint(client, "tinker://run-123/weights/0001")
  """
  @spec delete_checkpoint(t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint(%__MODULE__{config: config}, checkpoint_path) do
    Rest.delete_checkpoint(config, checkpoint_path)
  end

  @doc """
  Delete a checkpoint referenced by a tinker path.

  Alias for `delete_checkpoint/2` to mirror Python convenience naming.
  """
  @spec delete_checkpoint_by_tinker_path(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def delete_checkpoint_by_tinker_path(client, checkpoint_path) do
    delete_checkpoint(client, checkpoint_path)
  end

  # Training run APIs

  @doc """
  Get a training run by ID.
  """
  @spec get_training_run(t(), String.t()) ::
          {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
  def get_training_run(%__MODULE__{config: config}, run_id) do
    Rest.get_training_run(config, run_id)
  end

  @doc """
  Get a training run by tinker path.
  """
  @spec get_training_run_by_tinker_path(t(), String.t()) ::
          {:ok, TrainingRun.t()} | {:error, Tinkex.Error.t()}
  def get_training_run_by_tinker_path(%__MODULE__{config: config}, tinker_path) do
    Rest.get_training_run_by_tinker_path(config, tinker_path)
  end

  @doc """
  List training runs with pagination.
  """
  @spec list_training_runs(t(), keyword()) ::
          {:ok, TrainingRunsResponse.t()} | {:error, Tinkex.Error.t()}
  def list_training_runs(%__MODULE__{config: config}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    Rest.list_training_runs(config, limit, offset)
  end

  @doc """
  Publish a checkpoint (make it public).
  """
  @spec publish_checkpoint(t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def publish_checkpoint(%__MODULE__{config: config}, checkpoint_path) do
    Rest.publish_checkpoint(config, checkpoint_path)
  end

  @doc """
  Publish a checkpoint referenced by a tinker path.

  Alias for `publish_checkpoint/2` to mirror Python convenience naming.
  """
  @spec publish_checkpoint_from_tinker_path(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def publish_checkpoint_from_tinker_path(client, checkpoint_path) do
    publish_checkpoint(client, checkpoint_path)
  end

  @doc """
  Unpublish a checkpoint (make it private).
  """
  @spec unpublish_checkpoint(t(), String.t()) :: {:ok, map()} | {:error, Tinkex.Error.t()}
  def unpublish_checkpoint(%__MODULE__{config: config}, checkpoint_path) do
    Rest.unpublish_checkpoint(config, checkpoint_path)
  end

  @doc """
  Unpublish a checkpoint referenced by a tinker path.

  Alias for `unpublish_checkpoint/2` to mirror Python convenience naming.
  """
  @spec unpublish_checkpoint_from_tinker_path(t(), String.t()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def unpublish_checkpoint_from_tinker_path(client, checkpoint_path) do
    unpublish_checkpoint(client, checkpoint_path)
  end

  @doc """
  Get the archive download URL for a checkpoint referenced by a tinker path.

  Alias for `get_checkpoint_archive_url/2` to mirror Python convenience naming.
  """
  @spec get_checkpoint_archive_url_by_tinker_path(t(), String.t()) ::
          {:ok, CheckpointArchiveUrlResponse.t()} | {:error, Tinkex.Error.t()}
  def get_checkpoint_archive_url_by_tinker_path(client, checkpoint_path) do
    get_checkpoint_archive_url(client, checkpoint_path)
  end
end
