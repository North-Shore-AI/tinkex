# Structured Regularizers Example
#
# This example demonstrates the full structured regularizer composition feature
# in Tinkex, including:
#
# - Custom loss functions with composable regularizers
# - Multiple regularizer types (L1 sparsity, entropy, KL divergence)
# - Parallel vs sequential execution
# - Gradient norm tracking for training dynamics monitoring
# - Async regularizers for I/O-bound operations
# - Telemetry integration for observability
# - JSON serialization of outputs
#
# Run with: mix run examples/structured_regularizers.exs
#
# Note: This example uses mock data to demonstrate the API without requiring
# a live Tinker backend connection.

alias Tinkex.Types.RegularizerSpec
alias Tinkex.Regularizer.{Pipeline, Executor, GradientTracker, Telemetry}

IO.puts("""
================================================================================
Structured Regularizers in Tinkex
================================================================================

This example demonstrates custom loss computation with composable regularizers.
The total loss is computed as:

  loss_total = base_loss + Σ(weight_i × regularizer_i_loss)

Each regularizer can track gradient norms for monitoring training dynamics.
""")

# =============================================================================
# 1. BASIC TYPES AND CONFIGURATION
# =============================================================================

IO.puts("\n--- 1. Creating RegularizerSpec Configurations ---\n")

# L1 Sparsity Regularizer - encourages sparse activations
# NOTE: For gradient tracking compatibility, metrics are computed separately
# from the loss. Nx.to_number cannot be called inside traced functions.
l1_regularizer =
  RegularizerSpec.new(%{
    fn: fn _data, logprobs ->
      l1_sum = Nx.sum(Nx.abs(logprobs))
      # Return empty metrics - we compute metrics from the loss value later
      {l1_sum, %{}}
    end,
    weight: 0.01,
    name: "l1_sparsity"
  })

IO.puts("Created L1 sparsity regularizer: weight=#{l1_regularizer.weight}")

# Entropy Regularizer - encourages diversity in predictions
entropy_regularizer =
  RegularizerSpec.new(%{
    fn: fn _data, logprobs ->
      # Convert logprobs to probabilities
      probs = Nx.exp(logprobs)
      # Compute negative entropy (we want to maximize entropy, so minimize negative)
      neg_entropy = Nx.sum(Nx.multiply(probs, logprobs))
      {neg_entropy, %{}}
    end,
    weight: 0.001,
    name: "entropy"
  })

IO.puts("Created entropy regularizer: weight=#{entropy_regularizer.weight}")

# L2 Regularizer - weight decay
l2_regularizer =
  RegularizerSpec.new(%{
    fn: fn _data, logprobs ->
      l2_squared = Nx.sum(Nx.pow(logprobs, 2))
      {l2_squared, %{}}
    end,
    weight: 0.005,
    name: "l2_weight_decay"
  })

IO.puts("Created L2 regularizer: weight=#{l2_regularizer.weight}")

# =============================================================================
# 2. BASE LOSS FUNCTION
# =============================================================================

IO.puts("\n--- 2. Defining Base Loss Function ---\n")

# Negative log-likelihood base loss
# NOTE: For gradient tracking compatibility, avoid Nx.to_number inside the fn.
# Metrics that need conversion should be handled separately after execution.
base_loss_fn = fn _data, logprobs ->
  # Simulate cross-entropy loss: -mean(logprobs)
  nll = Nx.negate(Nx.mean(logprobs))
  # Return empty metrics - the Pipeline/CustomLossOutput will use the loss value
  {nll, %{}}
end

IO.puts("Base loss function: Negative Log-Likelihood with perplexity metric")

# =============================================================================
# 3. MOCK DATA FOR DEMONSTRATION
# =============================================================================

IO.puts("\n--- 3. Creating Mock Data ---\n")

# Simulate logprobs from a forward pass (log probabilities are typically negative)
logprobs =
  Nx.tensor([
    -0.5,
    -1.2,
    -0.8,
    -2.1,
    -0.3,
    -1.5,
    -0.9,
    -1.8,
    -0.6,
    -1.1
  ])

IO.puts("Mock logprobs shape: #{inspect(Nx.shape(logprobs))}")
IO.puts("Mock logprobs values: #{inspect(Nx.to_flat_list(logprobs))}")

# Empty data list (regularizers only use logprobs in this example)
data = []

# =============================================================================
# 4. PIPELINE EXECUTION - NO REGULARIZERS (BASELINE)
# =============================================================================

