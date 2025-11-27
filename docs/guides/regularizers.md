# Regularizers

This guide covers the structured regularizer composition system in Tinkex, which enables modular loss engineering for training LLMs. You'll learn how to implement custom regularizers, compose multiple regularization strategies, track gradient norms, and integrate with the Tinker API.

## Overview

Regularizers add penalty terms to the base loss function during training to encourage desired model behaviors such as:

- **Sparsity** (L1): Encourage sparse activations or weight distributions
- **Weight decay** (L2): Prevent large weights and overfitting
- **Entropy**: Promote diversity in predictions
- **Custom constraints**: Domain-specific penalties (KL divergence, feature correlation, etc.)

The regularizer system in Tinkex composes multiple weighted regularizers into a total loss:

```
loss_total = base_loss + Σ(weight_i × regularizer_i)
```

Each regularizer is executed independently (optionally in parallel), with full telemetry and optional gradient norm tracking for monitoring training dynamics.

## Core Concepts

### The Regularizer Behaviour

Regularizers implement the `Tinkex.Regularizer` behaviour, which defines two callbacks:

```elixir
@callback compute(
  data :: list(Datum.t()),
  logprobs :: Nx.Tensor.t(),
  opts :: keyword()
) :: {Nx.Tensor.t(), %{String.t() => number()}}

@callback name() :: String.t()
```

The `compute/3` callback:
- Takes training data and log probabilities from the forward pass
- Returns a tuple of `{loss_tensor, metrics_map}`
- The loss tensor should be a scalar (or will be summed automatically)
- Metrics are custom measurements for telemetry (e.g., `%{"l1_value" => 0.042}`)

The optional `name/0` callback provides a unique identifier for telemetry and logging. If not implemented, the name must be provided via `RegularizerSpec`.

### RegularizerSpec

The `RegularizerSpec` struct configures how a regularizer is executed:

```elixir
%RegularizerSpec{
  fn: function() | module(),      # Regularizer function or module
  weight: float(),                # Non-negative multiplier
  name: String.t(),              # Unique identifier
  async: boolean()               # Whether fn returns a Task (default: false)
}
```

**Fields:**
- `fn`: Either an anonymous function (arity 2 or 3) or a module implementing the `Regularizer` behaviour
- `weight`: Multiplier applied to the regularizer loss (must be >= 0)
- `name`: Unique name for telemetry events and output indexing
- `async`: If `true`, the function should return a `Task.t()` for async execution

Create a spec using `RegularizerSpec.new/1`:

```elixir
spec = RegularizerSpec.new(%{
  fn: &my_regularizer/2,
  weight: 0.01,
  name: "l1_sparsity"
})
```

## Implementing Regularizers

### As Anonymous Functions

The simplest approach is to use anonymous functions:

```elixir
# Arity 2: (data, logprobs) -> {loss, metrics}
l1_regularizer = fn _data, logprobs ->
  l1_loss = Nx.sum(Nx.abs(logprobs))
  {l1_loss, %{}}
end

spec = RegularizerSpec.new(%{
  fn: l1_regularizer,
  weight: 0.01,
  name: "l1_sparsity"
})
```

You can also use arity 3 to receive options:

```elixir
# Arity 3: (data, logprobs, opts) -> {loss, metrics}
configurable_l1 = fn _data, logprobs, opts ->
  threshold = Keyword.get(opts, :threshold, 0.0)

  # Only penalize values above threshold
  masked = Nx.select(Nx.greater(Nx.abs(logprobs), threshold), logprobs, 0)
  l1_loss = Nx.sum(Nx.abs(masked))

  {l1_loss, %{"threshold" => threshold}}
end

spec = RegularizerSpec.new(%{
  fn: configurable_l1,
  weight: 0.01,
  name: "l1_sparsity",
})
```

### As Behaviour-Implementing Modules

For reusable regularizers, implement the behaviour in a module:

```elixir
defmodule MyRegularizers.L1Sparsity do
  @behaviour Tinkex.Regularizer

  @impl true
  def compute(_data, logprobs, _opts) do
    l1_loss = Nx.sum(Nx.abs(logprobs))
    l1_value = Nx.to_number(l1_loss)

    {l1_loss, %{"l1_value" => l1_value}}
  end

  @impl true
  def name, do: "l1_sparsity"
end

# Use in a spec
spec = RegularizerSpec.new(%{
  fn: MyRegularizers.L1Sparsity,
  weight: 0.01,
  name: MyRegularizers.L1Sparsity.name()
})
```

