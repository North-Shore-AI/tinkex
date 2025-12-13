# Forward Inference

This guide covers forward-only inference using the `TrainingClient.forward/4` API. Forward inference runs a model's forward pass without computing gradients, returning logprobs that can be converted to Nx tensors for custom analysis and loss computation.

## Overview

Forward inference differs from the full training loop in a key way:

- **`forward_backward/4`**: Computes both forward pass (logits → loss) and backward pass (gradients)
- **`forward/4`**: Computes only the forward pass, returning logprobs without gradients

The forward-only API is useful when you need model outputs but don't need the backend to compute gradients. You might compute custom losses in Elixir/Nx, perform model evaluation, or analyze token probabilities.

## When to Use Forward Inference

Use `forward/4` instead of `forward_backward/4` when you need:

1. **Custom loss computation**: Compute losses in Elixir/Nx where gradients will be calculated locally
2. **Model evaluation**: Calculate perplexity, accuracy, or other metrics without training
3. **Token analysis**: Analyze probability distributions over tokens
4. **Regularizer development**: Build custom regularizers that need logprobs but compute their own gradients
5. **Inference-only workflows**: Get model predictions without updating weights
6. **Performance profiling**: Measure forward pass latency without backward overhead

For standard training with built-in loss functions, use `forward_backward/4` as shown in the [training loop guide](training_loop.md).

## Quick Start

```elixir
{:ok, _} = Application.ensure_all_started(:tinkex)

config = Tinkex.Config.new(
  api_key: System.fetch_env!("TINKER_API_KEY"),
  base_url: System.get_env("TINKER_BASE_URL")
)

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service, "meta-llama/Llama-3.1-8B",
  lora_config: %Tinkex.Types.LoraConfig{rank: 16}
)

{:ok, model_input} = Tinkex.Types.ModelInput.from_text(
  "The capital of France is",
  model_name: "meta-llama/Llama-3.1-8B",
  training_client: training
)

# Build datum with target tokens
tokens = model_input.chunks |> hd() |> Map.get(:tokens)
datum = Tinkex.Types.Datum.new(%{
  model_input: model_input,
  loss_fn_inputs: %{
    target_tokens: %Tinkex.Types.TensorData{
      data: tokens,
      dtype: :int64,
      shape: [length(tokens)]
    },
    weights: %Tinkex.Types.TensorData{
      data: List.duplicate(1.0, length(tokens)),
      dtype: :float32,
      shape: [length(tokens)]
    }
  }
})

# Run forward pass (inference only, no backward)
{:ok, task} = Tinkex.TrainingClient.forward(training, [datum], :cross_entropy)
{:ok, output} = Task.await(task, 60_000)

IO.inspect(output.metrics, label: "metrics")
```

## Setting Up TrainingClient for Forward Inference

The setup process is identical to a standard training workflow:

### 1. Create a Service Client

```elixir
config = Tinkex.Config.new(
  api_key: System.fetch_env!("TINKER_API_KEY")
)

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
```

### 2. Create a Training Client

```elixir
{:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service, "meta-llama/Llama-3.1-8B",
  lora_config: %Tinkex.Types.LoraConfig{rank: 16}
)
```

Even though you're doing inference, you still use a `TrainingClient` because the forward pass operates on the same infrastructure as training.

### 3. Prepare Input Data

```elixir
# Option 1: From text (automatic tokenization)
{:ok, model_input} = Tinkex.Types.ModelInput.from_text(
  "Your prompt here",
  model_name: "meta-llama/Llama-3.1-8B",
  training_client: training
)

# Option 2: From token IDs directly
model_input = %Tinkex.Types.ModelInput{
  chunks: [
    %{
      tokens: [1, 450, 6864, 315, 9822, 374],
      chunk_index: 0
    }
  ]
}
```

## Using TrainingClient.forward/4

The `forward/4` function signature is:

```elixir
@spec forward(t(), [map()], atom() | String.t(), keyword()) ::
  {:ok, Task.t()} | {:error, Error.t()}
```

### Parameters

- **client**: The `TrainingClient` pid
- **data**: List of `Datum` structs containing model inputs and loss function inputs
- **loss_fn**: Loss function name (e.g., `:cross_entropy`) - determines logprobs format
- **opts**: Optional keyword list for configuration

### Return Value

Always returns `{:ok, task}` where the task yields:
- `{:ok, %ForwardBackwardOutput{}}` on success
- `{:error, %Tinkex.Error{}}` on failure

### Example Usage