IO.puts("\n--- 4. Baseline: Base Loss Only ---\n")

{:ok, baseline_output} = Pipeline.compute(data, logprobs, base_loss_fn)

IO.puts("Base loss only:")
IO.puts("  loss_total: #{Float.round(baseline_output.loss_total, 4)}")
# Compute perplexity from NLL loss: exp(nll)
perplexity = :math.exp(baseline_output.loss_total)
IO.puts("  perplexity: #{Float.round(perplexity, 4)}")

# =============================================================================
# 5. PIPELINE EXECUTION - WITH REGULARIZERS
# =============================================================================

IO.puts("\n--- 5. With Regularizers (Parallel Execution) ---\n")

regularizers = [l1_regularizer, entropy_regularizer, l2_regularizer]

{:ok, output} =
  Pipeline.compute(data, logprobs, base_loss_fn,
    regularizers: regularizers,
    parallel: true
  )

IO.puts("Composed loss with #{length(regularizers)} regularizers:")
IO.puts("  loss_total: #{Float.round(output.loss_total, 4)}")
IO.puts("  base_loss: #{Float.round(output.base_loss.value, 4)}")
IO.puts("  regularizer_total: #{Float.round(output.regularizer_total, 4)}")
IO.puts("")
IO.puts("Per-regularizer breakdown:")

for {name, reg} <- output.regularizers do
  IO.puts("  #{name}:")
  IO.puts("    value: #{Float.round(reg.value, 4)}")
  IO.puts("    weight: #{reg.weight}")
  IO.puts("    contribution: #{Float.round(reg.contribution, 4)}")
end

# =============================================================================
# 6. GRADIENT NORM TRACKING
# =============================================================================

IO.puts("\n--- 6. With Gradient Norm Tracking ---\n")

{:ok, grad_output} =
  Pipeline.compute(data, logprobs, base_loss_fn,
    regularizers: regularizers,
    track_grad_norms: true,
    parallel: true
  )

IO.puts("Gradient norms for training dynamics monitoring:")
IO.puts("  base_loss grad_norm: #{Float.round(grad_output.base_loss.grad_norm, 4)}")
IO.puts("  total_grad_norm: #{Float.round(grad_output.total_grad_norm, 4)}")
IO.puts("")
IO.puts("Per-regularizer gradient norms:")

for {name, reg} <- grad_output.regularizers do
  IO.puts("  #{name}:")
  IO.puts("    grad_norm: #{Float.round(reg.grad_norm, 4)}")
  IO.puts("    grad_norm_weighted: #{Float.round(reg.grad_norm_weighted, 6)}")
end

# =============================================================================
# 7. SEQUENTIAL VS PARALLEL COMPARISON
# =============================================================================

IO.puts("\n--- 7. Sequential vs Parallel Execution ---\n")

# Parallel execution
{parallel_time, {:ok, parallel_output}} =
  :timer.tc(fn ->
    Pipeline.compute(data, logprobs, base_loss_fn,
      regularizers: regularizers,
      parallel: true
    )
  end)

# Sequential execution
{sequential_time, {:ok, sequential_output}} =
  :timer.tc(fn ->
    Pipeline.compute(data, logprobs, base_loss_fn,
      regularizers: regularizers,
      parallel: false
    )
  end)

IO.puts("Execution time comparison:")
IO.puts("  Parallel: #{parallel_time} μs")
IO.puts("  Sequential: #{sequential_time} μs")
IO.puts("  Results match: #{parallel_output.loss_total == sequential_output.loss_total}")

# =============================================================================
# 8. ASYNC REGULARIZERS
# =============================================================================

IO.puts("\n--- 8. Async Regularizers (for I/O-bound operations) ---\n")

# Simulate an async regularizer that might call an external API
async_regularizer =
  RegularizerSpec.new(%{
    fn: fn _data, logprobs ->
      Task.async(fn ->
        # Simulate I/O delay (in real use: external API, database, etc.)
        Process.sleep(10)

        # Compute some penalty
        penalty = Nx.mean(Nx.abs(logprobs))
        {penalty, %{"async_computed" => true, "simulated_delay_ms" => 10}}
      end)
    end,
    weight: 0.02,
    name: "async_external_validation",
    async: true
  })

IO.puts("Created async regularizer (simulates external API call)")

{async_time, {:ok, async_output}} =
  :timer.tc(fn ->
    Pipeline.compute(data, logprobs, base_loss_fn,
      regularizers: [async_regularizer],
      timeout: 5000
    )
  end)

