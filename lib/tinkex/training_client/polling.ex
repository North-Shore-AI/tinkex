defmodule Tinkex.TrainingClient.Polling do
  @moduledoc """
  Future polling and result awaiting for TrainingClient.

  This module handles:
  - Awaiting forward/backward results from polling tasks
  - Unlink tasks to prevent process coupling
  - Safe await with error handling
  - Response conversion to typed structs
  """

  alias Tinkex.Error
  alias Tinkex.Types.{ForwardBackwardOutput, UnloadModelResponse}

  @doc """
  Await forward-backward polling tasks and convert results to typed structs.

  Returns the results in order. If any task fails, remaining tasks are killed
  and an error is returned.
  """
  @spec await_forward_backward_results([Task.t()], module()) ::
          {:ok, [ForwardBackwardOutput.t()]} | {:error, Error.t()}
  def await_forward_backward_results([], _future_module), do: {:ok, []}

  def await_forward_backward_results([task | rest], future_module) do
    case safe_await(future_module, task, :infinity) do
      {:ok, result} ->
        with {:ok, remaining} <- await_forward_backward_results(rest, future_module) do
          {:ok, [ForwardBackwardOutput.from_json(result) | remaining]}
        end

      {:error, %Error{} = error} ->
        Enum.each(rest, &Task.shutdown(&1, :brutal_kill))
        {:error, error}
    end
  end

  @doc """
  Await forward-only polling tasks and convert results to typed structs.

  Similar to await_forward_backward_results but specifically for forward passes.
  """
  @spec await_forward_results([Task.t()], module()) ::
          {:ok, [ForwardBackwardOutput.t()]} | {:error, Error.t()}
  def await_forward_results([], _future_module), do: {:ok, []}

  def await_forward_results([task | rest], future_module) do
    case safe_await(future_module, task, :infinity) do
      {:ok, result} ->
        with {:ok, remaining} <- await_forward_results(rest, future_module) do
          {:ok, [ForwardBackwardOutput.from_json(result) | remaining]}
        end

      {:error, %Error{} = error} ->
        Enum.each(rest, &Task.shutdown(&1, :brutal_kill))
        {:error, error}
    end
  end

  @doc """
  Await forward results specifically for custom loss computation.

  Same as await_forward_results but with clearer naming for custom loss context.
  """
  @spec await_forward_results_for_custom_loss([Task.t()], module()) ::
          {:ok, [ForwardBackwardOutput.t()]} | {:error, Error.t()}
  def await_forward_results_for_custom_loss([], _future_module), do: {:ok, []}

  def await_forward_results_for_custom_loss([task | rest], future_module) do
    case safe_await(future_module, task, :infinity) do
      {:ok, result} ->
        with {:ok, remaining} <- await_forward_results_for_custom_loss(rest, future_module) do
          {:ok, [ForwardBackwardOutput.from_json(result) | remaining]}
        end

      {:error, %Error{} = error} ->
        Enum.each(rest, &Task.shutdown(&1, :brutal_kill))
        {:error, error}
    end
  end

  @doc """
  Unlink a task to prevent process coupling.

  This allows the task to continue running even if the calling process terminates.
  """
  @spec unlink_task(Task.t() | any()) :: :ok
  def unlink_task(%Task{pid: pid}) when is_pid(pid) do
    Process.unlink(pid)
    :ok
  end

  def unlink_task(_), do: :ok

  @doc """
  Poll an unload future and await its result.

  Polls the future, unlinks the task, and converts the result to an UnloadModelResponse.
  """
  @spec poll_and_await_unload(map(), map(), keyword()) ::
          {:ok, UnloadModelResponse.t()} | {:error, Error.t()}
  def poll_and_await_unload(future, state, opts) do
    task =
      state.future_module.poll(
        future,
        poll_opts_with_type(state, opts, "UnloadModel")
      )

    unlink_task(task)

    case safe_await(state.future_module, task, await_timeout(opts)) do
      {:ok, result} -> {:ok, UnloadModelResponse.from_json(result)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @doc """
  Safely await a task with timeout and error handling.

  Wraps Task.await with exception and exit handling to ensure errors are
  returned in a consistent format.
  """
  @spec safe_await(module(), Task.t(), timeout()) ::
          {:ok, any()} | {:error, Error.t()}
  def safe_await(future_module, task, timeout) do
    try do
      future_module.await(task, timeout)
    rescue
      e ->
        {:error,
         Error.new(:request_failed, "Polling task failed: #{Exception.message(e)}",
           data: %{exception: e, stacktrace: __STACKTRACE__}
         )}
    catch
      :exit, reason ->
        {:error,
         Error.new(:request_failed, "Polling task exited: #{inspect(reason)}",
           data: %{exit_reason: reason}
         )}
    end
  end

  @doc """
  Build poll options with request type metadata.
  """
  @spec poll_opts_with_type(map(), keyword(), String.t()) :: keyword()
  def poll_opts_with_type(state, opts, request_type) do
    poll_opts(state, opts)
    |> Keyword.put(:tinker_request_type, request_type)
  end

  @doc """
  Build base poll options from state and user-provided options.
  """
  @spec poll_opts(map(), keyword()) :: keyword()
  def poll_opts(state, opts) do
    telemetry_metadata =
      state.telemetry_metadata
      |> Map.merge(Map.new(Keyword.get(opts, :telemetry_metadata, %{})))
      |> Map.put(:model_id, state.model_id)

    # Use Observer module as default observer for automatic queue state logging
    # Users can override with their own observer via opts[:queue_state_observer]
    observer = Keyword.get(opts, :queue_state_observer, Tinkex.TrainingClient.Observer)

    opts
    |> Keyword.take([
      :timeout,
      :http_timeout,
      :telemetry_metadata,
      :sleep_fun
    ])
    |> Keyword.put(:config, state.config)
    |> Keyword.put(:telemetry_metadata, telemetry_metadata)
    |> Keyword.put(:queue_state_observer, observer)
  end

  # Private helper to extract await timeout from options
  defp await_timeout(opts), do: Keyword.get(opts, :await_timeout, :infinity)
end