```elixir
# Build datum with input and target
datum = Tinkex.Types.Datum.new(%{
  model_input: model_input,
  loss_fn_inputs: %{
    target_tokens: to_tensor(target_tokens, :int64),
    weights: to_tensor(weights, :float32)
  }
})

# Run forward pass
{:ok, task} = Tinkex.TrainingClient.forward(training, [datum], :cross_entropy)

# Await result
{:ok, output} = Task.await(task, 60_000)
```

### Options

The `opts` keyword list supports:

- `:loss_fn_config` - Configuration for the loss function (map)
- `:timeout` - HTTP request timeout in milliseconds
- `:http_timeout` - Alias for `:timeout`
- `:telemetry_metadata` - Additional telemetry metadata (map)
- `:await_timeout` - Maximum time to wait for task completion

## Understanding Logprobs Output

The forward pass returns a `ForwardBackwardOutput` struct containing logprobs in the `loss_fn_outputs` field.

### Output Structure

```elixir
%Tinkex.Types.ForwardBackwardOutput{
  metrics: %{
    "total_loss" => 2.456,
    "mean_loss" => 2.456,
    # ... other metrics
  },
  loss_fn_outputs: [
    %{
      "logprobs" => %{
        "data" => [...],      # Flat list of float32 values
        "dtype" => "float32",
        "shape" => [seq_len, vocab_size]
      }
    }
  ],
  loss_fn_output_type: "cross_entropy"
}
```

### Accessing Logprobs

```elixir
{:ok, output} = Task.await(task)

# Extract first output
[first_output | _] = output.loss_fn_outputs

# Get logprobs structure
%{"logprobs" => logprobs_data} = first_output

# logprobs_data contains:
# - data: flat list of probabilities
# - dtype: tensor data type (usually "float32")
# - shape: [sequence_length, vocabulary_size]
```

### Logprobs Format by Loss Function

Different loss functions return logprobs in different formats:

**`:cross_entropy`**
```elixir
%{
  "logprobs" => %{
    "data" => [0.1, 0.2, ...],  # Log probabilities
    "dtype" => "float32",
    "shape" => [seq_len, vocab_size]
  }
}
```

The shape indicates `[sequence_length, vocabulary_size]`, where:
- `sequence_length`: Number of tokens in the input
- `vocabulary_size`: Size of the model's token vocabulary (e.g., 128256 for Llama-3.1)

## Working with Nx Tensors

The logprobs can be converted to Nx tensors for numerical operations using `TensorData.to_nx/1`.

### Converting to Nx

```elixir
alias Tinkex.Types.TensorData

# Extract logprobs from output
[%{"logprobs" => logprobs}] = output.loss_fn_outputs

# Create TensorData struct
tensor_data = %TensorData{
  data: logprobs["data"],
  dtype: parse_dtype(logprobs["dtype"]),
  shape: logprobs["shape"]
}

# Convert to Nx tensor
nx_tensor = TensorData.to_nx(tensor_data)

# Now you can use Nx operations
mean_logprob = Nx.mean(nx_tensor)
max_logprob = Nx.reduce_max(nx_tensor)
```

### Data Type Conversion

The `dtype` field in the API response is a string. Convert it to an Nx-compatible atom:

```elixir
defp parse_dtype("float32"), do: :float32
defp parse_dtype("float64"), do: :float64
defp parse_dtype("int64"), do: :int64
defp parse_dtype("int32"), do: :int32
defp parse_dtype(atom) when is_atom(atom), do: atom
defp parse_dtype(_), do: :float32  # fallback
```

### Nx Operations on Logprobs

Once converted to an Nx tensor, you can perform various operations:

```elixir
# Basic statistics
mean = Nx.mean(nx_tensor) |> Nx.to_number()
variance = Nx.variance(nx_tensor) |> Nx.to_number()
min_val = Nx.reduce_min(nx_tensor) |> Nx.to_number()
max_val = Nx.reduce_max(nx_tensor) |> Nx.to_number()

# Reshape for per-token analysis
# If shape is [seq_len, vocab_size]
{seq_len, vocab_size} = Nx.shape(nx_tensor)

# Get probabilities for each position
per_token_probs = Nx.slice_along_axis(nx_tensor, 0, 1, axis: 0)

# Softmax to get probability distribution
probs = Nx.exp(nx_tensor) / Nx.sum(Nx.exp(nx_tensor), axes: [1])

# Find most likely token at each position
most_likely = Nx.argmax(nx_tensor, axis: 1)
```

## Converting Between Tinkex Types and Nx

