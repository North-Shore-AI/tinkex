# Byte Estimation Utility Specification

## Summary

Create a shared byte estimation utility for `ModelInput` and `Datum` structures, used by both `TrainingClient` (for chunking) and `SamplingClient` (for dispatch throttling). Python SDK v0.7.0 standardizes byte-based sizing across training and sampling.

## Python SDK Reference

### Internal Client Holder Estimators

```python
# tinker/src/tinker/lib/internal_client_holder.py

def estimate_bytes_count_in_chunk(self, chunk: types.ModelInputChunk) -> int:
    if isinstance(chunk, types.ImageChunk):
        return len(chunk.data)
    if isinstance(chunk, types.ImageAssetPointerChunk):
        return len(chunk.location)
    return chunk.length * 10  # Token IDs: 10 bytes per token

def estimate_bytes_count_in_model_input(self, model_input: types.ModelInput) -> int:
    return sum(self.estimate_bytes_count_in_chunk(chunk) for chunk in model_input.chunks)
```

### Training Client Estimator

```python
# tinker/src/tinker/lib/public_interfaces/training_client.py

def _estimate_bytes_count(self, datum: types.Datum) -> int:
    return (
        self.holder.estimate_bytes_count_in_model_input(datum.model_input) +
        sum(len(value.data) * 10 for _, value in datum.loss_fn_inputs.items())
    )
    # Note: loss_fn_inputs use *10 multiplier (same as token data)
```

### Key Design Points

1. **ImageChunk**: Raw byte size of `data` field
2. **ImageAssetPointerChunk**: Byte size of `location` string
3. **EncodedTextChunk** (tokens): `length * 10` bytes per token
4. **loss_fn_inputs (TensorData)**: `len(data) * 10` for numeric arrays

## Current Elixir Implementation

### TrainingClient.DataProcessor

```elixir
# lib/tinkex/training_client/data_processor.ex

defp estimate_number_count_in_chunk(%Tinkex.Types.ImageChunk{data: data})
     when is_binary(data),
     do: byte_size(data)

defp estimate_number_count_in_chunk(%Tinkex.Types.ImageAssetPointerChunk{location: location})
     when is_binary(location),
     do: byte_size(location)

defp estimate_number_count_in_chunk(%Tinkex.Types.EncodedTextChunk{} = chunk),
  do: Tinkex.Types.EncodedTextChunk.length(chunk)  # Token count, NOT bytes
```

### Issues with Current Implementation

1. **EncodedTextChunk** returns token count, not byte estimate
2. **loss_fn_inputs** counted as raw element count, not byte estimate
3. No shared utility between TrainingClient and SamplingClient
4. Naming (`estimate_number_count`) doesn't reflect byte semantics

## Required Changes

### 1. New ByteEstimator Module

**File**: `lib/tinkex/byte_estimator.ex`

