defmodule Tinkex.API.Service do
  @moduledoc """
  Service and model creation endpoints.

  Uses :session pool for model creation operations.
  """

  @doc """
  Create a new model.
  """
  @spec create_model(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create_model(request, opts) do
    Tinkex.API.post(
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
    Tinkex.API.post(
      "/api/v1/create_sampling_session",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
end