### TensorData → Nx

```elixir
# From Tinkex TensorData to Nx tensor
tensor_data = %Tinkex.Types.TensorData{
  data: [1.0, 2.0, 3.0, 4.0],
  dtype: :float32,
  shape: [2, 2]
}

nx_tensor = Tinkex.Types.TensorData.to_nx(tensor_data)
# => #Nx.Tensor<
#      f32[2][2]
#      [
#        [1.0, 2.0],
#        [3.0, 4.0]
#      ]
#    >
```

### Nx → TensorData

```elixir
# From Nx tensor to Tinkex TensorData
nx_tensor = Nx.tensor([[1, 2], [3, 4]], type: :s64)

tensor_data = %Tinkex.Types.TensorData{
  data: Nx.to_flat_list(nx_tensor),
  dtype: nx_type_to_tinkex(Nx.type(nx_tensor)),
  shape: Tuple.to_list(Nx.shape(nx_tensor))
}

defp nx_type_to_tinkex({:s, 64}), do: :int64
defp nx_type_to_tinkex({:s, 32}), do: :int32
defp nx_type_to_tinkex({:f, 32}), do: :float32
defp nx_type_to_tinkex({:f, 64}), do: :float64
```

### Building Datum with Nx Tensors

```elixir
# Helper to convert list to TensorData
defp to_tensor(data, dtype) when is_list(data) do
  %Tinkex.Types.TensorData{
    data: data,
    dtype: dtype,
    shape: [length(data)]
  }
end

# Or from Nx tensor directly
defp nx_to_tensor_data(nx_tensor) do
  %Tinkex.Types.TensorData{
    data: Nx.to_flat_list(nx_tensor),
    dtype: nx_type_to_tinkex(Nx.type(nx_tensor)),
    shape: Tuple.to_list(Nx.shape(nx_tensor))
  }
end

# Use in datum construction
target_tensor = Nx.tensor(target_tokens, type: :s64)
weights_tensor = Nx.broadcast(1.0, {length(target_tokens)})

datum = Tinkex.Types.Datum.new(%{
  model_input: model_input,
  loss_fn_inputs: %{
    target_tokens: nx_to_tensor_data(target_tensor),
    weights: nx_to_tensor_data(weights_tensor)
  }
})
```

## Use Cases

### 1. Model Evaluation

Calculate perplexity on a validation set without training:

```elixir
defmodule ModelEvaluator do
  def evaluate_perplexity(training_client, validation_data) do
    results = Enum.map(validation_data, fn {text, _label} ->
      {:ok, model_input} = Tinkex.Types.ModelInput.from_text(
        text,
        model_name: "meta-llama/Llama-3.1-8B",
        training_client: training_client
      )

      tokens = get_tokens(model_input)
      datum = build_datum(model_input, tokens)

      {:ok, task} = Tinkex.TrainingClient.forward(
        training_client,
        [datum],
        :cross_entropy
      )

      {:ok, output} = Task.await(task, 60_000)
      output.metrics["mean_loss"]
    end)

    # Perplexity = exp(average loss)
    avg_loss = Enum.sum(results) / length(results)
    perplexity = :math.exp(avg_loss)

    %{
      perplexity: perplexity,
      average_loss: avg_loss,
      sample_count: length(results)
    }
  end

  defp get_tokens(%{chunks: [chunk | _]}), do: chunk.tokens || chunk["tokens"]

  defp build_datum(model_input, tokens) do
    Tinkex.Types.Datum.new(%{
      model_input: model_input,
      loss_fn_inputs: %{
        target_tokens: to_tensor(tokens, :int64),
        weights: to_tensor(List.duplicate(1.0, length(tokens)), :float32)
      }
    })
  end

  defp to_tensor(data, dtype) do
    %Tinkex.Types.TensorData{
      data: data,
      dtype: dtype,
      shape: [length(data)]
    }
  end
end

# Usage
perplexity_report = ModelEvaluator.evaluate_perplexity(training, validation_set)
IO.inspect(perplexity_report)
# => %{perplexity: 12.34, average_loss: 2.513, sample_count: 100}
```

### 2. Token Probability Analysis

Analyze the probability distribution for specific tokens:

