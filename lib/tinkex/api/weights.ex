defmodule Tinkex.API.Weights do
  @moduledoc """
  Weight management endpoints.

  Uses :training pool for weight operations.
  """

  @doc """
  Save model weights.
  """
  @spec save_weights(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def save_weights(request, opts) do
    Tinkex.API.post(
      "/api/v1/save_weights",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Load model weights.
  """
  @spec load_weights(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def load_weights(request, opts) do
    Tinkex.API.post(
      "/api/v1/load_weights",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Save weights for sampler.
  """
  @spec save_weights_for_sampler(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def save_weights_for_sampler(request, opts) do
    Tinkex.API.post(
      "/api/v1/save_weights_for_sampler",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end
end