### Gradient Tracking Compatibility

**Important**: When using gradient norm tracking (`:track_grad_norms => true`), avoid calling `Nx.to_number/1` inside the regularizer function. Nx's automatic differentiation requires operations to remain as tensors during tracing.

```elixir
# BAD: Calls Nx.to_number inside the function
bad_regularizer = fn _data, logprobs ->
  l1 = Nx.sum(Nx.abs(logprobs))
  # This breaks gradient computation!
  {l1, %{"l1_value" => Nx.to_number(l1)}}
end

# GOOD: Returns empty metrics or computes them from the tensor later
good_regularizer = fn _data, logprobs ->
  l1 = Nx.sum(Nx.abs(logprobs))
  # Metrics will be computed from the loss value by the pipeline
  {l1, %{}}
end
```

## Common Regularizer Examples

### L1 Sparsity

Encourages sparse activations by penalizing the L1 norm:

```elixir
l1_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    {Nx.sum(Nx.abs(logprobs)), %{}}
  end,
  weight: 0.01,
  name: "l1_sparsity"
})
```

### L2 Weight Decay

Penalizes large weights (L2 norm):

```elixir
l2_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    {Nx.sum(Nx.pow(logprobs, 2)), %{}}
  end,
  weight: 0.005,
  name: "l2_weight_decay"
})
```

### Entropy Regularization

Encourages diversity in predictions by maximizing entropy:

```elixir
entropy_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    # Convert log probs to probs
    probs = Nx.exp(logprobs)
    # Negative entropy (we minimize, so negate to maximize entropy)
    neg_entropy = Nx.sum(Nx.multiply(probs, logprobs))
    {neg_entropy, %{}}
  end,
  weight: 0.001,
  name: "entropy"
})
```

### KL Divergence from Target Distribution

Encourage the model to match a target distribution:

```elixir
kl_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    # Assume uniform target distribution
    target_logprobs = Nx.broadcast(
      Nx.log(1.0 / Nx.size(logprobs)),
      Nx.shape(logprobs)
    )

    # KL(target || model) = sum(target * (log(target) - log(model)))
    probs = Nx.exp(logprobs)
    target_probs = Nx.exp(target_logprobs)
    kl = Nx.sum(
      Nx.multiply(
        target_probs,
        Nx.subtract(target_logprobs, logprobs)
      )
    )

    {kl, %{}}
  end,
  weight: 0.002,
  name: "kl_uniform"
})
```

## Composing Regularizer Pipelines

### Basic Pipeline Execution

Use `Regularizer.Pipeline.compute/4` to compose base loss with regularizers:

```elixir
alias Tinkex.Regularizer.Pipeline
alias Tinkex.Types.RegularizerSpec

# Define base loss function
base_loss_fn = fn _data, logprobs ->
  # Negative log-likelihood
  nll = Nx.negate(Nx.mean(logprobs))
  {nll, %{}}
end

# Define regularizers
regularizers = [
  RegularizerSpec.new(%{fn: &l1/2, weight: 0.01, name: "l1"}),
  RegularizerSpec.new(%{fn: &l2/2, weight: 0.005, name: "l2"}),
  RegularizerSpec.new(%{fn: &entropy/2, weight: 0.001, name: "entropy"})
]

# Execute pipeline
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers
)

# Access results
IO.puts("Total loss: #{output.loss_total}")
IO.puts("Base loss: #{output.base_loss.value}")
IO.puts("Regularizer total: #{output.regularizer_total}")

# Per-regularizer breakdown
for {name, reg} <- output.regularizers do
  IO.puts("#{name}: value=#{reg.value}, contribution=#{reg.contribution}")
end
```

### Pipeline Options

`Pipeline.compute/4` accepts the following options:

- `:regularizers` - List of `RegularizerSpec` structs (default: `[]`)
- `:track_grad_norms` - Compute gradient norms for monitoring (default: `false`)
- `:parallel` - Execute regularizers in parallel (default: `true`)
- `:timeout` - Timeout for async operations in milliseconds (default: `30_000`)
- `:max_concurrency` - Max parallel tasks (default: `System.schedulers_online()`)

Example with options:

```elixir
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true,
  parallel: true,
  timeout: 60_000,
  max_concurrency: 4
)
```

