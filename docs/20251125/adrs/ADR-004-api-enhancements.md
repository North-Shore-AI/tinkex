# ADR-004: API Method Enhancements

**Status:** Proposed
**Date:** 2025-11-25
**Decision Makers:** TBD
**Technical Story:** Implementing new RestClient API methods from Python SDK

## Context

The Python Tinker SDK commits introduced new API methods in `RestClient`:
1. `get_sampler(sampler_id)` - Get sampler information
2. `get_weights_info_by_tinker_path(tinker_path)` - Get checkpoint information

These methods enable new workflows:
- Inspecting sampler configuration before using it
- Validating checkpoint compatibility before loading

## Decision Drivers

1. **API Parity** - TinKex should support same operations as Python SDK
2. **Workflow Completeness** - Users need these methods for production workflows
3. **Type Safety** - New types (`GetSamplerResponse`, `WeightsInfoResponse`) support these
4. **Consistency** - Follow existing TinKex API patterns

## New API Methods

### 1. get_sampler/2

**Python Signature:**
```python
def get_sampler(self, sampler_id: str) -> APIFuture[types.GetSamplerResponse]:
    """Get sampler information."""
```

**Use Case:**
- Inspect a sampler's configuration
- Verify the base model before sampling
- Check if custom weights are loaded

**TinKex Implementation:**

```elixir
# In lib/tinkex/api/rest.ex

@doc """
Get sampler information.

Retrieves details about a sampler, including the base model and any
custom weights that are loaded.

## Parameters

- `client` - The REST client
- `sampler_id` - The sampler ID (sampling_session_id) to query

## Returns

- `{:ok, %GetSamplerResponse{}}` - On success
- `{:error, :not_found}` - If sampler doesn't exist
- `{:error, %APIError{}}` - On API error

## Examples

    iex> {:ok, resp} = Rest.get_sampler(client, "session-id:sample:0")
    iex> resp.base_model
    "Qwen/Qwen2.5-7B"
    iex> resp.model_path
    "tinker://run-id/weights/checkpoint-001"

    # Sampler with base model only
    iex> {:ok, resp} = Rest.get_sampler(client, "session-id:sample:0")
    iex> resp.model_path
    nil

## Notes

The `sampler_id` is returned when creating a sampling client via
`Service.create_sampling_client/2` or `Training.save_weights_and_get_sampling_client/2`.
"""
@spec get_sampler(client(), String.t()) ::
        {:ok, GetSamplerResponse.t()} | {:error, term()}
def get_sampler(client, sampler_id) do
  path = "/samplers/#{URI.encode(sampler_id)}"

  case API.get(client, path) do
    {:ok, json} ->
      {:ok, GetSamplerResponse.from_json(json)}
    {:error, %{status: 404}} ->
      {:error, :not_found}
    {:error, _} = error ->
      error
  end
end
```

### 2. get_weights_info_by_tinker_path/2

**Python Signature:**
```python
def get_weights_info_by_tinker_path(
        self, tinker_path: str) -> APIFuture[types.WeightsInfoResponse]:
    """Get checkpoint information from a tinker path."""
```

**Use Case:**
- Validate checkpoint before loading
- Check if checkpoint is LoRA compatible
- Verify LoRA rank matches expectations

**TinKex Implementation:**

```elixir
# In lib/tinkex/api/rest.ex

@doc """
Get checkpoint information from a tinker path.

Retrieves metadata about a checkpoint, including the base model,
whether it uses LoRA, and the LoRA rank.

## Parameters

- `client` - The REST client
- `tinker_path` - The tinker path to the checkpoint
  (e.g., `"tinker://run-id/weights/checkpoint-001"`)

## Returns

- `{:ok, %WeightsInfoResponse{}}` - On success
- `{:error, :not_found}` - If checkpoint doesn't exist
- `{:error, :invalid_path}` - If tinker_path format is invalid
- `{:error, %APIError{}}` - On API error

## Examples

    iex> path = "tinker://run-id/weights/checkpoint-001"
    iex> {:ok, resp} = Rest.get_weights_info_by_tinker_path(client, path)
    iex> resp.base_model
    "Qwen/Qwen2.5-7B"
    iex> resp.is_lora
    true
    iex> resp.lora_rank
    32

    # Non-LoRA checkpoint
    iex> {:ok, resp} = Rest.get_weights_info_by_tinker_path(client, path)
    iex> resp.is_lora
    false
    iex> resp.lora_rank
    nil

## Use Cases

### Validating Checkpoint Compatibility

    def validate_checkpoint(client, path, expected_rank) do
      case Rest.get_weights_info_by_tinker_path(client, path) do
        {:ok, %{is_lora: true, lora_rank: ^expected_rank}} ->
          :ok
        {:ok, %{is_lora: true, lora_rank: actual}} ->
          {:error, {:rank_mismatch, expected: expected_rank, actual: actual}}
        {:ok, %{is_lora: false}} ->
          {:error, :not_lora}
        {:error, _} = error ->
          error
      end
    end
"""
@spec get_weights_info_by_tinker_path(client(), String.t()) ::
        {:ok, WeightsInfoResponse.t()} | {:error, term()}
def get_weights_info_by_tinker_path(client, tinker_path) do
  encoded_path = URI.encode(tinker_path, &URI.char_unreserved?/1)
  path = "/weights/info?path=#{encoded_path}"

  case API.get(client, path) do
    {:ok, json} ->
      {:ok, WeightsInfoResponse.from_json(json)}
    {:error, %{status: 404}} ->
      {:error, :not_found}
    {:error, %{status: 400}} ->
      {:error, :invalid_path}
    {:error, _} = error ->
      error
  end
end
```