IO.puts("Async regularizer result:")
IO.puts("  loss_total: #{Float.round(async_output.loss_total, 4)}")

IO.puts(
  "  async_external_validation contribution: #{Float.round(async_output.regularizers["async_external_validation"].contribution, 4)}"
)

IO.puts("  Execution time: #{async_time} μs")

# =============================================================================
# 9. DIRECT EXECUTOR USAGE
# =============================================================================

IO.puts("\n--- 9. Direct Executor Usage ---\n")

# Execute a single regularizer
{:ok, single_output} =
  Executor.execute_one(l1_regularizer, data, logprobs, track_grad_norms: true)

IO.puts("Single regularizer execution via Executor:")
IO.puts("  name: #{single_output.name}")
IO.puts("  value: #{Float.round(single_output.value, 4)}")
IO.puts("  contribution: #{Float.round(single_output.contribution, 4)}")
IO.puts("  grad_norm: #{Float.round(single_output.grad_norm, 4)}")

# Execute multiple regularizers
{:ok, all_outputs} =
  Executor.execute_all(regularizers, data, logprobs,
    parallel: true,
    track_grad_norms: true
  )

IO.puts("\nAll regularizers via Executor.execute_all:")

for output <- all_outputs do
  IO.puts(
    "  #{output.name}: value=#{Float.round(output.value, 4)}, grad_norm=#{Float.round(output.grad_norm, 4)}"
  )
end

# =============================================================================
# 10. GRADIENT TRACKER DIRECT USAGE
# =============================================================================

IO.puts("\n--- 10. Direct GradientTracker Usage ---\n")

# Compute gradient norm for a simple loss function
simple_loss = fn x -> Nx.sum(x) end
simple_grad_norm = GradientTracker.compute_grad_norm(simple_loss, logprobs)

IO.puts("Gradient norm for sum(x):")
IO.puts("  grad_norm: #{Float.round(simple_grad_norm, 4)}")
IO.puts("  (Expected: sqrt(n) = sqrt(10) ≈ 3.162)")

# Compute gradient norm for squared loss
squared_loss = fn x -> Nx.sum(Nx.pow(x, 2)) end
squared_grad_norm = GradientTracker.compute_grad_norm(squared_loss, logprobs)

IO.puts("\nGradient norm for sum(x^2):")
IO.puts("  grad_norm: #{Float.round(squared_grad_norm, 4)}")
IO.puts("  (Gradient is 2x, so norm depends on input values)")

# =============================================================================
# 11. TELEMETRY INTEGRATION
# =============================================================================

IO.puts("\n--- 11. Telemetry Integration ---\n")

# Attach telemetry logger
handler_id = Telemetry.attach_logger(level: :info)
IO.puts("Attached telemetry handler: #{handler_id}")

# Run pipeline with telemetry enabled
IO.puts("\nRunning pipeline with telemetry (watch for log output):")

{:ok, _telemetry_output} =
  Pipeline.compute(data, logprobs, base_loss_fn,
    regularizers: [l1_regularizer],
    track_grad_norms: true
  )

# Detach handler
:ok = Telemetry.detach(handler_id)
IO.puts("Detached telemetry handler")

# =============================================================================
# 12. JSON SERIALIZATION
# =============================================================================

IO.puts("\n--- 12. JSON Serialization ---\n")

# Serialize CustomLossOutput to JSON
json = Jason.encode!(grad_output, pretty: true)

IO.puts("CustomLossOutput as JSON:")
IO.puts(String.slice(json, 0, 500) <> "...")
IO.puts("\n(Output truncated for display)")

# Serialize single RegularizerOutput
reg_json = Jason.encode!(single_output, pretty: true)
IO.puts("\nRegularizerOutput as JSON:")
IO.puts(reg_json)

# =============================================================================
# 13. ERROR HANDLING
# =============================================================================

IO.puts("\n--- 13. Error Handling ---\n")

# Duplicate regularizer names
duplicate_regs = [
  %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end, weight: 0.1, name: "dup"},
  %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(2.0), %{}} end, weight: 0.2, name: "dup"}
]

case Pipeline.compute(data, logprobs, base_loss_fn, regularizers: duplicate_regs) do
  {:error, {:pipeline_failed, %ArgumentError{message: msg}}} ->
    IO.puts("Caught expected error for duplicate names:")
    IO.puts("  #{msg}")

  _ ->
    IO.puts("Unexpected result")
end