### Sequential vs Parallel Execution

By default, regularizers execute in parallel for better throughput:

```elixir
# Parallel execution (default)
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  parallel: true
)
```

For deterministic execution order or debugging, use sequential mode:

```elixir
# Sequential execution
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  parallel: false
)
```

## Gradient Norm Tracking

Gradient norms help you monitor which components dominate the training signal. Enable tracking with `:track_grad_norms => true`:

```elixir
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true
)

# Gradient norms are L2 norms: sqrt(sum(grad^2))
IO.puts("Base loss grad norm: #{output.base_loss.grad_norm}")
IO.puts("Total grad norm: #{output.total_grad_norm}")

for {name, reg} <- output.regularizers do
  IO.puts("#{name} grad norm: #{reg.grad_norm}")
  IO.puts("#{name} weighted grad norm: #{reg.grad_norm_weighted}")
end
```

### Understanding Gradient Norms

- **Base loss grad norm**: Gradient contribution from the base loss alone
- **Per-regularizer grad norm**: Gradient contribution from each regularizer (unweighted)
- **Weighted grad norm**: `weight × grad_norm` (actual contribution to total gradient)
- **Total grad norm**: L2 norm of the complete composed gradient

These metrics help identify:
- Which regularizers dominate training
- Whether regularizers are too strong/weak
- Training instability (exploding/vanishing gradients)

### Direct Gradient Computation

For custom gradient analysis, use `GradientTracker` directly:

```elixir
alias Tinkex.Regularizer.GradientTracker

# Compute gradient norm for a loss function
loss_fn = fn logprobs -> Nx.sum(Nx.abs(logprobs)) end
grad_norm = GradientTracker.compute_grad_norm(loss_fn, logprobs)

# Compute gradient norm for a regularizer spec
grad_norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

# Compute total composed gradient norm
total_norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)
```

## Executing Regularizers

### Via Pipeline (Recommended)

The pipeline is the high-level API that handles everything:

```elixir
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers
)
```

### Via Executor (Low-Level)

For fine-grained control, use `Executor` directly:

```elixir
alias Tinkex.Regularizer.Executor

# Execute a single regularizer
{:ok, output} = Executor.execute_one(spec, data, logprobs,
  timeout: 5000,
  track_grad_norms: true
)

# Execute all regularizers
{:ok, outputs} = Executor.execute_all(regularizers, data, logprobs,
  parallel: true,
  timeout: 30_000,
  track_grad_norms: true
)
```

### Via Regularizer Module (Direct)

Execute regularizers directly without specs:

```elixir
alias Tinkex.Regularizer

# With anonymous function (arity 2)
{loss, metrics} = Regularizer.execute(
  fn _data, logprobs -> {Nx.sum(logprobs), %{}} end,
  data,
  logprobs
)

# With anonymous function (arity 3)
{loss, metrics} = Regularizer.execute(
  fn _data, logprobs, opts -> {Nx.sum(logprobs), opts} end,
  data,
  logprobs,
  custom_option: "value"
)

# With module
{loss, metrics} = Regularizer.execute(MyRegularizer, data, logprobs)
```

## Async Regularizers

For I/O-bound operations (e.g., calling external APIs, querying databases), use async regularizers:

```elixir
async_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    Task.async(fn ->
      # Simulate external API call
      :timer.sleep(100)

      # Compute penalty based on external validation
      penalty = Nx.mean(Nx.abs(logprobs))
      {penalty, %{"external_validated" => true}}
    end)
  end,
  weight: 0.02,
  name: "async_validator",
  async: true  # Mark as async
})

{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: [async_spec],
  timeout: 5000  # Wait up to 5s for async tasks
)
```

The executor will automatically `Task.await/2` the result with the specified timeout.

## Telemetry Integration

The regularizer system emits comprehensive telemetry events for observability.

### Custom Loss Pipeline Events

**`[:tinkex, :custom_loss, :start]`**
- Measurements: `%{system_time: integer()}`
- Metadata: `%{regularizer_count: integer(), track_grad_norms: boolean()}`

**`[:tinkex, :custom_loss, :stop]`**
- Measurements: `%{duration: integer(), loss_total: float(), regularizer_total: float()}`
- Metadata: `%{regularizer_count: integer()}`

**`[:tinkex, :custom_loss, :exception]`**
- Measurements: `%{duration: integer()}`
- Metadata: `%{reason: term()}`

