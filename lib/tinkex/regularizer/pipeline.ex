defmodule Tinkex.Regularizer.Pipeline do
  @moduledoc """
  Orchestrates regularizer composition and computes structured loss output.

  The pipeline coordinates the execution of base loss and regularizer functions,
  computing the total composed loss and optional gradient norms.

  ## Composition Formula

      loss_total = base_loss + Σ(weight_i × regularizer_i)

  ## Execution Flow

  1. Validates inputs (base_loss_fn, regularizer specs)
  2. Executes base loss function
  3. Executes regularizers (optionally in parallel)
  4. Computes gradient norms (if tracking enabled)
  5. Builds structured `CustomLossOutput`
  6. Emits telemetry events

  ## Telemetry Events

  - `[:tinkex, :custom_loss, :start]` - Before computation
  - `[:tinkex, :custom_loss, :stop]` - After successful computation
  - `[:tinkex, :custom_loss, :exception]` - On failure

  ## Examples

      # Base loss only
      {:ok, output} = Pipeline.compute(data, logprobs, &my_loss/2)

      # With regularizers
      {:ok, output} = Pipeline.compute(data, logprobs, &my_loss/2,
        regularizers: [
          %RegularizerSpec{fn: &l1_reg/2, weight: 0.01, name: "l1"},
          %RegularizerSpec{fn: &entropy_reg/2, weight: 0.001, name: "entropy"}
        ],
        track_grad_norms: true,
        parallel: true
      )
  """

  alias Tinkex.Regularizer.{Executor, GradientTracker}
  alias Tinkex.Types.{CustomLossOutput, RegularizerSpec}

  require Logger

  @doc """
  Compute composed loss from base loss and regularizers.

  ## Parameters

  - `data` - List of training Datum structs
  - `logprobs` - Nx tensor of log probabilities
  - `base_loss_fn` - Required function `(data, logprobs) -> {loss, metrics}`
  - `opts` - Configuration options

  ## Options

  - `:regularizers` - List of RegularizerSpec (default: [])
  - `:track_grad_norms` - Compute gradient norms (default: false)
  - `:parallel` - Run regularizers in parallel (default: true)
  - `:timeout` - Execution timeout (default: 30_000)

  ## Returns

  - `{:ok, CustomLossOutput.t()}` on success
  - `{:error, {:pipeline_failed, exception}}` on failure
  - `{:error, term()}` for regularizer failures

  ## Examples

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
        regularizers: regularizers,
        track_grad_norms: true
      )

      output.loss_total          # Total composed loss
      output.regularizer_total   # Sum of regularizer contributions
      output.regularizers["l1"]  # Individual regularizer metrics
  """
  @spec compute(
          list(Tinkex.Types.Datum.t()),
          Nx.Tensor.t(),
          base_loss_fn :: function(),
          keyword()
        ) :: {:ok, CustomLossOutput.t()} | {:error, term()}
  def compute(data, logprobs, base_loss_fn, opts \\ []) do
    regularizers = Keyword.get(opts, :regularizers, [])
    track_grad_norms = Keyword.get(opts, :track_grad_norms, false)

    start_time = System.monotonic_time()
    emit_start_telemetry(length(regularizers), track_grad_norms)

    try do
      # Validate inputs
      :ok = validate_inputs!(base_loss_fn, regularizers)

      # Execute base loss function
      {base_loss_tensor, base_metrics} = base_loss_fn.(data, logprobs)
      base_loss_value = Nx.to_number(base_loss_tensor)

      # Compute base gradient norm if tracking
      base_grad_norm =
        if track_grad_norms do
          compute_base_grad_norm(base_loss_fn, data, logprobs)
        else
          nil
        end

      # Execute regularizers
      case Executor.execute_all(regularizers, data, logprobs, opts) do
        {:ok, reg_outputs} ->
          # Compute total gradient norm if tracking
          total_grad_norm =
            if track_grad_norms and length(regularizers) > 0 do
              GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)
            else
              base_grad_norm
            end

          # Build output
          output =
            CustomLossOutput.build(
              base_loss_value,
              base_metrics,
              reg_outputs,
              base_grad_norm: base_grad_norm,
              total_grad_norm: total_grad_norm
            )

          duration = System.monotonic_time() - start_time
          emit_stop_telemetry(output, length(regularizers), duration)

          {:ok, output}

        {:error, _} = error ->
          duration = System.monotonic_time() - start_time
          emit_exception_telemetry(:regularizer_error, duration)
          error
      end
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        emit_exception_telemetry(e, duration)
        {:error, {:pipeline_failed, e}}
    end
  end

  # Validation
  defp validate_inputs!(base_loss_fn, regularizers) do
    unless is_function(base_loss_fn, 2) do
      raise ArgumentError, "base_loss_fn must be a function of arity 2"
    end

    Enum.each(regularizers, fn
      %RegularizerSpec{} = spec ->
        RegularizerSpec.validate!(%{
          fn: spec.fn,
          weight: spec.weight,
          name: spec.name,
          async: spec.async
        })

      other ->
        raise ArgumentError,
              "Each regularizer must be a RegularizerSpec, got: #{inspect(other)}"
    end)

    # Check for duplicate names
    names = Enum.map(regularizers, & &1.name)
    unique_names = Enum.uniq(names)

    if length(names) != length(unique_names) do
      duplicates = names -- unique_names
      raise ArgumentError, "Duplicate regularizer names: #{inspect(duplicates)}"
    end

    :ok
  end

  defp compute_base_grad_norm(base_loss_fn, data, logprobs) do
    loss_fn = fn lp ->
      {loss, _} = base_loss_fn.(data, lp)
      loss
    end

    GradientTracker.compute_grad_norm(loss_fn, logprobs)
  rescue
    _ -> nil
  end

  # Telemetry
  defp emit_start_telemetry(reg_count, track_grad_norms) do
    :telemetry.execute(
      [:tinkex, :custom_loss, :start],
      %{system_time: System.system_time()},
      %{
        regularizer_count: reg_count,
        track_grad_norms: track_grad_norms
      }
    )
  end

  defp emit_stop_telemetry(output, reg_count, duration) do
    :telemetry.execute(
      [:tinkex, :custom_loss, :stop],
      %{
        duration: duration,
        loss_total: output.loss_total,
        regularizer_total: output.regularizer_total
      },
      %{regularizer_count: reg_count}
    )
  end

  defp emit_exception_telemetry(exception, duration) do
    :telemetry.execute(
      [:tinkex, :custom_loss, :exception],
      %{duration: duration},
      %{reason: exception}
    )
  end
end
