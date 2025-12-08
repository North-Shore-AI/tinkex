# Training Chunking Changes Specification

## Summary

Update training data chunking from count-based limits (128 items, 500K numbers) to byte-based limits (1024 items, 5MB bytes) matching Python SDK v0.7.0.

## Python SDK Reference

```python
# tinker/src/tinker/lib/public_interfaces/training_client.py

MAX_CHUNK_LEN = 1024          # CHANGED from 128
MAX_CHUNK_BYTES_COUNT = 5000000  # NEW (was count-based 500,000)

def _estimate_bytes_count(self, datum: types.Datum) -> int:
    return (
        self.holder.estimate_bytes_count_in_model_input(datum.model_input) +
        sum(len(value.data) * 10 for _, value in datum.loss_fn_inputs.items())
    )

def _chunked_requests_generator(self, data: List[types.Datum]) -> Generator[...]:
    current_chunk: List[types.Datum] = []
    current_chunk_bytes_count = 0

    for datum in data:
        estimated_bytes_count = self._estimate_bytes_count(datum)

        if (
            len(current_chunk) > 0
            and current_chunk_bytes_count + estimated_bytes_count > MAX_CHUNK_BYTES_COUNT
        ) or (len(current_chunk) == MAX_CHUNK_LEN):
            yield current_chunk
            current_chunk = []
            current_chunk_bytes_count = 0

        current_chunk.append(datum)
        current_chunk_bytes_count += estimated_bytes_count

    if len(current_chunk) > 0:
        yield current_chunk
```

### Key Changes from Previous Python Version

| Aspect | Previous | v0.7.0 |
|--------|----------|--------|
| Max items per chunk | 128 | 1024 |
| Size limit | 500,000 numbers | 5,000,000 bytes |
| Estimation unit | Token/pixel count | Byte estimate |
| loss_fn_inputs handling | Element count | Element count × 10 |

## Current Elixir Implementation

### Constants

```elixir
# lib/tinkex/training_client/data_processor.ex
@max_chunk_len 128
@max_chunk_number_count 500_000
```

### Estimation Logic

```elixir
# Uses number count (tokens, pixels) not bytes
defp _estimate_number_count_in_chunk(%Tinkex.Types.EncodedTextChunk{} = chunk),
  do: Tinkex.Types.EncodedTextChunk.length(chunk)  # Returns token count

# loss_fn_inputs counted as raw element count
loss_count =
  loss_inputs
  |> Map.values()
  |> Enum.reduce(0, fn
    %{data: data}, acc when is_list(data) -> acc + length(data)
    _other, acc -> acc
  end)
```

### Chunking Algorithm

```elixir
def chunk_data(data) do
  data
  |> Enum.chunk_while(
    {[], 0},
    fn datum, {chunk, count} ->
      estimated = estimate_number_count(datum)

      cond do
        length(chunk) >= @max_chunk_len ->          # 128 items
          {:cont, chunk, {[datum], estimated}}

        count + estimated > @max_chunk_number_count ->  # 500K numbers
          {:cont, chunk, {[datum], estimated}}

        true ->
          {:cont, {chunk ++ [datum], count + estimated}}
      end
    end,
    fn
      {[], 0} -> {:cont, []}
      {chunk, _count} -> {:cont, chunk, {[], 0}}
    end
  )
end
```

## Required Changes

### 1. Update Constants

**File**: `lib/tinkex/training_client/data_processor.ex`

```elixir
# OLD
@max_chunk_len 128
@max_chunk_number_count 500_000

# NEW
@max_chunk_len 1024
@max_chunk_bytes_count 5_000_000
```

### 2. Update Chunking Logic

**File**: `lib/tinkex/training_client/data_processor.ex`

```elixir
alias Tinkex.ByteEstimator

@doc """
Chunk data into manageable pieces based on size and byte limits.

Ensures no chunk exceeds:
- #{@max_chunk_len} items (1024)
- #{@max_chunk_bytes_count} total estimated bytes (5MB)
"""
@spec chunk_data(list()) :: [list()]
def chunk_data(data) do
  data
  |> Enum.chunk_while(
    {[], 0},
    fn datum, {chunk, byte_count} ->
      estimated = ByteEstimator.estimate_datum_bytes(datum)

      cond do
        length(chunk) >= @max_chunk_len ->
          {:cont, chunk, {[datum], estimated}}

        byte_count + estimated > @max_chunk_bytes_count ->
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
```

### 3. Remove Deprecated Functions

Remove the count-based estimators from `lib/tinkex/training_client/data_processor.ex`:

```elixir
# REMOVE - replaced by ByteEstimator
defp estimate_number_count_in_chunk/1
@spec estimate_number_count(map()) :: non_neg_integer()
def estimate_number_count/1
```

### 4. Update Documentation

**File**: `lib/tinkex/training_client/data_processor.ex` moduledoc

Add a note that chunking now uses byte estimates (10 bytes per token/tensor element) and the new limits (1024 items, 5 MB).