# Invalid base loss function
case Pipeline.compute(data, logprobs, "not a function") do
  {:error, {:pipeline_failed, %ArgumentError{}}} ->
    IO.puts("\nCaught expected error for invalid base_loss_fn")

  _ ->
    IO.puts("Unexpected result")
end

# =============================================================================
# 14. REGULARIZER BEHAVIOUR MODULE
# =============================================================================

IO.puts("\n--- 14. Module-Based Regularizer (Behaviour) ---\n")

defmodule Examples.L1Regularizer do
  @behaviour Tinkex.Regularizer

  @impl true
  def compute(_data, logprobs, _opts) do
    l1 = Nx.sum(Nx.abs(logprobs))
    {l1, %{"l1_value" => Nx.to_number(l1)}}
  end

  @impl true
  def name, do: "module_l1"
end

# Use module-based regularizer
{loss, metrics} = Tinkex.Regularizer.execute(Examples.L1Regularizer, data, logprobs)

IO.puts("Module-based regularizer (implements Tinkex.Regularizer behaviour):")
IO.puts("  name: #{Examples.L1Regularizer.name()}")
IO.puts("  loss: #{Float.round(Nx.to_number(loss), 4)}")
IO.puts("  metrics: #{inspect(metrics)}")

# =============================================================================
# 15. LIVE API USAGE (requires running Tinker server)
# =============================================================================

IO.puts("""

--- 15. Live API Usage ---

To use with a real Tinker server, replace Pipeline.compute with TrainingClient:

```elixir
# 1. Connect to server
config = Tinkex.Config.new(
  host: "your-tinker-host",
  api_key: System.get_env("TINKER_API_KEY")
)

# 2. Create training client
{:ok, session} = Tinkex.SessionManager.start_session(config, "your-model")
{:ok, client} = Tinkex.TrainingClient.create(session)

# 3. Prepare training data (tokenized)
data = [
  %Datum{
    inputs: %ModelInput{tokens: [1, 2, 3, 4, 5]},
    targets: %ModelInput{tokens: [6, 7, 8, 9, 10]}
  }
]

# 4. Define regularizers
regularizers = [
  RegularizerSpec.new(fn: &l1_sparsity/2, weight: 0.01, name: "l1"),
  RegularizerSpec.new(fn: &entropy/2, weight: 0.001, name: "entropy")
]

# 5. Call forward_backward_custom (hits live API!)
{:ok, task} = TrainingClient.forward_backward_custom(
  client, data, &base_loss/2,
  regularizers: regularizers,
  track_grad_norms: true
)

{:ok, output} = Task.await(task, :infinity)

# output is a CustomLossOutput with real logprobs from the server!
IO.puts("Total loss: \#{output.loss_total}")
```

The Pipeline.compute calls in this example use mock logprobs.
TrainingClient.forward_backward_custom does a real forward pass on the server,
then runs Pipeline.compute with the actual logprobs returned.
""")

# =============================================================================
# 16. SUMMARY
# =============================================================================

IO.puts("""

================================================================================
Summary
================================================================================

The structured regularizer system provides:

1. **RegularizerSpec** - Type-safe configuration for regularizers
   - fn: Loss computation function (arity 2 or 3)
   - weight: Non-negative multiplier
   - name: Unique identifier for telemetry
   - async: Support for Task-returning functions

2. **Pipeline.compute/4** - Orchestrates full loss composition
   - Base loss + weighted regularizers
   - Parallel or sequential execution
   - Optional gradient norm tracking
   - Comprehensive telemetry

3. **Executor** - Low-level regularizer execution
   - execute_one/4 for single regularizer
   - execute_all/4 for batched execution
   - Timeout and error handling

4. **GradientTracker** - Nx-based gradient computation
   - compute_grad_norm/2 for L2 norms
   - grad_norm_for_regularizer/3 for per-regularizer tracking
   - total_grad_norm/4 for composed loss

5. **Telemetry** - Observable training dynamics
   - [:tinkex, :custom_loss, :start | :stop | :exception]
   - [:tinkex, :regularizer, :compute, :start | :stop | :exception]

6. **JSON Serialization** - Export metrics for analysis
   - CustomLossOutput implements Jason.Encoder
   - RegularizerOutput implements Jason.Encoder

For production use with a Tinker backend, wrap these in:

  {:ok, task} = TrainingClient.forward_backward_custom(
    client, data, base_loss_fn,
    regularizers: regularizers,
    track_grad_norms: true
  )
  {:ok, output} = Task.await(task)

================================================================================
""")
