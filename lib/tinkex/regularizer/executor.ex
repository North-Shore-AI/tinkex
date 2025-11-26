defmodule Tinkex.Regularizer.Executor do
  @moduledoc """
  Manages regularizer execution with process-based parallelism.

  This module handles both synchronous and async regularizers,
  with optional parallel execution using Elixir Tasks.

  ## Execution Modes

  ### Sequential (`:parallel => false`)

  Executes regularizers one at a time in the order specified.
  Useful for debugging and deterministic behavior.

  ### Parallel (`:parallel => true`, default)

  Executes regularizers concurrently using `Task.async_stream/3`.
  Provides better throughput for CPU-bound regularizers.

  ## Async Regularizers

  Regularizers with `async: true` in their spec should return a `Task.t()`
  instead of the result directly. The executor will `Task.await/2` the result.

  ## Telemetry

  Emits the following events:

  - `[:tinkex, :regularizer, :compute, :start]` - Before each regularizer
  - `[:tinkex, :regularizer, :compute, :stop]` - After each regularizer
  - `[:tinkex, :regularizer, :compute, :exception]` - On failure
  """

  alias Tinkex.Regularizer
  alias Tinkex.Regularizer.GradientTracker
  alias Tinkex.Types.{RegularizerSpec, RegularizerOutput}

  require Logger

  @default_timeout 30_000
  @max_concurrency System.schedulers_online()

  @doc """
  Execute all regularizers and collect outputs.

  ## Options

  - `:parallel` - Run in parallel (default: true)
  - `:timeout` - Execution timeout in ms (default: 30_000)
  - `:track_grad_norms` - Compute gradient norms (default: false)
  - `:max_concurrency` - Max parallel tasks (default: schedulers_online)

  ## Returns

  - `{:ok, list(RegularizerOutput.t())}` on success
  - `{:error, term()}` on failure

  ## Examples

      {:ok, outputs} = Executor.execute_all(regularizers, data, logprobs,
        parallel: true,
        timeout: 60_000,
        track_grad_norms: true
      )
  """
  @spec execute_all(
          list(RegularizerSpec.t()),
          list(Tinkex.Types.Datum.t()),
          Nx.Tensor.t(),
          keyword()
        ) :: {:ok, list(RegularizerOutput.t())} | {:error, term()}
  def execute_all([], _data, _logprobs, _opts), do: {:ok, []}

  def execute_all(regularizers, data, logprobs, opts) do
    parallel = Keyword.get(opts, :parallel, true)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    if parallel do
      execute_parallel(regularizers, data, logprobs, opts, timeout)
    else
      execute_sequential(regularizers, data, logprobs, opts)
    end
  end

  @doc """
  Execute a single regularizer and return output.

  ## Options

  - `:timeout` - Timeout for async regularizers (default: 30_000)
  - `:track_grad_norms` - Compute gradient norm (default: false)

  ## Returns

  - `{:ok, RegularizerOutput.t()}` on success
  - `{:error, {:regularizer_failed, name, exception}}` on failure
  - `{:error, {:regularizer_exit, name, reason}}` on exit
  """
  @spec execute_one(
          RegularizerSpec.t(),
          list(Tinkex.Types.Datum.t()),
          Nx.Tensor.t(),
          keyword()
        ) :: {:ok, RegularizerOutput.t()} | {:error, term()}
  def execute_one(spec, data, logprobs, opts) do
    track_grad_norms = Keyword.get(opts, :track_grad_norms, false)
    start_time = System.monotonic_time()

    try do
      # Execute the regularizer (handle async)
      {loss_tensor, custom_metrics} =
        if spec.async do
          task = spec.fn.(data, logprobs)
          Task.await(task, Keyword.get(opts, :timeout, @default_timeout))
        else
          Regularizer.execute(spec.fn, data, logprobs, opts)
        end

      # Extract loss value
      loss_value = Nx.to_number(loss_tensor)

      # Compute gradient norm if requested
      grad_norm =
        if track_grad_norms do
          GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)
        else
          nil
        end

      output =
        RegularizerOutput.from_computation(
          spec.name,
          loss_value,
          spec.weight,
          custom_metrics,
          grad_norm
        )

      duration = System.monotonic_time() - start_time
      emit_stop_telemetry(spec, output, duration)

      {:ok, output}
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        emit_exception_telemetry(spec, e, duration)
        {:error, {:regularizer_failed, spec.name, e}}
    catch
      :exit, reason ->
        {:error, {:regularizer_exit, spec.name, reason}}
    end
  end

  # Private: Sequential execution
  defp execute_sequential(regularizers, data, logprobs, opts) do
    results =
      Enum.reduce_while(regularizers, {:ok, []}, fn spec, {:ok, acc} ->
        emit_start_telemetry(spec)

        case execute_one(spec, data, logprobs, opts) do
          {:ok, output} -> {:cont, {:ok, [output | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case results do
      {:ok, outputs} -> {:ok, Enum.reverse(outputs)}
      error -> error
    end
  end

  # Private: Parallel execution using Task.async_stream
  defp execute_parallel(regularizers, data, logprobs, opts, timeout) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @max_concurrency)

    # Emit start telemetry for all
    Enum.each(regularizers, &emit_start_telemetry/1)

    results =
      regularizers
      |> Task.async_stream(
        fn spec -> execute_one(spec, data, logprobs, opts) end,
        timeout: timeout,
        max_concurrency: max_concurrency,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.map(fn
        {:ok, {:ok, output}} ->
          {:ok, output}

        {:ok, {:error, reason}} ->
          {:error, reason}

        {:exit, :timeout} ->
          {:error, :timeout}

        {:exit, reason} ->
          {:error, {:task_exit, reason}}
      end)

    # Check for any errors
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        outputs = Enum.map(results, fn {:ok, out} -> out end)
        {:ok, outputs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Telemetry helpers
  defp emit_start_telemetry(spec) do
    :telemetry.execute(
      [:tinkex, :regularizer, :compute, :start],
      %{system_time: System.system_time()},
      %{
        regularizer_name: spec.name,
        weight: spec.weight,
        async: spec.async
      }
    )
  end

  defp emit_stop_telemetry(spec, output, duration) do
    :telemetry.execute(
      [:tinkex, :regularizer, :compute, :stop],
      %{
        duration: duration,
        value: output.value,
        contribution: output.contribution,
        grad_norm: output.grad_norm
      },
      %{
        regularizer_name: spec.name,
        weight: spec.weight,
        async: spec.async
      }
    )
  end

  defp emit_exception_telemetry(spec, exception, duration) do
    :telemetry.execute(
      [:tinkex, :regularizer, :compute, :exception],
      %{duration: duration},
      %{
        regularizer_name: spec.name,
        weight: spec.weight,
        reason: exception
      }
    )
  end
end