```elixir
defmodule TokenAnalyzer do
  alias Tinkex.Types.TensorData

  def analyze_token_probabilities(training_client, text, target_word) do
    {:ok, model_input} = Tinkex.Types.ModelInput.from_text(
      text,
      model_name: "meta-llama/Llama-3.1-8B",
      training_client: training_client
    )

    tokens = get_tokens(model_input)
    datum = build_datum(model_input, tokens)

    {:ok, task} = Tinkex.TrainingClient.forward(
      training_client,
      [datum],
      :cross_entropy
    )

    {:ok, output} = Task.await(task, 60_000)

    # Extract logprobs and convert to Nx
    [%{"logprobs" => logprobs_data}] = output.loss_fn_outputs

    tensor_data = %TensorData{
      data: logprobs_data["data"],
      dtype: :float32,
      shape: logprobs_data["shape"]
    }

    logprobs = TensorData.to_nx(tensor_data)

    # Get probability distribution for each position
    # logprobs shape: [seq_len, vocab_size]
    probs = Nx.exp(logprobs)

    # Find most likely tokens at each position
    most_likely_indices = Nx.argmax(logprobs, axis: 1)

    %{
      sequence_length: elem(Nx.shape(logprobs), 0),
      vocab_size: elem(Nx.shape(logprobs), 1),
      most_likely_tokens: Nx.to_flat_list(most_likely_indices),
      average_confidence: Nx.mean(Nx.reduce_max(probs, axes: [1])) |> Nx.to_number()
    }
  end

  defp get_tokens(%{chunks: [chunk | _]}), do: chunk.tokens || chunk["tokens"]

  defp build_datum(model_input, tokens) do
    Tinkex.Types.Datum.new(%{
      model_input: model_input,
      loss_fn_inputs: %{
        target_tokens: %TensorData{data: tokens, dtype: :int64, shape: [length(tokens)]},
        weights: %TensorData{data: List.duplicate(1.0, length(tokens)), dtype: :float32, shape: [length(tokens)]}
      }
    })
  end
end

# Usage
analysis = TokenAnalyzer.analyze_token_probabilities(
  training,
  "The capital of France is Paris",
  "Paris"
)

IO.inspect(analysis)
```

### 3. Custom Loss Computation

Compute a custom loss in Nx with your own gradient logic:

```elixir
defmodule CustomLoss do
  def compute_with_regularization(training_client, data, lambda \\ 0.01) do
    # Get logprobs from forward pass
    {:ok, task} = Tinkex.TrainingClient.forward(
      training_client,
      data,
      :cross_entropy
    )

    {:ok, output} = Task.await(task, 60_000)

    # Extract logprobs
    [%{"logprobs" => logprobs_data}] = output.loss_fn_outputs

    logprobs = Tinkex.Types.TensorData.to_nx(%Tinkex.Types.TensorData{
      data: logprobs_data["data"],
      dtype: :float32,
      shape: logprobs_data["shape"]
    })

    # Compute base cross-entropy loss
    base_loss = output.metrics["mean_loss"]

    # Add custom L2 regularization in Nx
    l2_penalty = lambda * Nx.sum(Nx.pow(logprobs, 2)) / Nx.size(logprobs)
    l2_value = Nx.to_number(l2_penalty)

    total_loss = base_loss + l2_value

    %{
      base_loss: base_loss,
      l2_penalty: l2_value,
      total_loss: total_loss,
      logprobs_shape: Nx.shape(logprobs)
    }
  end
end

# Usage
loss_report = CustomLoss.compute_with_regularization(training, [datum], 0.001)
IO.inspect(loss_report)
```

### 4. Perplexity Calculation

Calculate perplexity for language model evaluation:

```elixir
defmodule Perplexity do
  def calculate(training_client, text_samples) do
    losses = Enum.map(text_samples, fn text ->
      {:ok, model_input} = Tinkex.Types.ModelInput.from_text(
        text,
        model_name: "meta-llama/Llama-3.1-8B",
        training_client: training_client
      )

      tokens = get_first_chunk_tokens(model_input)
      datum = %Tinkex.Types.Datum{
        model_input: model_input,
        loss_fn_inputs: %{
          target_tokens: to_tensor(tokens, :int64),
          weights: to_tensor(List.duplicate(1.0, length(tokens)), :float32)
        }
      }

      {:ok, task} = Tinkex.TrainingClient.forward(training_client, [datum], :cross_entropy)
      {:ok, output} = Task.await(task, 60_000)

      output.metrics["mean_loss"]
    end)

    avg_loss = Enum.sum(losses) / length(losses)
    perplexity = :math.exp(avg_loss)

    %{
      perplexity: perplexity,
      average_loss: avg_loss,
      num_samples: length(text_samples)
    }
  end

  defp get_first_chunk_tokens(%{chunks: [chunk | _]}) do
    Map.get(chunk, :tokens) || Map.get(chunk, "tokens") || []
  end

  defp to_tensor(data, dtype) when is_list(data) do
    %Tinkex.Types.TensorData{
      data: data,
      dtype: dtype,
      shape: [length(data)]
    }
  end
end

# Usage
samples = [
  "The quick brown fox jumps over the lazy dog",
  "Machine learning models require large datasets",
  "Natural language processing is fascinating"
]

result = Perplexity.calculate(training, samples)
IO.puts("Perplexity: #{result.perplexity}")
```

