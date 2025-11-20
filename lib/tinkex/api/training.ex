defmodule Tinkex.API.Training do
  @moduledoc """
  Training API endpoints.

  Uses :training pool (sequential, long-running operations).
  Pool size: 5 connections.
  """

  alias Tinkex.Future
  alias Tinkex.Types.{ForwardBackwardOutput, OptimStepResponse}

  @doc """
  Forward-backward pass for gradient computation.

  This helper awaits the future internally. Use
  `forward_backward_future/2` to get the raw future response.

  ## Examples

      Tinkex.API.Training.forward_backward(
        %{model_id: "...", inputs: [...]},
        config: config
      )
  """
  @spec forward_backward(map(), keyword()) ::
          {:ok, ForwardBackwardOutput.t() | map()} | {:error, Tinkex.Error.t()}
  def forward_backward(request, opts) do
    with {:ok, response} <- forward_backward_future(request, opts) do
      handle_forward_backward_response(response, opts)
    end
  end

  @doc """
  Forward-backward pass that returns a server-side future reference.
  """
  @spec forward_backward_future(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward_backward_future(request, opts) do
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
          {:ok, OptimStepResponse.t() | map()} | {:error, Tinkex.Error.t()}
  def optim_step(request, opts) do
    with {:ok, response} <- optim_step_future(request, opts) do
      handle_optim_step_response(response, opts)
    end
  end

  @doc """
  Optimizer step that returns a server-side future reference.
  """
  @spec optim_step_future(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def optim_step_future(request, opts) do
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

  defp poll_opts(opts) do
    opts
    |> Keyword.take([
      :timeout,
      :http_timeout,
      :telemetry_metadata,
      :queue_state_observer,
      :sleep_fun
    ])
    |> Keyword.put(:config, Keyword.fetch!(opts, :config))
  end

  defp await_timeout(opts), do: Keyword.get(opts, :await_timeout, :infinity)

  defp handle_forward_backward_response(%{"request_id" => _} = future, opts) do
    poll_and_parse_future(future, opts, &ForwardBackwardOutput.from_json/1, "ForwardBackward")
  end

  defp handle_forward_backward_response(%{request_id: _} = future, opts) do
    poll_and_parse_future(future, opts, &ForwardBackwardOutput.from_json/1, "ForwardBackward")
  end

  defp handle_forward_backward_response(%{"loss_fn_output_type" => _} = result, _opts) do
    {:ok, ForwardBackwardOutput.from_json(result)}
  end

  defp handle_forward_backward_response(%{loss_fn_output_type: _} = result, _opts) do
    {:ok, ForwardBackwardOutput.from_json(Map.new(result))}
  end

  defp handle_forward_backward_response(other, _opts), do: {:ok, other}

  defp handle_optim_step_response(%{"request_id" => _} = future, opts) do
    poll_and_parse_future(future, opts, &OptimStepResponse.from_json/1, "OptimStep")
  end

  defp handle_optim_step_response(%{request_id: _} = future, opts) do
    poll_and_parse_future(future, opts, &OptimStepResponse.from_json/1, "OptimStep")
  end

  defp handle_optim_step_response(%{"metrics" => _} = result, _opts) do
    {:ok, OptimStepResponse.from_json(result)}
  end

  defp handle_optim_step_response(other, _opts), do: {:ok, other}

  defp poll_and_parse_future(future, opts, parse_fun, request_type) do
    poll_task =
      Future.poll(future, Keyword.put(poll_opts(opts), :tinker_request_type, request_type))

    case Future.await(poll_task, await_timeout(opts)) do
      {:ok, result} -> {:ok, parse_fun.(result)}
      {:error, _} = error -> error
    end
  end
end