## Implementation Plan

### Phase 1: Dependencies (ADR-002)
1. Implement `WeightsInfoResponse` type
2. Implement `GetSamplerResponse` type

### Phase 2: API Methods
1. Add `get_sampler/2` to `Tinkex.API.Rest`
2. Add `get_weights_info_by_tinker_path/2` to `Tinkex.API.Rest`

### Phase 3: Testing
1. Unit tests with mocked responses
2. Integration tests (if test server available)
3. Documentation verification

## Test Strategy

### get_sampler/2 Tests

```elixir
describe "get_sampler/2" do
  test "returns sampler info on success" do
    Bypass.expect_once(bypass, "GET", "/samplers/session-id:sample:0", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({
        "sampler_id": "session-id:sample:0",
        "base_model": "Qwen/Qwen2.5-7B",
        "model_path": null
      }))
    end)

    assert {:ok, %GetSamplerResponse{
      sampler_id: "session-id:sample:0",
      base_model: "Qwen/Qwen2.5-7B",
      model_path: nil
    }} = Rest.get_sampler(client, "session-id:sample:0")
  end

  test "returns :not_found for missing sampler" do
    Bypass.expect_once(bypass, "GET", "/samplers/missing", fn conn ->
      Plug.Conn.resp(conn, 404, ~s({"error": "not found"}))
    end)

    assert {:error, :not_found} = Rest.get_sampler(client, "missing")
  end
end
```

### get_weights_info_by_tinker_path/2 Tests

```elixir
describe "get_weights_info_by_tinker_path/2" do
  test "returns weights info for LoRA checkpoint" do
    Bypass.expect_once(bypass, "GET", "/weights/info", fn conn ->
      assert conn.query_string =~ "path="
      Plug.Conn.resp(conn, 200, ~s({
        "base_model": "Qwen/Qwen2.5-7B",
        "is_lora": true,
        "lora_rank": 32
      }))
    end)

    path = "tinker://run-id/weights/001"
    assert {:ok, %WeightsInfoResponse{
      base_model: "Qwen/Qwen2.5-7B",
      is_lora: true,
      lora_rank: 32
    }} = Rest.get_weights_info_by_tinker_path(client, path)
  end

  test "returns weights info for non-LoRA checkpoint" do
    Bypass.expect_once(bypass, "GET", "/weights/info", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({
        "base_model": "Qwen/Qwen2.5-7B",
        "is_lora": false
      }))
    end)

    assert {:ok, %WeightsInfoResponse{
      is_lora: false,
      lora_rank: nil
    }} = Rest.get_weights_info_by_tinker_path(client, "tinker://...")
  end

  test "URL-encodes tinker path" do
    Bypass.expect_once(bypass, "GET", "/weights/info", fn conn ->
      # Verify path is properly encoded
      assert conn.query_string =~ "tinker%3A%2F%2F"
      Plug.Conn.resp(conn, 200, ~s({"base_model": "x", "is_lora": false}))
    end)

    Rest.get_weights_info_by_tinker_path(client, "tinker://run/weights")
  end
end
```

## Consequences

### Positive
- Full feature parity with Python SDK
- Enables checkpoint validation workflows
- Enables sampler inspection workflows
- Well-typed responses

### Negative
- Additional API surface to maintain
- Requires new types (covered in ADR-002)

### Neutral
- Follows existing TinKex patterns
- Standard REST API implementation

## Open Questions

1. **Endpoint Paths:** The exact endpoint paths (`/samplers/:id`, `/weights/info`) need verification against actual API. The Python SDK abstracts these internally.

2. **Error Handling:** Should we create specific error types or use atoms? Current decision uses atoms for common cases (`:not_found`, `:invalid_path`).

3. **Async Variants:** Should we add `get_sampler_async/2` etc? Python returns `APIFuture`. Current TinKex pattern uses sync calls.

## Links

- [ADR-002: Type Updates](./ADR-002-type-updates.md) - Required types
- [ELIXIR_MAPPING.md](../ELIXIR_MAPPING.md) - Full implementation templates
- [COMMIT_ANALYSIS.md](../COMMIT_ANALYSIS.md) - Source commit analysis
