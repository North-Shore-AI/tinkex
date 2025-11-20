defmodule Tinkex.API.Training do
  @moduledoc """
  Training API endpoints.

  Uses :training pool (sequential, long-running operations).
  Pool size: 5 connections.
  """

  @doc """
  Forward-backward pass for gradient computation.

  ## Examples

      Tinkex.API.Training.forward_backward(
        %{model_id: "...", inputs: [...]},
        config: config
      )
  """
  @spec forward_backward(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward_backward(request, opts) do
    Tinkex.API.post(
      "/api/v1/forward_backward",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Optimizer step to update model parameters.
  """
  @spec optim_step(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def optim_step(request, opts) do
    Tinkex.API.post(
      "/api/v1/optim_step",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Forward pass only (inference).
  """
  @spec forward(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward(request, opts) do
    Tinkex.API.post(
      "/api/v1/forward",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end
end