## Behavioral Impact

### Before (128 items / 500K numbers)

```
Dataset: 1000 datums, average 1000 tokens each
- Items limit: ceil(1000 / 128) = 8 chunks
- Number limit: ceil(1,000,000 tokens / 500,000) = 2 chunks
- Result: 8 chunks (item limit is bottleneck)
```

### After (1024 items / 5MB bytes)

```
Dataset: 1000 datums, average 1000 tokens each
- Items limit: ceil(1000 / 1024) = 1 chunk
- Bytes: 1000 * 1000 * 10 = 10MB -> 2 chunks
- Result: 2 chunks (byte limit is bottleneck)

Dataset: 500 datums, average 500 tokens each
- Items limit: 1 chunk (500 < 1024)
- Bytes: 500 * 500 * 10 = 2.5MB -> 1 chunk
- Result: 1 chunk (fits in single request)
```

### Benefits

1. **Fewer API Calls**: 8× increase in items per chunk reduces overhead
2. **Consistent Sizing**: Byte-based limits are more predictable than number counts
3. **Image Handling**: Large images correctly capped by byte limit, not distorted by token heuristics

## Test Cases

```elixir
# test/tinkex/training_client/data_processor_test.exs

describe "chunk_data/1 with updated limits" do
  test "allows up to 1024 items per chunk" do
    # Create 1024 small datums (< 5KB each)
    data = for _ <- 1..1024, do: small_datum()
    chunks = DataProcessor.chunk_data(data)

    assert length(chunks) == 1
    assert length(hd(chunks)) == 1024
  end

  test "splits at 1024 items regardless of bytes" do
    # Create 1025 small datums
    data = for _ <- 1..1025, do: small_datum()
    chunks = DataProcessor.chunk_data(data)

    assert length(chunks) == 2
    assert length(hd(chunks)) == 1024
    assert length(Enum.at(chunks, 1)) == 1
  end

  test "splits at 5MB byte limit" do
    # Create datums that total > 5MB
    # Each datum with 10K tokens = 100KB estimated
    # 51 datums = 5.1MB -> should split
    data = for _ <- 1..51, do: datum_with_tokens(10_000)
    chunks = DataProcessor.chunk_data(data)

    assert length(chunks) == 2
  end

  test "respects byte limit before item limit" do
    # Create large datums that hit byte limit before item limit
    # 10 datums with 100K tokens each = 10MB -> multiple chunks
    data = for _ <- 1..10, do: datum_with_tokens(100_000)
    chunks = DataProcessor.chunk_data(data)

    # Each datum is ~1MB, so max 5 per chunk
    assert length(chunks) >= 2
  end

  test "handles mixed content (text + images)" do
    data = [
      datum_with_tokens(1000),           # ~10KB
      datum_with_image(2_000_000),       # ~2MB image
      datum_with_tokens(1000),           # ~10KB
      datum_with_image(2_000_000),       # ~2MB image
      datum_with_tokens(1000),           # ~10KB
    ]
    # Total: ~4MB, fits in one chunk
    chunks = DataProcessor.chunk_data(data)
    assert length(chunks) == 1

    # Add one more image to exceed 5MB
    data = data ++ [datum_with_image(2_000_000)]
    chunks = DataProcessor.chunk_data(data)
    assert length(chunks) == 2
  end
end

# Helper functions
defp small_datum do
  %Datum{
    model_input: %ModelInput{chunks: [%EncodedTextChunk{data: [1, 2, 3]}]},
    loss_fn_inputs: %{}
  }
end

defp datum_with_tokens(count) do
  %Datum{
    model_input: %ModelInput{chunks: [%EncodedTextChunk{data: Enum.to_list(1..count)}]},
    loss_fn_inputs: %{}
  }
end

defp datum_with_image(size) do
  %Datum{
    model_input: %ModelInput{chunks: [%ImageChunk{data: :crypto.strong_rand_bytes(size)}]},
    loss_fn_inputs: %{}
  }
end
```

## Migration Notes

### Breaking Changes

**None** - The changes relax limits (larger chunks allowed), so existing training code will continue to work. May result in fewer, larger API calls.

### Performance Considerations

1. **Memory**: Larger chunks may increase peak memory during serialization
2. **Latency**: Fewer requests may reduce overall latency due to reduced overhead
3. **Retries**: Failed chunks are larger, so retry cost is higher per failure

### Monitoring

Consider adding telemetry for:
- Chunk count per batch
- Chunk sizes (items and bytes)
- Requests per forward_backward call

## Files Affected

| File | Change |
|------|--------|
| `lib/tinkex/training_client/data_processor.ex` | Update constants, use ByteEstimator |
| `test/tinkex/training_client/data_processor_test.exs` | Update/add chunking tests |
| `test/tinkex/training_client_test.exs` | Update chunking integration tests |

## Dependencies

- **Spec 03 (ByteEstimator)**: Must be implemented first

## Implementation Priority

**High** - Direct API behavior change affecting all training operations.