### Per-Regularizer Events

**`[:tinkex, :regularizer, :compute, :start]`**
- Measurements: `%{system_time: integer()}`
- Metadata: `%{regularizer_name: String.t(), weight: float(), async: boolean()}`

**`[:tinkex, :regularizer, :compute, :stop]`**
- Measurements: `%{duration: integer(), value: float(), contribution: float(), grad_norm: float() | nil}`
- Metadata: `%{regularizer_name: String.t(), weight: float(), async: boolean()}`

**`[:tinkex, :regularizer, :compute, :exception]`**
- Measurements: `%{duration: integer()}`
- Metadata: `%{regularizer_name: String.t(), weight: float(), reason: term()}`

### Attaching Telemetry Handlers

Use the built-in telemetry helper:

```elixir
alias Tinkex.Regularizer.Telemetry

# Attach logger (logs all events)
handler_id = Telemetry.attach_logger(level: :info)

# Run pipeline (emits telemetry)
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true
)

# Detach when done
Telemetry.detach(handler_id)
```

Or attach custom handlers:

```elixir
:telemetry.attach(
  "my-regularizer-handler",
  [:tinkex, :regularizer, :compute, :stop],
  fn event, measurements, metadata, _config ->
    IO.puts("Regularizer #{metadata.regularizer_name} completed in #{measurements.duration}μs")
    IO.puts("  Value: #{measurements.value}")
    IO.puts("  Contribution: #{measurements.contribution}")
  end,
  nil
)
```

## Output Structure

### CustomLossOutput

The pipeline returns a `CustomLossOutput` struct:

```elixir
%CustomLossOutput{
  loss_total: float(),              # Total composed loss
  base_loss: %{                     # Base loss component
    value: float(),
    metrics: map(),
    grad_norm: float() | nil
  },
  regularizers: %{                  # Per-regularizer outputs
    String.t() => RegularizerOutput.t()
  },
  regularizer_total: float(),       # Sum of all regularizer contributions
  total_grad_norm: float() | nil    # Total gradient L2 norm
}
```

### RegularizerOutput

Each regularizer produces a `RegularizerOutput`:

```elixir
%RegularizerOutput{
  name: String.t(),                 # Regularizer name
  value: float(),                   # Raw loss value
  weight: float(),                  # Weight multiplier
  contribution: float(),            # weight × value (added to total)
  custom_metrics: map(),            # Custom metrics from compute/3
  grad_norm: float() | nil,         # Gradient L2 norm
  grad_norm_weighted: float() | nil # weight × grad_norm
}
```

### JSON Serialization

Both output types implement `Jason.Encoder` for easy serialization:

```elixir
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true
)

# Serialize to JSON
json = Jason.encode!(output, pretty: true)
File.write!("training_metrics.json", json)

# Deserialize (manual reconstruction)
data = Jason.decode!(json)
```

## Error Handling

The pipeline and executor provide comprehensive error handling.

### Common Error Patterns

**Duplicate regularizer names:**

```elixir
regularizers = [
  RegularizerSpec.new(%{fn: &l1/2, weight: 0.01, name: "dup"}),
  RegularizerSpec.new(%{fn: &l2/2, weight: 0.02, name: "dup"})
]

{:error, {:pipeline_failed, %ArgumentError{message: msg}}} =
  Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)

# msg: "Duplicate regularizer names: [\"dup\"]"
```

**Invalid base loss function:**

```elixir
{:error, {:pipeline_failed, %ArgumentError{}}} =
  Pipeline.compute(data, logprobs, "not a function")
```

**Regularizer execution failure:**

```elixir
failing_spec = RegularizerSpec.new(%{
  fn: fn _data, _logprobs -> raise "oops" end,
  weight: 0.01,
  name: "failing"
})

{:error, {:regularizer_failed, "failing", exception}} =
  Executor.execute_one(failing_spec, data, logprobs)
```

**Timeout:**

```elixir
slow_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    Task.async(fn ->
      :timer.sleep(10_000)
      {Nx.sum(logprobs), %{}}
    end)
  end,
  weight: 0.01,
  name: "slow",
  async: true
})

{:error, :timeout} =
  Executor.execute_one(slow_spec, data, logprobs, timeout: 100)
```

### Handling Errors

Always pattern match on error tuples:

