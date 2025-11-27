defmodule Tinkex.API.Weights do
  @moduledoc """
  Weight management endpoints.

  Uses :training pool for weight operations.
  """

  alias Tinkex.Types.{
    LoadWeightsResponse,
    SaveWeightsForSamplerResponse,
    SaveWeightsResponse
  }

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
  Save model weights with a typed response.
  """
  @spec save_weights_typed(map(), keyword()) ::
          {:ok, SaveWeightsResponse.t()} | {:error, Tinkex.Error.t()}
  def save_weights_typed(request, opts) do
    case save_weights(request, opts) do
      {:ok, data} -> {:ok, SaveWeightsResponse.from_json(data)}
      {:error, _} = error -> error
    end
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
  Load model weights with a typed response.
  """
  @spec load_weights_typed(map(), keyword()) ::
          {:ok, LoadWeightsResponse.t()} | {:error, Tinkex.Error.t()}
  def load_weights_typed(request, opts) do
    case load_weights(request, opts) do
      {:ok, data} -> {:ok, LoadWeightsResponse.from_json(data)}
      {:error, _} = error -> error
    end
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

  @doc """
  Save weights for sampler with typed response.
  """
  @spec save_weights_for_sampler_typed(map(), keyword()) ::
          {:ok, SaveWeightsForSamplerResponse.t()} | {:error, Tinkex.Error.t()}
  def save_weights_for_sampler_typed(request, opts) do
    case save_weights_for_sampler(request, opts) do
      {:ok, data} -> {:ok, SaveWeightsForSamplerResponse.from_json(data)}
      {:error, _} = error -> error
    end
  end
end
