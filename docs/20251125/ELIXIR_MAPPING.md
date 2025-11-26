# Python to Elixir Mapping Guide

This document provides detailed mappings for porting the Python Tinker SDK changes to TinKex.

## Table of Contents

1. [Type System Mappings](#type-system-mappings)
2. [Module Structure Mappings](#module-structure-mappings)
3. [API Method Mappings](#api-method-mappings)
4. [Documentation Mappings](#documentation-mappings)
5. [Implementation Templates](#implementation-templates)

---

## Type System Mappings

### New Type: WeightsInfoResponse

#### Python Definition
```python
class WeightsInfoResponse(BaseModel):
    """Minimal information for loading public checkpoints."""
    base_model: str
    is_lora: bool
    lora_rank: int | None = None
```

#### Elixir Implementation
```elixir
# lib/tinkex/types/weights_info_response.ex
defmodule Tinkex.Types.WeightsInfoResponse do
  @moduledoc """
  Minimal information for loading public checkpoints.

  Mirrors Python `tinker.types.WeightsInfoResponse`.

  ## Fields

  - `base_model` - The base model name (e.g., "Qwen/Qwen2.5-7B")
  - `is_lora` - Whether this checkpoint uses LoRA
  - `lora_rank` - The LoRA rank, if applicable (nil for non-LoRA checkpoints)

  ## Wire Format

  ```json
  {
    "base_model": "Qwen/Qwen2.5-7B",
    "is_lora": true,
    "lora_rank": 32
  }
  ```
  """

  @enforce_keys [:base_model, :is_lora]
  defstruct [:base_model, :is_lora, :lora_rank]

  @type t :: %__MODULE__{
          base_model: String.t(),
          is_lora: boolean(),
          lora_rank: non_neg_integer() | nil
        }

  @doc """
  Create a WeightsInfoResponse from a JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"base_model" => base_model, "is_lora" => is_lora} = json) do
    %__MODULE__{
      base_model: base_model,
      is_lora: is_lora,
      lora_rank: json["lora_rank"]
    }
  end

  def from_json(%{base_model: base_model, is_lora: is_lora} = json) do
    %__MODULE__{
      base_model: base_model,
      is_lora: is_lora,
      lora_rank: json[:lora_rank]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.WeightsInfoResponse do
  def encode(resp, opts) do
    map = %{
      base_model: resp.base_model,
      is_lora: resp.is_lora
    }

    map =
      if resp.lora_rank do
        Map.put(map, :lora_rank, resp.lora_rank)
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
```

### New Type: GetSamplerResponse

#### Python Definition
```python
class GetSamplerResponse(BaseModel):
    sampler_id: str      # The sampler ID (sampling_session_id)
    base_model: str      # The base model name
    model_path: str | None = None  # Optional model path
```

#### Elixir Implementation
```elixir
# lib/tinkex/types/get_sampler_response.ex
defmodule Tinkex.Types.GetSamplerResponse do
  @moduledoc """
  Response from the get_sampler API call.

  Mirrors Python `tinker.types.GetSamplerResponse`.

  ## Fields

  - `sampler_id` - The sampler ID (sampling_session_id)
  - `base_model` - The base model name
  - `model_path` - Optional tinker:// path to custom weights

  ## Wire Format

  ```json
  {
    "sampler_id": "session-id:sample:0",
    "base_model": "Qwen/Qwen2.5-7B",
    "model_path": "tinker://run-id/weights/checkpoint-001"
  }
  ```
  """

  @enforce_keys [:sampler_id, :base_model]
  defstruct [:sampler_id, :base_model, :model_path]

  @type t :: %__MODULE__{
          sampler_id: String.t(),
          base_model: String.t(),
          model_path: String.t() | nil
        }

  @doc """
  Create a GetSamplerResponse from a JSON map.
  """
  @spec from_json(map()) :: t()
  def from_json(%{"sampler_id" => sampler_id, "base_model" => base_model} = json) do
    %__MODULE__{
      sampler_id: sampler_id,
      base_model: base_model,
      model_path: json["model_path"]
    }
  end

  def from_json(%{sampler_id: sampler_id, base_model: base_model} = json) do
    %__MODULE__{
      sampler_id: sampler_id,
      base_model: base_model,
      model_path: json[:model_path]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.GetSamplerResponse do
  def encode(resp, opts) do
    map = %{
      sampler_id: resp.sampler_id,
      base_model: resp.base_model
    }

    map =
      if resp.model_path do
        Map.put(map, :model_path, resp.model_path)
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
```

### Type Update: LossFnType

#### Python (Updated)
```python
LossFnType: TypeAlias = Literal["cross_entropy", "importance_sampling", "ppo", "cispo", "dro"]
```

#### Elixir (Current)
```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo
```

#### Elixir (Updated)
```elixir
# lib/tinkex/types/loss_fn_type.ex
defmodule Tinkex.Types.LossFnType do
  @moduledoc """
  Loss function type.

  Mirrors Python `tinker.types.LossFnType`.

  ## Supported Loss Functions

  - `:cross_entropy` - Standard cross-entropy loss
  - `:importance_sampling` - Importance-weighted sampling loss
  - `:ppo` - Proximal Policy Optimization loss
  - `:cispo` - CISPO (Constrained Importance Sampling Policy Optimization) loss
  - `:dro` - Distributionally Robust Optimization loss

  ## Wire Format

  String values: `"cross_entropy"` | `"importance_sampling"` | `"ppo"` | `"cispo"` | `"dro"`
  """

  @type t :: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro

  @doc """
  Parse wire format string to atom.

  ## Examples

      iex> LossFnType.parse("cross_entropy")
      :cross_entropy

      iex> LossFnType.parse("cispo")
      :cispo

      iex> LossFnType.parse("unknown")
      nil
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("cross_entropy"), do: :cross_entropy
  def parse("importance_sampling"), do: :importance_sampling
  def parse("ppo"), do: :ppo
  def parse("cispo"), do: :cispo
  def parse("dro"), do: :dro
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.

  ## Examples

      iex> LossFnType.to_string(:cross_entropy)
      "cross_entropy"

      iex> LossFnType.to_string(:dro)
      "dro"
  """
  @spec to_string(t()) :: String.t()
  def to_string(:cross_entropy), do: "cross_entropy"
  def to_string(:importance_sampling), do: "importance_sampling"
  def to_string(:ppo), do: "ppo"
  def to_string(:cispo), do: "cispo"
  def to_string(:dro), do: "dro"
end
```

### Type Update: ImageChunk

#### Python (Updated)
```python
class ImageChunk(StrictBase):
    data: bytes
    format: Literal["png", "jpeg"]
    height: int
    tokens: int
    width: int
    expected_tokens: int | None = None  # NEW FIELD
    type: Literal["image"] = "image"
```

#### Elixir (Current)
```elixir
defstruct [:data, :format, :height, :width, :tokens, type: "image"]
```

#### Elixir (Updated)
```elixir
# lib/tinkex/types/image_chunk.ex
defmodule Tinkex.Types.ImageChunk do
  @moduledoc """
  Image chunk with base64 encoded data.

  Mirrors Python `tinker.types.ImageChunk`.

  ## Fields

  - `data` - Base64-encoded image data
  - `format` - Image format (`:png` or `:jpeg`)
  - `height` - Image height in pixels
  - `width` - Image width in pixels
  - `tokens` - Number of tokens this image represents
  - `expected_tokens` - Advisory expected token count (optional)
  - `type` - Always "image"

  ## Expected Tokens

  The `expected_tokens` field is advisory. The Tinker backend computes the actual
  token count from the image. If `expected_tokens` is provided and doesn't match,
  the request will fail quickly rather than processing the full request.

  ## Wire Format

  ```json
  {
    "data": "base64-encoded-data",
    "format": "png",
    "height": 512,
    "width": 512,
    "tokens": 256,
    "expected_tokens": 256,
    "type": "image"
  }
  ```
  """

  @enforce_keys [:data, :format, :height, :width, :tokens]
  defstruct [:data, :format, :height, :width, :tokens, :expected_tokens, type: "image"]

  @type format :: :png | :jpeg
  @type t :: %__MODULE__{
          data: String.t(),
          format: format(),
          height: pos_integer(),
          width: pos_integer(),
          tokens: non_neg_integer(),
          expected_tokens: non_neg_integer() | nil,
          type: String.t()
        }

  @doc """
  Create a new ImageChunk from binary image data.

  Automatically encodes the binary data as base64.

  ## Parameters

  - `image_binary` - Raw image bytes
  - `format` - Image format (`:png` or `:jpeg`)
  - `height` - Image height in pixels
  - `width` - Image width in pixels
  - `tokens` - Number of tokens this image represents
  - `opts` - Optional keyword list with `:expected_tokens`

  ## Examples

      iex> ImageChunk.new(<<...>>, :png, 512, 512, 256)
      %ImageChunk{...}

      iex> ImageChunk.new(<<...>>, :png, 512, 512, 256, expected_tokens: 256)
      %ImageChunk{expected_tokens: 256, ...}
  """
  @spec new(binary(), format(), pos_integer(), pos_integer(), non_neg_integer(), keyword()) :: t()
  def new(image_binary, format, height, width, tokens, opts \\ []) do
    %__MODULE__{
      data: Base.encode64(image_binary),
      format: format,
      height: height,
      width: width,
      tokens: tokens,
      expected_tokens: Keyword.get(opts, :expected_tokens),
      type: "image"
    }
  end

  @doc """
  Get the length (number of tokens) consumed by this image.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{tokens: tokens}), do: tokens
end

defimpl Jason.Encoder, for: Tinkex.Types.ImageChunk do
  def encode(chunk, opts) do
    format_str = Atom.to_string(chunk.format)

    base_map = %{
      data: chunk.data,
      format: format_str,
      height: chunk.height,
      width: chunk.width,
      tokens: chunk.tokens,
      type: chunk.type
    }

    map =
      if chunk.expected_tokens do
        Map.put(base_map, :expected_tokens, chunk.expected_tokens)
      else
        base_map
      end

    Jason.Encode.map(map, opts)
  end
end
```

### Type Update: LoadWeightsRequest

#### Python (Updated)
```python
class LoadWeightsRequest(StrictBase):
    path: str  # A tinker URI for model weights
    load_optimizer_state: bool = False  # NEW FIELD
```

#### Elixir (Updated)
```elixir
# lib/tinkex/types/load_weights_request.ex
defmodule Tinkex.Types.LoadWeightsRequest do
  @moduledoc """
  Request to load model weights from storage.

  Mirrors Python `tinker.types.LoadWeightsRequest`.

  ## Fields

  - `path` - Tinker URI for model weights (e.g., "tinker://run-id/weights/checkpoint-001")
  - `load_optimizer_state` - Whether to also load optimizer state (default: false)

  ## Wire Format

  ```json
  {
    "path": "tinker://run-id/weights/checkpoint-001",
    "load_optimizer_state": true
  }
  ```
  """

  @enforce_keys [:path]
  defstruct [:path, load_optimizer_state: false]

  @type t :: %__MODULE__{
          path: String.t(),
          load_optimizer_state: boolean()
        }

  @doc """
  Create a LoadWeightsRequest.

  ## Parameters

  - `path` - Tinker URI for model weights
  - `opts` - Optional keyword list with `:load_optimizer_state`

  ## Examples

      iex> LoadWeightsRequest.new("tinker://run-id/weights/001")
      %LoadWeightsRequest{path: "tinker://run-id/weights/001", load_optimizer_state: false}

      iex> LoadWeightsRequest.new("tinker://run-id/weights/001", load_optimizer_state: true)
      %LoadWeightsRequest{path: "tinker://run-id/weights/001", load_optimizer_state: true}
  """
  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) do
    %__MODULE__{
      path: path,
      load_optimizer_state: Keyword.get(opts, :load_optimizer_state, false)
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.LoadWeightsRequest do
  def encode(req, opts) do
    Jason.Encode.map(
      %{
        path: req.path,
        load_optimizer_state: req.load_optimizer_state
      },
      opts
    )
  end
end
```

---

## Module Structure Mappings

| Python Module | Elixir Module |
|--------------|---------------|
| `tinker.lib.public_interfaces.service_client` | `Tinkex.API.Service` |
| `tinker.lib.public_interfaces.training_client` | `Tinkex.API.Training` |
| `tinker.lib.public_interfaces.sampling_client` | `Tinkex.API.Sampling` |
| `tinker.lib.public_interfaces.rest_client` | `Tinkex.API.Rest` |
| `tinker.lib.public_interfaces.api_future` | `Tinkex.Future` |
| `tinker.types.*` | `Tinkex.Types.*` |
| `tinker._exceptions` | `Tinkex.Error` |

---

## API Method Mappings

### RestClient.get_sampler

#### Python
```python
def get_sampler(self, sampler_id: str) -> APIFuture[types.GetSamplerResponse]:
    """Get sampler information."""
```

#### Elixir
```elixir
# In lib/tinkex/api/rest.ex

@doc """
Get sampler information.

## Parameters

- `client` - The RestClient
- `sampler_id` - The sampler ID (sampling_session_id) to get information for

## Returns

`{:ok, %GetSamplerResponse{}}` on success, `{:error, reason}` on failure.

## Examples

    iex> {:ok, resp} = Rest.get_sampler(client, "session-id:sample:0")
    iex> resp.base_model
    "Qwen/Qwen2.5-7B"
"""
@spec get_sampler(client(), String.t()) :: {:ok, GetSamplerResponse.t()} | {:error, term()}
def get_sampler(client, sampler_id) do
  case API.get(client, "/samplers/#{sampler_id}") do
    {:ok, json} -> {:ok, GetSamplerResponse.from_json(json)}
    {:error, _} = error -> error
  end
end
```

### RestClient.get_weights_info_by_tinker_path

#### Python
```python
def get_weights_info_by_tinker_path(
        self, tinker_path: str) -> APIFuture[types.WeightsInfoResponse]:
    """Get checkpoint information from a tinker path."""
```

#### Elixir
```elixir
# In lib/tinkex/api/rest.ex

@doc """
Get checkpoint information from a tinker path.

## Parameters

- `client` - The RestClient
- `tinker_path` - The tinker path to the checkpoint (e.g., "tinker://run-id/weights/001")

## Returns

`{:ok, %WeightsInfoResponse{}}` on success, `{:error, reason}` on failure.

## Examples

    iex> {:ok, resp} = Rest.get_weights_info_by_tinker_path(client, "tinker://run-id/weights/001")
    iex> resp.base_model
    "Qwen/Qwen2.5-7B"
    iex> resp.is_lora
    true
"""
@spec get_weights_info_by_tinker_path(client(), String.t()) ::
        {:ok, WeightsInfoResponse.t()} | {:error, term()}
def get_weights_info_by_tinker_path(client, tinker_path) do
  encoded_path = URI.encode(tinker_path)
  case API.get(client, "/weights/info?path=#{encoded_path}") do
    {:ok, json} -> {:ok, WeightsInfoResponse.from_json(json)}
    {:error, _} = error -> error
  end
end
```

---

## Documentation Mappings

### Python Docstring Format (After Commits)
```python
def method(self, param: Type) -> ReturnType:
    """Short description.

    Longer description if needed.

    Args:
    - `param`: Description of param

    Returns:
    - `ReturnType` with description

    Raises:
        SomeException: When something goes wrong

    Example:
    ```python
    result = client.method("value")
    print(result)
    ```
    """
```

### Elixir @doc Format (Recommended)
```elixir
@doc """
Short description.

Longer description if needed.

## Parameters

- `param` - Description of param

## Returns

`{:ok, result}` on success, `{:error, reason}` on failure.

## Errors

- `{:error, :not_found}` - When resource doesn't exist
- `{:error, %APIError{}}` - When API returns an error

## Examples

    iex> {:ok, result} = Module.method(client, "value")
    iex> result.field
    "expected_value"
"""
```

### Key Differences

| Aspect | Python | Elixir |
|--------|--------|--------|
| Args/Params | `Args:\n- \`param\`: desc` | `## Parameters\n\n- \`param\` - desc` |
| Returns | `Returns:\n- \`Type\` desc` | `## Returns\n\n\`{:ok, result}\` on success...` |
| Raises | `Raises:\n    Exception: desc` | `## Errors\n\n- \`{:error, :reason}\` - desc` |
| Examples | ````python\ncode\n```` | `    iex> code` (4-space indent) |
| Backticks | Used for params/types | Used for params/types |

---

## Implementation Checklist

### Types
- [ ] Create `lib/tinkex/types/weights_info_response.ex`
- [ ] Create `lib/tinkex/types/get_sampler_response.ex`
- [ ] Update `lib/tinkex/types/loss_fn_type.ex` (add `:cispo`, `:dro`)
- [ ] Update `lib/tinkex/types/image_chunk.ex` (add `expected_tokens`)
- [ ] Update `lib/tinkex/types/load_weights_request.ex` (add `load_optimizer_state`)
- [ ] Export new types from main types module

### API Methods
- [ ] Implement `Tinkex.API.Rest.get_sampler/2`
- [ ] Implement `Tinkex.API.Rest.get_weights_info_by_tinker_path/2`

### Documentation
- [ ] Update @moduledoc for all public modules
- [ ] Update @doc for all public functions
- [ ] Follow Elixir documentation conventions
- [ ] Add examples to all @doc strings
- [ ] Verify ExDoc output

### Tests
- [ ] Write tests for `WeightsInfoResponse`
- [ ] Write tests for `GetSamplerResponse`
- [ ] Write tests for updated `LossFnType`
- [ ] Write tests for updated `ImageChunk`
- [ ] Write tests for `Rest.get_sampler/2`
- [ ] Write tests for `Rest.get_weights_info_by_tinker_path/2`