```elixir
case Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers) do
  {:ok, output} ->
    # Success - use output
    process_training_step(output)

  {:error, {:pipeline_failed, exception}} ->
    # Pipeline-level error
    Logger.error("Pipeline failed: #{Exception.message(exception)}")
    reraise exception, __STACKTRACE__

  {:error, {:regularizer_failed, name, exception}} ->
    # Specific regularizer failed
    Logger.error("Regularizer #{name} failed: #{inspect(exception)}")
    :retry

  {:error, {:regularizer_exit, name, reason}} ->
    # Regularizer process exited
    Logger.error("Regularizer #{name} exited: #{inspect(reason)}")
    :halt

  {:error, other} ->
    # Other errors
    Logger.error("Unknown error: #{inspect(other)}")
    :halt
end
```

## Integration with Training API

When using Tinkex with a live Tinker backend, wrap regularizers in `TrainingClient.forward_backward_custom/4`:

```elixir
alias Tinkex.Types.{Datum, ModelInput, RegularizerSpec}

# 1. Create training client
config = Tinkex.Config.new(api_key: System.fetch_env!("TINKER_API_KEY"))
{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service,
  base_model: "meta-llama/Llama-3.1-8B",
  lora_config: %Tinkex.Types.LoraConfig{rank: 16}
)

# 2. Prepare training data
{:ok, model_input} = ModelInput.from_text("The quick brown fox",
  model_name: "meta-llama/Llama-3.1-8B",
  training_client: training
)

datum = Datum.new(%{
  model_input: model_input,
  loss_fn_inputs: %{
    target_tokens: Nx.tensor([1, 2, 3, 4, 5]),
    weights: Nx.tensor([1.0, 1.0, 1.0, 1.0, 1.0])
  }
})

# 3. Define base loss and regularizers
base_loss_fn = fn _data, logprobs ->
  nll = Nx.negate(Nx.mean(logprobs))
  {nll, %{}}
end

regularizers = [
  RegularizerSpec.new(%{fn: &l1/2, weight: 0.01, name: "l1"}),
  RegularizerSpec.new(%{fn: &entropy/2, weight: 0.001, name: "entropy"})
]

# 4. Execute forward-backward pass with custom loss
{:ok, task} = Tinkex.TrainingClient.forward_backward_custom(
  training,
  [datum],
  base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true
)

# 5. Await results
{:ok, output} = Task.await(task, :infinity)

# output contains real logprobs from the server!
IO.puts("Total loss: #{output.loss_total}")
IO.puts("Base loss: #{output.base_loss.value}")
IO.puts("Regularizer total: #{output.regularizer_total}")
```

The `TrainingClient.forward_backward_custom/4` function:
1. Sends the training data to the Tinker server
2. Performs a forward pass to get log probabilities
3. Executes `Pipeline.compute/4` locally with the returned logprobs
4. Returns the composed `CustomLossOutput`

## Complete Example

Here's a complete example demonstrating all features:

```elixir
alias Tinkex.Regularizer.Pipeline
alias Tinkex.Types.RegularizerSpec

# Define base loss
base_loss_fn = fn _data, logprobs ->
  nll = Nx.negate(Nx.mean(logprobs))
  {nll, %{}}
end

# Define regularizers
l1_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    {Nx.sum(Nx.abs(logprobs)), %{}}
  end,
  weight: 0.01,
  name: "l1_sparsity"
})

l2_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    {Nx.sum(Nx.pow(logprobs, 2)), %{}}
  end,
  weight: 0.005,
  name: "l2_weight_decay"
})

entropy_spec = RegularizerSpec.new(%{
  fn: fn _data, logprobs ->
    probs = Nx.exp(logprobs)
    neg_entropy = Nx.sum(Nx.multiply(probs, logprobs))
    {neg_entropy, %{}}
  end,
  weight: 0.001,
  name: "entropy"
})

regularizers = [l1_spec, l2_spec, entropy_spec]

# Mock data
logprobs = Nx.tensor([-0.5, -1.2, -0.8, -2.1, -0.3])
data = []

# Execute pipeline with all features
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true,
  parallel: true,
  timeout: 30_000
)

# Display results
IO.puts("=== Training Step Results ===")
IO.puts("Total Loss: #{Float.round(output.loss_total, 6)}")
IO.puts("Base Loss: #{Float.round(output.base_loss.value, 6)}")
IO.puts("Regularizer Total: #{Float.round(output.regularizer_total, 6)}")

if output.total_grad_norm do
  IO.puts("Total Grad Norm: #{Float.round(output.total_grad_norm, 6)}")
end

IO.puts("\n=== Per-Regularizer Breakdown ===")
for {name, reg} <- output.regularizers do
  IO.puts("\n#{name}:")
  IO.puts("  value: #{Float.round(reg.value, 6)}")
  IO.puts("  weight: #{reg.weight}")
  IO.puts("  contribution: #{Float.round(reg.contribution, 6)}")

  if reg.grad_norm do
    IO.puts("  grad_norm: #{Float.round(reg.grad_norm, 6)}")
    IO.puts("  grad_norm_weighted: #{Float.round(reg.grad_norm_weighted, 6)}")
  end
end

# Serialize to JSON
json = Jason.encode!(output, pretty: true)
File.write!("training_step.json", json)
IO.puts("\n✓ Saved to training_step.json")
```

