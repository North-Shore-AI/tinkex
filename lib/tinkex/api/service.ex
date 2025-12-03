defmodule Tinkex.API.Service do
  @moduledoc """
  Service and model creation endpoints.

  Uses :session pool for model creation operations.
  """

  alias Tinkex.Types.{GetServerCapabilitiesResponse, HealthResponse}

  @doc """
  Retrieve supported models and server capabilities.
  """
  @spec get_server_capabilities(keyword()) ::
          {:ok, GetServerCapabilitiesResponse.t()} | {:error, Tinkex.Error.t()}
  def get_server_capabilities(opts) do
    client = Tinkex.API.client_module(opts)

    case client.get(
           "/api/v1/get_server_capabilities",
           Keyword.put(opts, :pool_type, :session)
         ) do
      {:ok, json} -> {:ok, GetServerCapabilitiesResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Perform a health check against the service.
  """
  @spec health_check(keyword()) :: {:ok, HealthResponse.t()} | {:error, Tinkex.Error.t()}
  def health_check(opts) do
    client = Tinkex.API.client_module(opts)

    case client.get("/api/v1/healthz", Keyword.put(opts, :pool_type, :session)) do
      {:ok, json} -> {:ok, HealthResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Create a new model.
  """
  @spec create_model(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create_model(request, opts) do
    client = Tinkex.API.client_module(opts)

    client.post(
      "/api/v1/create_model",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end

  @doc """
  Create a sampling session.
  """
  @spec create_sampling_session(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create_sampling_session(request, opts) do
    client = Tinkex.API.client_module(opts)

    client.post(
      "/api/v1/create_sampling_session",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
end
