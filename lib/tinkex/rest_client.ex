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
    ListSessionsResponse
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
end