## Best Practices

### 1. Start with Small Weights

Begin with small regularizer weights and increase gradually:

```elixir
# Start small
regularizers = [
  RegularizerSpec.new(%{fn: &l1/2, weight: 0.001, name: "l1"}),
  RegularizerSpec.new(%{fn: &l2/2, weight: 0.0005, name: "l2"})
]

# Monitor gradient norms to tune weights
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  track_grad_norms: true
)

# Adjust if regularizers dominate base loss
```

### 2. Use Gradient Norms for Tuning

Track gradient norms to ensure balanced contributions:

```elixir
# Check if regularizers are dominating
base_norm = output.base_loss.grad_norm
reg_norms = Enum.map(output.regularizers, fn {_name, reg} ->
  reg.grad_norm_weighted
end)
total_reg_norm = Enum.sum(reg_norms)

ratio = total_reg_norm / base_norm
IO.puts("Regularizer/Base gradient ratio: #{ratio}")

# Aim for ratio ~0.1 to 0.5 (regularizers shouldn't dominate)
```

### 3. Avoid Nx.to_number in Regularizers

Keep operations as tensors for gradient compatibility:

```elixir
# BAD
bad = fn _data, logprobs ->
  loss = Nx.sum(logprobs)
  {loss, %{"value" => Nx.to_number(loss)}}  # Breaks gradients!
end

# GOOD
good = fn _data, logprobs ->
  loss = Nx.sum(logprobs)
  {loss, %{}}  # Pipeline will compute metrics
end
```

### 4. Use Unique Names

Ensure each regularizer has a unique name for telemetry:

```elixir
# BAD - duplicate names
regularizers = [
  RegularizerSpec.new(%{fn: &l1/2, weight: 0.01, name: "reg"}),
  RegularizerSpec.new(%{fn: &l2/2, weight: 0.01, name: "reg"})  # Error!
]

# GOOD - unique names
regularizers = [
  RegularizerSpec.new(%{fn: &l1/2, weight: 0.01, name: "l1"}),
  RegularizerSpec.new(%{fn: &l2/2, weight: 0.01, name: "l2"})
]
```

### 5. Handle Errors Gracefully

Always pattern match on error results:

```elixir
case Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers) do
  {:ok, output} ->
    process_output(output)

  {:error, reason} ->
    Logger.error("Training step failed: #{inspect(reason)}")
    :retry
end
```

### 6. Use Parallel Execution

Enable parallel execution for multiple regularizers:

```elixir
# Parallel (default) - better throughput
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  parallel: true
)

# Sequential - only for debugging
{:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn,
  regularizers: regularizers,
  parallel: false
)
```

### 7. Monitor with Telemetry

Attach telemetry handlers for production monitoring:

```elixir
:telemetry.attach(
  "my-training-monitor",
  [:tinkex, :custom_loss, :stop],
  fn _event, measurements, metadata, _config ->
    # Log to monitoring system
    MyMonitoring.record_metric("training.loss", measurements.loss_total)
    MyMonitoring.record_metric("training.regularizers", metadata.regularizer_count)
  end,
  nil
)
```

## See Also

- **API Reference**: `docs/guides/api_reference.md`
- **Training Loop**: `docs/guides/training_loop.md`
- **Examples**: `examples/structured_regularizers.exs`, `examples/structured_regularizers_live.exs`
- **Source Code**: `lib/tinkex/regularizer/`