```elixir
defmodule Tinkex.ByteEstimator do
  @moduledoc """
  Byte size estimation for ModelInput and Datum structures.

  Provides consistent byte estimation across TrainingClient (chunking)
  and SamplingClient (dispatch throttling). Estimation heuristics match
  Python SDK v0.7.0.

  ## Estimation Heuristics

  - **ImageChunk**: Raw byte size of image data
  - **ImageAssetPointerChunk**: Byte size of location string
  - **EncodedTextChunk**: `token_count * 10` bytes (conservative estimate)
  - **TensorData (loss_fn_inputs)**: `element_count * 10` bytes

  The 10-byte multiplier for tokens/tensors accounts for serialization
  overhead and provides consistent behavior with the Python SDK.
  """

  alias Tinkex.Types.{
    Datum,
    EncodedTextChunk,
    ImageAssetPointerChunk,
    ImageChunk,
    ModelInput,
    TensorData
  }

  @bytes_per_token 10
  @bytes_per_tensor_element 10

  @doc """
  Estimate byte size of a ModelInputChunk.

  ## Examples

      iex> Tinkex.ByteEstimator.estimate_chunk_bytes(%EncodedTextChunk{data: [1, 2, 3]})
      30  # 3 tokens * 10 bytes

      iex> Tinkex.ByteEstimator.estimate_chunk_bytes(%ImageChunk{data: <<0, 1, 2, 3>>})
      4   # Raw byte size
  """
  @spec estimate_chunk_bytes(struct()) :: non_neg_integer()
  def estimate_chunk_bytes(%ImageChunk{data: data}) when is_binary(data) do
    byte_size(data)
  end

  def estimate_chunk_bytes(%ImageAssetPointerChunk{location: location})
      when is_binary(location) do
    byte_size(location)
  end

  def estimate_chunk_bytes(%EncodedTextChunk{} = chunk) do
    EncodedTextChunk.length(chunk) * @bytes_per_token
  end

  # Generic fallback for custom chunk types implementing length/1
  def estimate_chunk_bytes(%{__struct__: mod} = chunk) do
    if function_exported?(mod, :length, 1) do
      mod.length(chunk) * @bytes_per_token
    else
      0
    end
  end

  def estimate_chunk_bytes(_), do: 0

  @doc """
  Estimate byte size of a ModelInput.

  Sums the byte estimates for all chunks in the input.

  ## Examples

      iex> input = %ModelInput{chunks: [%EncodedTextChunk{data: [1, 2, 3, 4, 5]}]}
      iex> Tinkex.ByteEstimator.estimate_model_input_bytes(input)
      50  # 5 tokens * 10 bytes
  """
  @spec estimate_model_input_bytes(ModelInput.t()) :: non_neg_integer()
  def estimate_model_input_bytes(%ModelInput{chunks: chunks}) when is_list(chunks) do
    Enum.reduce(chunks, 0, fn chunk, acc ->
      acc + estimate_chunk_bytes(chunk)
    end)
  end

  def estimate_model_input_bytes(_), do: 0

  @doc """
  Estimate byte size of loss function inputs map.

  Each TensorData entry is estimated as `element_count * #{@bytes_per_tensor_element}` bytes.

  ## Examples

      iex> inputs = %{"target_tokens" => %TensorData{data: [1, 2, 3, 4]}}
      iex> Tinkex.ByteEstimator.estimate_loss_fn_inputs_bytes(inputs)
      40  # 4 elements * 10 bytes
  """
  @spec estimate_loss_fn_inputs_bytes(map()) :: non_neg_integer()
  def estimate_loss_fn_inputs_bytes(loss_fn_inputs) when is_map(loss_fn_inputs) do
    loss_fn_inputs
    |> Map.values()
    |> Enum.reduce(0, fn
      %TensorData{data: data}, acc when is_list(data) ->
        acc + length(data) * @bytes_per_tensor_element

      %{data: data}, acc when is_list(data) ->
        acc + length(data) * @bytes_per_tensor_element

      # Nx.Tensor support
      %Nx.Tensor{} = tensor, acc ->
        acc + Nx.size(tensor) * @bytes_per_tensor_element

      _, acc ->
        acc
    end)
  end

  def estimate_loss_fn_inputs_bytes(_), do: 0

  @doc """
  Estimate total byte size of a Datum.

  Combines model_input and loss_fn_inputs byte estimates.

  ## Examples

      iex> datum = %Datum{
      ...>   model_input: %ModelInput{chunks: [%EncodedTextChunk{data: [1, 2]}]},
      ...>   loss_fn_inputs: %{"target" => %TensorData{data: [1, 2, 3]}}
      ...> }
      iex> Tinkex.ByteEstimator.estimate_datum_bytes(datum)
      50  # (2 tokens * 10) + (3 elements * 10)
  """
  @spec estimate_datum_bytes(Datum.t()) :: non_neg_integer()
  def estimate_datum_bytes(%Datum{model_input: model_input, loss_fn_inputs: loss_fn_inputs}) do
    estimate_model_input_bytes(model_input) + estimate_loss_fn_inputs_bytes(loss_fn_inputs)
  end

  def estimate_datum_bytes(%{model_input: model_input, loss_fn_inputs: loss_fn_inputs}) do
    estimate_model_input_bytes(model_input) + estimate_loss_fn_inputs_bytes(loss_fn_inputs)
  end

  def estimate_datum_bytes(_), do: 0

  @doc """
  Estimate total byte size for a list of Datums.

  ## Examples

      iex> data = [datum1, datum2, datum3]
      iex> Tinkex.ByteEstimator.estimate_data_bytes(data)
      150
  """
  @spec estimate_data_bytes([Datum.t()]) :: non_neg_integer()
  def estimate_data_bytes(data) when is_list(data) do
    Enum.reduce(data, 0, fn datum, acc ->
      acc + estimate_datum_bytes(datum)
    end)
  end
end
```

### 2. Update TrainingClient.DataProcessor

**File**: `lib/tinkex/training_client/data_processor.ex`

```elixir
defmodule Tinkex.TrainingClient.DataProcessor do
  @moduledoc """
  Data chunking, numbering, and tensor operations for TrainingClient.
  """

  alias Tinkex.ByteEstimator  # ADD import
  alias Tinkex.Error
  alias Tinkex.Types.{Datum, TensorData}

  @max_chunk_len 1024              # UPDATED from 128
  @max_chunk_bytes_count 5_000_000  # RENAMED and updated from 500_000

  @doc """
  Chunk data into manageable pieces based on size and byte limits.

  Ensures no chunk exceeds:
  - #{@max_chunk_len} items
  - #{@max_chunk_bytes_count} total estimated bytes
  """
  @spec chunk_data(list()) :: [list()]
  def chunk_data(data) do
    data
    |> Enum.chunk_while(
      {[], 0},
      fn datum, {chunk, byte_count} ->
        estimated = ByteEstimator.estimate_datum_bytes(datum)  # UPDATED

        cond do
          length(chunk) >= @max_chunk_len ->
            {:cont, chunk, {[datum], estimated}}

          byte_count + estimated > @max_chunk_bytes_count ->  # RENAMED
            {:cont, chunk, {[datum], estimated}}

          true ->
            {:cont, {chunk ++ [datum], byte_count + estimated}}
        end
      end,
      fn
        {[], 0} -> {:cont, []}
        {chunk, _count} -> {:cont, chunk, {[], 0}}
      end
    )
  end

  # REMOVE: estimate_number_count/1 and estimate_number_count_in_chunk/1
  # Now delegated to Tinkex.ByteEstimator
end
```

### 3. TrainingClient integration

`TrainingClient` already delegates chunking to `DataProcessor`, so no direct changes are needed inside `training_client.ex` beyond deleting any dead count-based estimators if they linger. The only required work is to ensure all chunking and estimation paths call into `ByteEstimator`.

## Test Cases

```elixir
# test/tinkex/byte_estimator_test.exs

defmodule Tinkex.ByteEstimatorTest do
  use ExUnit.Case, async: true

  alias Tinkex.ByteEstimator
  alias Tinkex.Types.{Datum, EncodedTextChunk, ImageAssetPointerChunk, ImageChunk, ModelInput, TensorData}

  describe "estimate_chunk_bytes/1" do
    test "ImageChunk returns raw byte size" do
      chunk = %ImageChunk{data: <<0, 1, 2, 3, 4>>}
      assert ByteEstimator.estimate_chunk_bytes(chunk) == 5
    end

    test "ImageAssetPointerChunk returns location string byte size" do
      chunk = %ImageAssetPointerChunk{location: "tinker://path/to/asset"}
      assert ByteEstimator.estimate_chunk_bytes(chunk) == byte_size("tinker://path/to/asset")
    end

    test "EncodedTextChunk returns token_count * 10" do
      chunk = %EncodedTextChunk{data: [1, 2, 3, 4, 5]}
      assert ByteEstimator.estimate_chunk_bytes(chunk) == 50
    end

    test "unknown chunk returns 0" do
      assert ByteEstimator.estimate_chunk_bytes(%{unknown: true}) == 0
    end
  end

  describe "estimate_model_input_bytes/1" do
    test "sums all chunk estimates" do
      input = %ModelInput{
        chunks: [
          %EncodedTextChunk{data: [1, 2, 3]},     # 30 bytes
          %ImageChunk{data: <<0::64>>}            # 8 bytes
        ]
      }
      assert ByteEstimator.estimate_model_input_bytes(input) == 38
    end

    test "returns 0 for empty chunks" do
      input = %ModelInput{chunks: []}
      assert ByteEstimator.estimate_model_input_bytes(input) == 0
    end
  end

  describe "estimate_loss_fn_inputs_bytes/1" do
    test "TensorData returns element_count * 10" do
      inputs = %{"target_tokens" => %TensorData{data: [1, 2, 3, 4, 5], dtype: :int32}}
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(inputs) == 50
    end

    test "handles multiple inputs" do
      inputs = %{
        "target_tokens" => %TensorData{data: [1, 2, 3], dtype: :int32},
        "weights" => %TensorData{data: [0.1, 0.2, 0.3, 0.4], dtype: :float32}
      }
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(inputs) == 70  # 30 + 40
    end

    test "handles Nx.Tensor" do
      tensor = Nx.tensor([1, 2, 3, 4])
      inputs = %{"target_tokens" => tensor}
      assert ByteEstimator.estimate_loss_fn_inputs_bytes(inputs) == 40
    end
  end

  describe "estimate_datum_bytes/1" do
    test "combines model_input and loss_fn_inputs" do
      datum = %Datum{
        model_input: %ModelInput{chunks: [%EncodedTextChunk{data: [1, 2, 3]}]},
        loss_fn_inputs: %{"target_tokens" => %TensorData{data: [1, 2], dtype: :int32}}
      }
      assert ByteEstimator.estimate_datum_bytes(datum) == 50  # 30 + 20
    end
  end

  describe "estimate_data_bytes/1" do
    test "sums all datum estimates" do
      data = [
        %Datum{
          model_input: %ModelInput{chunks: [%EncodedTextChunk{data: [1, 2]}]},
          loss_fn_inputs: %{}
        },
        %Datum{
          model_input: %ModelInput{chunks: [%EncodedTextChunk{data: [1, 2, 3]}]},
          loss_fn_inputs: %{}
        }
      ]
      assert ByteEstimator.estimate_data_bytes(data) == 50  # 20 + 30
    end
  end
end
```

## Integration with Sampling Dispatch

The `ByteEstimator.estimate_model_input_bytes/1` function will be used by `SamplingClient` for dispatch throttling (see spec 05).

## Files Affected

| File | Change |
|------|--------|
| `lib/tinkex/byte_estimator.ex` | NEW - Shared estimator module |
| `lib/tinkex/training_client/data_processor.ex` | Use ByteEstimator, update constants |
| `lib/tinkex/sampling_client.ex` | Call ByteEstimator for prompt sizing (Spec 05 ties in) |
| `test/tinkex/byte_estimator_test.exs` | NEW - Unit tests |

## Implementation Priority

**High** - Foundation for training chunking and sampling throttling changes.
