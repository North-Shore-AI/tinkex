defmodule Tinkex.API.Session do
  @moduledoc """
  Session management endpoints.

  Uses :session pool (critical, keep-alive).
  Pool size: 5 connections with infinite idle time.
  """

  alias Tinkex.Types.CreateSessionResponse

  @doc """
  Create a new session.

  ## Examples

      Tinkex.API.Session.create(
        %{model_id: "...", config: %{}},
        config: config
      )
  """
  @spec create(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create(request, opts) do
    Tinkex.API.post(
      "/api/v1/create_session",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end

  @doc """
  Create a new session with typed response.

  Returns a properly typed CreateSessionResponse struct.

  ## Examples

      {:ok, response} = Tinkex.API.Session.create_typed(request, config: config)
      response.session_id  # => "session-abc-123"
  """
  @spec create_typed(map(), keyword()) ::
          {:ok, CreateSessionResponse.t()} | {:error, Tinkex.Error.t()}
  def create_typed(request, opts) do
    case create(request, opts) do
      {:ok, json} ->
        {:ok, CreateSessionResponse.from_json(json)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Send heartbeat to keep session alive.
  """
  @spec heartbeat(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def heartbeat(request, opts) do
    Tinkex.API.post(
      "/api/v1/heartbeat",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
end
