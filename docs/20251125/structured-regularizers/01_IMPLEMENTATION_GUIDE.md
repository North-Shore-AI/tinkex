# Implementation Guide: Structured Regularizers for Tinkex

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites](#2-prerequisites)
3. [Module Implementation Order](#3-module-implementation-order)
4. [Step-by-Step Implementation](#4-step-by-step-implementation)
5. [Code Examples](#5-code-examples)
6. [Testing Guidelines](#6-testing-guidelines)
7. [Common Pitfalls](#7-common-pitfalls)
8. [Debugging Tips](#8-debugging-tips)

---

## 1. Introduction

This guide walks through the implementation of structured regularizer composition for Tinkex, porting the Python SDK feature (commit `22e6fc9b`) to Elixir while leveraging OTP patterns and Nx for tensor operations.

### Key Differences from Python

| Aspect | Python | Elixir |
|--------|--------|--------|
| Async model | asyncio + ThreadPoolExecutor | Task + GenServer |
| Tensor library | PyTorch | Nx/EXLA |
| Autodiff | torch.autograd | Nx.Defn.grad |
| Type system | TypedDict, runtime checks | @type specs, dialyzer |
| Concurrency | GIL-limited threads | True parallel processes |

---

## 2. Prerequisites

### 2.1 Development Environment

```bash
# Elixir 1.14+ required
elixir --version

# Ensure Nx and EXLA are available
mix deps.get
mix compile
```

### 2.2 Required Dependencies

Ensure `mix.exs` includes:

```elixir
defp deps do
  [
    {:nx, "~> 0.7"},
    {:exla, "~> 0.7"},
    {:telemetry, "~> 1.2"},
    # ... existing deps
  ]
end
```

### 2.3 Nx Backend Configuration

```elixir
# config/config.exs
config :nx, :default_backend, EXLA.Backend

# For testing without GPU
config :nx, :default_backend, Nx.BinaryBackend
```

---

## 3. Module Implementation Order

Follow this order to minimize dependencies and enable incremental testing:

```
Phase 1: Types (no dependencies)
├── lib/tinkex/types/regularizer_spec.ex
├── lib/tinkex/types/regularizer_output.ex
└── lib/tinkex/types/custom_loss_output.ex

Phase 2: Behaviour (depends on types)
└── lib/tinkex/regularizer/regularizer.ex

Phase 3: Gradient Tracking (depends on Nx)
└── lib/tinkex/regularizer/gradient_tracker.ex

Phase 4: Executor (depends on types, behaviour)
└── lib/tinkex/regularizer/executor.ex

Phase 5: Pipeline (depends on all above)
└── lib/tinkex/regularizer/pipeline.ex

Phase 6: Telemetry (depends on types)
└── lib/tinkex/regularizer/telemetry.ex

Phase 7: TrainingClient Integration (depends on pipeline)
└── lib/tinkex/training_client.ex (modifications)
```

---

## 4. Step-by-Step Implementation

### 4.1 Phase 1: Type Definitions

#### 4.1.1 RegularizerSpec

Create `lib/tinkex/types/regularizer_spec.ex`:

```elixir
defmodule Tinkex.Types.RegularizerSpec do
  @moduledoc """
  Specification for a single regularizer in the composition pipeline.

  ## Fields

  - `:fn` - The regularizer function. Must accept `(data, logprobs)` and
    return `{loss_tensor, metrics_map}`. For async regularizers, should
    return a `Task.t()` that resolves to the same tuple.

  - `:weight` - Non-negative float multiplier for the regularizer loss.
    The contribution to total loss is `weight * regularizer_loss`.

  - `:name` - String identifier for telemetry and metrics. Must be unique
    within a regularizer list.

  - `:async` - Boolean flag indicating whether `fn` returns a Task (default: false).
    When true, the executor will `Task.await/2` the result.

  ## Examples

      # Synchronous regularizer
      %RegularizerSpec{
        fn: fn _data, logprobs ->
          {Nx.sum(Nx.abs(logprobs)), %{"l1" => 1.0}}
        end,
        weight: 0.01,
        name: "l1_sparsity"
      }

      # Async regularizer (I/O-bound)
      %RegularizerSpec{
        fn: fn data, _logprobs ->
          Task.async(fn ->
            result = external_api_call(data)
            {Nx.tensor(result.penalty), %{"validated" => true}}
          end)
        end,
        weight: 0.1,
        name: "external_validation",
        async: true
      }
  """

  @type regularizer_fn ::
          (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() ->
             {Nx.Tensor.t(), %{String.t() => number()}})

  @type async_regularizer_fn ::
          (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() ->
             Task.t({Nx.Tensor.t(), %{String.t() => number()}}))

  @enforce_keys [:fn, :weight, :name]
  defstruct [:fn, :weight, :name, async: false]

  @type t :: %__MODULE__{
          fn: regularizer_fn() | async_regularizer_fn(),
          weight: float(),
          name: String.t(),
          async: boolean()
        }

  @doc """
  Create a new RegularizerSpec with validation.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)
    validate!(attrs)

    %__MODULE__{
      fn: Map.fetch!(attrs, :fn),
      weight: Map.fetch!(attrs, :weight),
      name: Map.fetch!(attrs, :name),
      async: Map.get(attrs, :async, false)
    }
  end

  def new(attrs) when is_list(attrs) do
    new(Map.new(attrs))
  end

  @doc """
  Validate regularizer spec attributes.
  """
  @spec validate!(map()) :: :ok
  def validate!(attrs) do
    fn_val = Map.get(attrs, :fn)

    unless is_function(fn_val, 2) do
      raise ArgumentError,
            "RegularizerSpec :fn must be a function of arity 2, got: #{inspect(fn_val)}"
    end

    weight = Map.get(attrs, :weight)

    unless is_number(weight) and weight >= 0.0 do
      raise ArgumentError,
            "RegularizerSpec :weight must be a non-negative number, got: #{inspect(weight)}"
    end

    name = Map.get(attrs, :name)

    unless is_binary(name) and byte_size(name) > 0 do
      raise ArgumentError,
            "RegularizerSpec :name must be a non-empty string, got: #{inspect(name)}"
    end

    async = Map.get(attrs, :async, false)

    unless is_boolean(async) do
      raise ArgumentError,
            "RegularizerSpec :async must be a boolean, got: #{inspect(async)}"
    end

    :ok
  end
end
```

#### 4.1.2 RegularizerOutput

Create `lib/tinkex/types/regularizer_output.ex`:

```elixir
defmodule Tinkex.Types.RegularizerOutput do
  @moduledoc """
  Output metrics from a single regularizer computation.

  This struct captures both the loss contribution and optional gradient
  tracking information for monitoring regularizer dynamics.

  ## Fields

  - `:name` - Regularizer name (matches RegularizerSpec.name)
  - `:value` - Raw loss value before weighting
  - `:weight` - Weight applied to the loss
  - `:contribution` - Weighted contribution: `weight * value`
  - `:grad_norm` - L2 norm of gradients (when tracking enabled)
  - `:grad_norm_weighted` - Weighted gradient norm: `weight * grad_norm`
  - `:custom` - Custom metrics returned by the regularizer function
  """

  @enforce_keys [:name, :value, :weight, :contribution]
  defstruct [
    :name,
    :value,
    :weight,
    :contribution,
    :grad_norm,
    :grad_norm_weighted,
    custom: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          value: float(),
          weight: float(),
          contribution: float(),
          grad_norm: float() | nil,
          grad_norm_weighted: float() | nil,
          custom: %{String.t() => number()}
        }

  @doc """
  Create a RegularizerOutput from computation results.
  """
  @spec from_computation(
          name :: String.t(),
          loss_value :: float(),
          weight :: float(),
          custom_metrics :: map(),
          grad_norm :: float() | nil
        ) :: t()
  def from_computation(name, loss_value, weight, custom_metrics, grad_norm \\ nil) do
    %__MODULE__{
      name: name,
      value: loss_value,
      weight: weight,
      contribution: weight * loss_value,
      grad_norm: grad_norm,
      grad_norm_weighted: if(grad_norm, do: weight * grad_norm),
      custom: custom_metrics || %{}
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.RegularizerOutput do
  def encode(output, opts) do
    map = %{
      name: output.name,
      value: output.value,
      weight: output.weight,
      contribution: output.contribution,
      custom: output.custom
    }

    # Only include gradient fields if present
    map =
      if output.grad_norm do
        Map.merge(map, %{
          grad_norm: output.grad_norm,
          grad_norm_weighted: output.grad_norm_weighted
        })
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
```

#### 4.1.3 CustomLossOutput

Create `lib/tinkex/types/custom_loss_output.ex`:

```elixir
defmodule Tinkex.Types.CustomLossOutput do
  @moduledoc """
  Structured output from custom loss computation with regularizers.

  This type mirrors the Python SDK's metrics schema for API compatibility,
  providing comprehensive telemetry for research workflows.

  ## Schema

      %CustomLossOutput{
        loss_total: 2.847,
        base_loss: %{
          value: 2.5,
          grad_norm: 3.14,
          custom: %{"perplexity" => 12.18}
        },
        regularizers: %{
          "sparsity" => %RegularizerOutput{...},
          "entropy" => %RegularizerOutput{...}
        },
        regularizer_total: 0.347,
        total_grad_norm: 5.67
      }
  """

  alias Tinkex.Types.RegularizerOutput

  @enforce_keys [:loss_total]
  defstruct [
    :loss_total,
    :base_loss,
    :regularizer_total,
    :total_grad_norm,
    regularizers: %{}
  ]

  @type base_loss_metrics :: %{
          value: float(),
          grad_norm: float() | nil,
          custom: %{String.t() => number()}
        }

  @type t :: %__MODULE__{
          loss_total: float(),
          base_loss: base_loss_metrics() | nil,
          regularizers: %{String.t() => RegularizerOutput.t()},
          regularizer_total: float(),
          total_grad_norm: float() | nil
        }

  @doc """
  Build CustomLossOutput from computation results.
  """
  @spec build(
          base_loss_value :: float(),
          base_loss_metrics :: map(),
          regularizer_outputs :: list(RegularizerOutput.t()),
          opts :: keyword()
        ) :: t()
  def build(base_loss_value, base_loss_metrics, regularizer_outputs, opts \\ []) do
    base_grad_norm = Keyword.get(opts, :base_grad_norm)
    total_grad_norm = Keyword.get(opts, :total_grad_norm)

    regularizer_total =
      regularizer_outputs
      |> Enum.map(& &1.contribution)
      |> Enum.sum()

    regularizers_map =
      regularizer_outputs
      |> Enum.map(&{&1.name, &1})
      |> Map.new()

    %__MODULE__{
      loss_total: base_loss_value + regularizer_total,
      base_loss: %{
        value: base_loss_value,
        grad_norm: base_grad_norm,
        custom: base_loss_metrics || %{}
      },
      regularizers: regularizers_map,
      regularizer_total: regularizer_total,
      total_grad_norm: total_grad_norm
    }
  end

  @doc """
  Get the primary loss value (for backward compatibility).
  """
  @spec loss(t()) :: float()
  def loss(%__MODULE__{loss_total: loss_total}), do: loss_total
end

defimpl Jason.Encoder, for: Tinkex.Types.CustomLossOutput do
  def encode(output, opts) do
    base = %{
      loss_total: output.loss_total,
      regularizer_total: output.regularizer_total,
      regularizers:
        output.regularizers
        |> Enum.map(fn {name, reg} ->
          {name,
           %{
             value: reg.value,
             weight: reg.weight,
             contribution: reg.contribution,
             grad_norm: reg.grad_norm,
             grad_norm_weighted: reg.grad_norm_weighted,
             custom: reg.custom
           }}
        end)
        |> Map.new()
    }

    # Add base_loss if present
    base =
      if output.base_loss do
        Map.put(base, :base_loss, output.base_loss)
      else
        base
      end

    # Add total_grad_norm if present
    base =
      if output.total_grad_norm do
        Map.put(base, :total_grad_norm, output.total_grad_norm)
      else
        base
      end

    Jason.Encode.map(base, opts)
  end
end
```

### 4.2 Phase 2: Regularizer Behaviour

Create `lib/tinkex/regularizer/regularizer.ex`:

```elixir
defmodule Tinkex.Regularizer do
  @moduledoc """
  Behaviour for implementing regularizers.

  Regularizers can be implemented as:
  1. Anonymous functions matching the callback spec
  2. Modules implementing this behaviour
  3. Tasks for async operations

  ## Implementing a Regularizer Module

      defmodule MyRegularizers.L1Sparsity do
        @behaviour Tinkex.Regularizer

        @impl true
        def compute(_data, logprobs, _opts) do
          l1 = Nx.sum(Nx.abs(logprobs))
          {l1, %{"l1_value" => Nx.to_number(l1)}}
        end

        @impl true
        def name, do: "l1_sparsity"
      end

  ## Using as Anonymous Function

      regularizer_spec = %RegularizerSpec{
        fn: fn _data, logprobs ->
          {Nx.sum(Nx.abs(logprobs)), %{}}
        end,
        weight: 0.01,
        name: "l1"
      }
  """

  alias Tinkex.Types.Datum

  @doc """
  Compute the regularizer loss and metrics.

  ## Parameters
  - data: List of training Datum structs
  - logprobs: Nx tensor of log probabilities from forward pass
  - opts: Optional keyword configuration

  ## Returns
  Tuple of `{loss_tensor, metrics_map}` where:
  - loss_tensor: Scalar Nx tensor representing the regularizer loss
  - metrics_map: Map of string keys to numeric values for telemetry
  """
  @callback compute(
              data :: list(Datum.t()),
              logprobs :: Nx.Tensor.t(),
              opts :: keyword()
            ) :: {Nx.Tensor.t(), %{String.t() => number()}}

  @doc """
  Return the regularizer name for telemetry and logging.
  """
  @callback name() :: String.t()

  @optional_callbacks [name: 0]

  @doc """
  Execute a regularizer (function or module) and return results.

  Handles both anonymous functions and behaviour-implementing modules.
  """
  @spec execute(
          fn_or_module :: function() | module(),
          data :: list(Datum.t()),
          logprobs :: Nx.Tensor.t(),
          opts :: keyword()
        ) :: {Nx.Tensor.t(), %{String.t() => number()}}
  def execute(fn_or_module, data, logprobs, opts \\ [])

  def execute(fun, data, logprobs, _opts) when is_function(fun, 2) do
    fun.(data, logprobs)
  end

  def execute(fun, data, logprobs, opts) when is_function(fun, 3) do
    fun.(data, logprobs, opts)
  end

  def execute(module, data, logprobs, opts) when is_atom(module) do
    module.compute(data, logprobs, opts)
  end
end
```

### 4.3 Phase 3: Gradient Tracker

Create `lib/tinkex/regularizer/gradient_tracker.ex`:

```elixir
defmodule Tinkex.Regularizer.GradientTracker do
  @moduledoc """
  Computes gradient norms for regularizers using Nx automatic differentiation.

  This module provides L2 gradient norm computation for monitoring which
  regularizers dominate the training signal.

  ## Implementation Notes

  Nx.Defn provides automatic differentiation through `grad/2` and
  `value_and_grad/2`. We wrap regularizer functions to extract just
  the loss tensor for differentiation.

  Unlike PyTorch's `torch.autograd.grad(..., retain_graph=True)`, Nx
  computes gradients symbolically and doesn't require graph retention.
  """

  import Nx.Defn

  @doc """
  Compute L2 norm of gradients from a loss function with respect to inputs.

  ## Parameters
  - loss_fn: Function that takes logprobs and returns scalar loss tensor
  - logprobs: Nx tensor to differentiate with respect to

  ## Returns
  Float representing the L2 norm: sqrt(sum(grad^2))
  """
  @spec compute_grad_norm(
          loss_fn :: (Nx.Tensor.t() -> Nx.Tensor.t()),
          logprobs :: Nx.Tensor.t()
        ) :: float()
  def compute_grad_norm(loss_fn, logprobs) do
    grad_tensor = Nx.Defn.grad(loss_fn, logprobs)

    grad_tensor
    |> Nx.flatten()
    |> Nx.pow(2)
    |> Nx.sum()
    |> Nx.sqrt()
    |> Nx.to_number()
  end

  @doc """
  Compute gradient norm for a regularizer spec.

  Wraps the regularizer function to extract just the loss for differentiation.
  """
  @spec grad_norm_for_regularizer(
          Tinkex.Types.RegularizerSpec.t(),
          list(Tinkex.Types.Datum.t()),
          Nx.Tensor.t()
        ) :: float()
  def grad_norm_for_regularizer(spec, data, logprobs) do
    # Wrap regularizer to return only the loss tensor
    loss_fn = fn lp ->
      {loss, _metrics} = spec.fn.(data, lp)
      # Ensure it's a scalar
      case Nx.shape(loss) do
        {} -> loss
        _ -> Nx.sum(loss)
      end
    end

    compute_grad_norm(loss_fn, logprobs)
  rescue
    e ->
      # Some operations may not be differentiable
      # Return 0.0 with a warning
      require Logger
      Logger.warning("Gradient computation failed for #{spec.name}: #{inspect(e)}")
      0.0
  end

  @doc """
  Compute gradient norm for the total loss.

  ## Parameters
  - base_loss_fn: Base loss function
  - regularizers: List of RegularizerSpec with weights
  - data: Training data
  - logprobs: Nx tensor
  """
  @spec total_grad_norm(
          base_loss_fn :: function(),
          regularizers :: list(Tinkex.Types.RegularizerSpec.t()),
          data :: list(Tinkex.Types.Datum.t()),
          logprobs :: Nx.Tensor.t()
        ) :: float()
  def total_grad_norm(base_loss_fn, regularizers, data, logprobs) do
    # Compose total loss function
    total_loss_fn = fn lp ->
      {base_loss, _} = base_loss_fn.(data, lp)

      reg_losses =
        Enum.map(regularizers, fn spec ->
          {loss, _} = spec.fn.(data, lp)
          Nx.multiply(spec.weight, loss)
        end)

      [base_loss | reg_losses]
      |> Enum.reduce(&Nx.add/2)
    end

    compute_grad_norm(total_loss_fn, logprobs)
  end

  # Defn version for JIT compilation (optional optimization)
  defn compute_l2_norm(tensor) do
    tensor
    |> Nx.flatten()
    |> Nx.pow(2)
    |> Nx.sum()
    |> Nx.sqrt()
  end
end
```

### 4.4 Phase 4: Executor

Create `lib/tinkex/regularizer/executor.ex`:

```elixir
defmodule Tinkex.Regularizer.Executor do
  @moduledoc """
  Manages regularizer execution with process-based parallelism.

  This module handles both synchronous and async regularizers,
  with optional parallel execution using Elixir Tasks.
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
  - :parallel - Run in parallel (default: true)
  - :timeout - Execution timeout in ms (default: 30_000)
  - :track_grad_norms - Compute gradient norms (default: false)
  - :max_concurrency - Max parallel tasks (default: schedulers_online)
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

      output = RegularizerOutput.from_computation(
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
```

### 4.5 Phase 5: Pipeline

Create `lib/tinkex/regularizer/pipeline.ex`:

```elixir
defmodule Tinkex.Regularizer.Pipeline do
  @moduledoc """
  Orchestrates regularizer composition and computes structured loss output.

  The pipeline:
  1. Executes the base loss function
  2. Executes regularizers (optionally in parallel)
  3. Composes total loss: base + Σ(weight_i × reg_i)
  4. Optionally computes gradient norms
  5. Returns structured CustomLossOutput
  """

  alias Tinkex.Regularizer.{Executor, GradientTracker}
  alias Tinkex.Types.{CustomLossOutput, RegularizerSpec}

  require Logger

  @doc """
  Compute composed loss from base loss and regularizers.

  ## Parameters
  - data: List of training Datum structs
  - logprobs: Nx tensor of log probabilities
  - base_loss_fn: Required function `(data, logprobs) -> {loss, metrics}`
  - opts: Configuration options

  ## Options
  - :regularizers - List of RegularizerSpec (default: [])
  - :track_grad_norms - Compute gradient norms (default: false)
  - :parallel - Run regularizers in parallel (default: true)
  - :timeout - Execution timeout (default: 30_000)

  ## Returns
  `{:ok, CustomLossOutput.t()}` or `{:error, term()}`
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
      {:ok, reg_outputs} = Executor.execute_all(regularizers, data, logprobs, opts)

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
```

### 4.6 Phase 6: TrainingClient Integration

Add to `lib/tinkex/training_client.ex`:

```elixir
# Add to module attributes
alias Tinkex.Regularizer.Pipeline
alias Tinkex.Types.{CustomLossOutput, RegularizerSpec, TensorData}

# Add new public function
@doc """
Compute forward/backward pass with custom loss function and optional regularizers.

See module documentation for full details.
"""
@spec forward_backward_custom(
        t(),
        list(Tinkex.Types.Datum.t()),
        base_loss_fn :: (list(Tinkex.Types.Datum.t()), Nx.Tensor.t() ->
          {Nx.Tensor.t(), map()}),
        keyword()
      ) :: {:ok, Task.t()} | {:error, Tinkex.Error.t()}
def forward_backward_custom(client, data, base_loss_fn, opts \\ []) do
  {:ok,
   Task.async(fn ->
     GenServer.call(client, {:forward_backward_custom, data, base_loss_fn, opts}, :infinity)
   end)}
end

# Add handle_call clause
@impl true
def handle_call({:forward_backward_custom, data, base_loss_fn, opts}, from, state) do
  # Spawn background task
  Task.start(fn ->
    reply =
      try do
        do_forward_backward_custom(data, base_loss_fn, opts, state)
      rescue
        e ->
          {:error,
           %Error{
             message: "Custom loss failed: #{Exception.message(e)}",
             type: :request_failed,
             data: %{exception: e, stacktrace: __STACKTRACE__}
           }}
      end

    try do
      GenServer.reply(from, reply)
    rescue
      ArgumentError -> :ok
    end
  end)

  {:noreply, state}
end

# Private implementation
defp do_forward_backward_custom(data, base_loss_fn, opts, state) do
  # 1. Run forward pass to get logprobs
  with {:ok, forward_output} <- do_forward(data, state),
       {:ok, logprobs} <- extract_logprobs(forward_output) do

    # 2. Run regularizer pipeline
    case Pipeline.compute(data, logprobs, base_loss_fn, opts) do
      {:ok, custom_output} ->
        # 3. Optionally send gradients back (linearization)
        # This depends on whether backward pass is needed
        {:ok, custom_output}

      {:error, reason} ->
        {:error, Error.new(:request_failed, "Pipeline failed: #{inspect(reason)}")}
    end
  end
end

defp do_forward(data, state) do
  # Similar to existing forward logic but synchronous
  # ... implementation
end

defp extract_logprobs(%ForwardBackwardOutput{loss_fn_outputs: outputs}) do
  case outputs do
    [%{"logprobs" => lp} | _] when is_map(lp) ->
      tensor_data = %TensorData{
        data: lp["data"],
        dtype: parse_dtype(lp["dtype"]),
        shape: lp["shape"]
      }
      {:ok, TensorData.to_nx(tensor_data)}

    _ ->
      {:error, :no_logprobs}
  end
end

defp parse_dtype("float32"), do: :float32
defp parse_dtype("int64"), do: :int64
defp parse_dtype(_), do: :float32
```

---

## 5. Code Examples

### 5.1 Basic Usage

```elixir
# Define base loss function
def base_cross_entropy(_data, logprobs) do
  loss = Nx.negate(Nx.mean(logprobs))
  {loss, %{"mean_nll" => Nx.to_number(loss)}}
end

# Define regularizers
regularizers = [
  %RegularizerSpec{
    fn: fn _data, logprobs ->
      l1 = Nx.sum(Nx.abs(logprobs))
      {l1, %{"l1_total" => Nx.to_number(l1)}}
    end,
    weight: 0.01,
    name: "l1_sparsity"
  }
]

# Execute
{:ok, task} = TrainingClient.forward_backward_custom(
  training_client,
  data,
  &base_cross_entropy/2,
  regularizers: regularizers,
  track_grad_norms: true
)

{:ok, output} = Task.await(task, 60_000)

IO.puts("Total loss: #{output.loss_total}")
IO.puts("L1 contribution: #{output.regularizers["l1_sparsity"].contribution}")
IO.puts("L1 grad norm: #{output.regularizers["l1_sparsity"].grad_norm}")
```

### 5.2 Async Regularizer

```elixir
# External validation regularizer
async_regularizer = %RegularizerSpec{
  fn: fn data, _logprobs ->
    Task.async(fn ->
      # Call external API
      {:ok, resp} = HTTPoison.post(
        "http://validator.example.com/check",
        Jason.encode!(%{data: data}),
        [{"Content-Type", "application/json"}]
      )

      %{"penalty" => penalty} = Jason.decode!(resp.body)
      {Nx.tensor(penalty), %{"validated" => true}}
    end)
  end,
  weight: 0.1,
  name: "external_validation",
  async: true
}
```

### 5.3 Module-Based Regularizer

```elixir
defmodule MyApp.Regularizers.EntropyRegularizer do
  @behaviour Tinkex.Regularizer
  import Nx.Defn

  @impl true
  def compute(_data, logprobs, _opts) do
    entropy = compute_entropy(logprobs)
    # Negative entropy to encourage diversity
    {Nx.negate(entropy), %{"entropy" => Nx.to_number(entropy)}}
  end

  @impl true
  def name, do: "entropy"

  defnp compute_entropy(logprobs) do
    probs = Nx.exp(logprobs)
    Nx.negate(Nx.sum(probs * logprobs))
  end
end

# Usage
regularizer = %RegularizerSpec{
  fn: &MyApp.Regularizers.EntropyRegularizer.compute/3,
  weight: 0.001,
  name: MyApp.Regularizers.EntropyRegularizer.name()
}
```

---

## 6. Testing Guidelines

### 6.1 Test Organization

```
test/tinkex/
├── types/
│   ├── regularizer_spec_test.exs
│   ├── regularizer_output_test.exs
│   └── custom_loss_output_test.exs
├── regularizer/
│   ├── regularizer_test.exs
│   ├── gradient_tracker_test.exs
│   ├── executor_test.exs
│   └── pipeline_test.exs
└── training_client_custom_loss_test.exs
```

### 6.2 Test Patterns

```elixir
# Unit test example
defmodule Tinkex.Regularizer.PipelineTest do
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer.Pipeline
  alias Tinkex.Types.RegularizerSpec

  describe "compute/4" do
    test "returns correct total loss with multiple regularizers" do
      data = []
      logprobs = Nx.tensor([-1.0, -2.0, -3.0])

      base_loss_fn = fn _d, _lp ->
        {Nx.tensor(1.0), %{}}
      end

      regularizers = [
        %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(10.0), %{}} end, weight: 0.1, name: "a"},
        %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(20.0), %{}} end, weight: 0.5, name: "b"}
      ]

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)

      # 1.0 + (0.1 * 10) + (0.5 * 20) = 1.0 + 1.0 + 10.0 = 12.0
      assert_in_delta output.loss_total, 12.0, 0.001
    end
  end
end
```

---

## 7. Common Pitfalls

### 7.1 Nx Type Mismatches

```elixir
# WRONG: Mixing dtypes
loss = Nx.add(Nx.tensor(1.0), Nx.tensor(1, type: :s64))

# RIGHT: Ensure consistent types
loss = Nx.add(Nx.tensor(1.0), Nx.tensor(1.0))
```

### 7.2 Task Timeout

```elixir
# WRONG: No timeout handling
Task.await(task)

# RIGHT: Always specify timeout
Task.await(task, 60_000)
```

### 7.3 GenServer Blocking

```elixir
# WRONG: Long computation in handle_call
def handle_call({:compute}, _from, state) do
  result = expensive_computation()  # Blocks GenServer!
  {:reply, result, state}
end

# RIGHT: Spawn background task
def handle_call({:compute}, from, state) do
  Task.start(fn ->
    result = expensive_computation()
    GenServer.reply(from, result)
  end)
  {:noreply, state}
end
```

---

## 8. Debugging Tips

### 8.1 Telemetry Debugging

```elixir
# Attach debug handler
:telemetry.attach(
  "debug-regularizers",
  [:tinkex, :regularizer, :compute, :stop],
  fn _event, measurements, metadata, _config ->
    IO.inspect({metadata.regularizer_name, measurements}, label: "Regularizer")
  end,
  nil
)
```

### 8.2 Nx Tensor Inspection

```elixir
# Print tensor info without full data
def inspect_tensor(tensor) do
  IO.puts("Shape: #{inspect(Nx.shape(tensor))}")
  IO.puts("Type: #{inspect(Nx.type(tensor))}")
  IO.puts("Backend: #{inspect(Nx.backend(tensor))}")
  IO.puts("First 5: #{inspect(Enum.take(Nx.to_flat_list(tensor), 5))}")
end
```

### 8.3 Process Tracing

```elixir
# Trace Task executions
:dbg.tracer()
:dbg.p(:all, :c)
:dbg.tp(Task, :async, :x)
```

---

*End of Implementation Guide*