## Performance Considerations

### 1. Batching and Chunking

The `forward/4` function automatically chunks large batches to avoid overwhelming the backend:

- **Max chunk size**: 128 examples
- **Max token count**: 500,000 numbers per chunk

Large datasets are automatically split and processed sequentially:

```elixir
# This gets chunked automatically
large_batch = Enum.map(1..1000, fn i ->
  build_datum("Sample text #{i}")
end)

{:ok, task} = Tinkex.TrainingClient.forward(training, large_batch, :cross_entropy)
```

### 2. Async vs Sync

The `forward/4` function returns a `Task.t()`, allowing async workflows:

```elixir
# Start multiple forward passes in parallel
tasks = Enum.map(batches, fn batch ->
  {:ok, task} = Tinkex.TrainingClient.forward(training, batch, :cross_entropy)
  task
end)

# Await all results
results = Enum.map(tasks, &Task.await(&1, 60_000))
```

### 3. Memory Management

Logprobs tensors can be large (sequence_length × vocab_size):

- Llama-3.1-8B vocabulary size: 128,256
- Sequence length 512: ~512 × 128,256 × 4 bytes = ~250 MB per forward pass

Consider:

```elixir
# Process in smaller batches
batches = Enum.chunk_every(large_dataset, 10)

results = Enum.map(batches, fn batch ->
  {:ok, task} = Tinkex.TrainingClient.forward(training, batch, :cross_entropy)
  {:ok, output} = Task.await(task)

  # Extract only what you need
  metrics = output.metrics

  # Let logprobs be garbage collected
  metrics
end)
```

### 4. Timeout Configuration

Adjust timeouts based on data size:

```elixir
# For large sequences or batches
{:ok, task} = Tinkex.TrainingClient.forward(
  training,
  large_batch,
  :cross_entropy,
  timeout: 120_000,  # 2 minutes for HTTP request
  await_timeout: 180_000  # 3 minutes for task completion
)

{:ok, output} = Task.await(task, 180_000)
```

### 5. EXLA Backend

Nx operations on logprobs can leverage EXLA for GPU acceleration.

Note: EXLA is optional and is not started automatically. Start it before
switching backends.

```elixir
# Ensure EXLA is started, then set it as the default backend
{:ok, _} = Application.ensure_all_started(:exla)
Nx.default_backend(EXLA.Backend)

# Now all Nx operations use GPU if available
logprobs_tensor = TensorData.to_nx(tensor_data)
mean = Nx.mean(logprobs_tensor)  # Runs on GPU
```

## Complete Example

Here's a complete example that demonstrates forward inference for model evaluation:

```elixir
defmodule ForwardInferenceExample do
  alias Tinkex.Types.{TensorData, Datum, ModelInput}

  def run do
    # 1. Setup
    {:ok, _} = Application.ensure_all_started(:tinkex)

    config = Tinkex.Config.new(
      api_key: System.fetch_env!("TINKER_API_KEY")
    )

    {:ok, service} = Tinkex.ServiceClient.start_link(config: config)

    {:ok, training} = Tinkex.ServiceClient.create_lora_training_client(
      service,
      "meta-llama/Llama-3.1-8B",
      lora_config: %Tinkex.Types.LoraConfig{rank: 16}
    )

    # 2. Prepare test data
    test_prompts = [
      "The capital of France is",
      "Machine learning is",
      "The quick brown fox"
    ]

    # 3. Run forward inference on each
    results = Enum.map(test_prompts, fn prompt ->
      analyze_prompt(training, prompt)
    end)

    # 4. Display results
    Enum.each(Enum.zip(test_prompts, results), fn {prompt, result} ->
      IO.puts("\nPrompt: #{prompt}")
      IO.puts("Loss: #{Float.round(result.loss, 4)}")
      IO.puts("Perplexity: #{Float.round(result.perplexity, 2)}")
      IO.puts("Tokens: #{result.token_count}")
    end)

    # 5. Calculate overall statistics
    avg_loss = Enum.sum(Enum.map(results, & &1.loss)) / length(results)
    avg_perplexity = :math.exp(avg_loss)

    IO.puts("\n=== Overall Statistics ===")
    IO.puts("Average Loss: #{Float.round(avg_loss, 4)}")
    IO.puts("Average Perplexity: #{Float.round(avg_perplexity, 2)}")
  end

  defp analyze_prompt(training_client, prompt) do
    # Tokenize
    {:ok, model_input} = ModelInput.from_text(
      prompt,
      model_name: "meta-llama/Llama-3.1-8B",
      training_client: training_client
    )

    # Get tokens
    tokens = get_first_chunk_tokens(model_input)
    token_count = length(tokens)

    # Build datum
    datum = Datum.new(%{
      model_input: model_input,
      loss_fn_inputs: %{
        target_tokens: to_tensor(tokens, :int64),
        weights: to_tensor(List.duplicate(1.0, token_count), :float32)
      }
    })

    # Forward pass
    {:ok, task} = Tinkex.TrainingClient.forward(
      training_client,
      [datum],
      :cross_entropy
    )

    {:ok, output} = Task.await(task, 60_000)

    # Extract metrics
    loss = output.metrics["mean_loss"]
    perplexity = :math.exp(loss)

    # Optionally analyze logprobs
    logprobs_stats = analyze_logprobs(output.loss_fn_outputs)

    %{
      loss: loss,
      perplexity: perplexity,
      token_count: token_count,
      logprobs_stats: logprobs_stats
    }
  end

  defp analyze_logprobs([%{"logprobs" => logprobs_data}]) do
    tensor_data = %TensorData{
      data: logprobs_data["data"],
      dtype: :float32,
      shape: logprobs_data["shape"]
    }

    tensor = TensorData.to_nx(tensor_data)

    %{
      shape: Nx.shape(tensor),
      mean: Nx.mean(tensor) |> Nx.to_number(),
      min: Nx.reduce_min(tensor) |> Nx.to_number(),
      max: Nx.reduce_max(tensor) |> Nx.to_number()
    }
  end

  defp analyze_logprobs(_), do: %{}

  defp get_first_chunk_tokens(%{chunks: [chunk | _]}) do
    Map.get(chunk, :tokens) || Map.get(chunk, "tokens") || []
  end

  defp to_tensor(data, dtype) when is_list(data) do
    %TensorData{data: data, dtype: dtype, shape: [length(data)]}
  end
end

# Run the example
ForwardInferenceExample.run()
```

## Troubleshooting

### Issue: Logprobs not in expected format

**Problem**: `loss_fn_outputs` doesn't contain logprobs structure

**Solution**: Ensure you're using the correct loss function. Cross-entropy returns logprobs:

```elixir
# Correct
{:ok, task} = Tinkex.TrainingClient.forward(training, data, :cross_entropy)

# Some loss functions may return different output structures
```

### Issue: Nx tensor shape mismatch

**Problem**: Error when converting TensorData to Nx

**Solution**: Verify the shape matches the data length:

```elixir
# Check data consistency
data_len = length(logprobs_data["data"])
shape = logprobs_data["shape"]
expected_len = Enum.reduce(shape, 1, &*/2)

if data_len != expected_len do
  IO.puts("Warning: data length #{data_len} != expected #{expected_len}")
end
```

### Issue: Out of memory errors

**Problem**: Large logprobs tensors consume too much memory

**Solution**: Process in smaller batches and extract only needed values:

```elixir
# Instead of keeping full tensors
results = Enum.map(large_dataset, fn datum ->
  {:ok, task} = Tinkex.TrainingClient.forward(training, [datum], :cross_entropy)
  {:ok, output} = Task.await(task)

  # Extract only the metric, discard logprobs
  output.metrics["mean_loss"]
end)
```

### Issue: Timeout during forward pass

**Problem**: Task times out on large batches

**Solution**: Increase timeout or reduce batch size:

```elixir
# Increase timeout
{:ok, task} = Tinkex.TrainingClient.forward(
  training,
  data,
  :cross_entropy,
  timeout: 300_000
)

{:ok, output} = Task.await(task, 300_000)

# Or reduce batch size
smaller_batches = Enum.chunk_every(data, 10)
```

## See Also

- [Training Loop Guide](training_loop.md) - Full forward-backward training
- [Getting Started](getting_started.md) - Initial setup and configuration
- [API Reference](api_reference.md) - Complete API documentation
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
