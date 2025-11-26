# Type Changes Summary

This document provides a consolidated view of all type changes required to port the Python Tinker SDK commits to TinKex.

## Quick Reference Table

| Type | Change | Priority | Status |
|------|--------|----------|--------|
| `WeightsInfoResponse` | NEW | P0 | Pending |
| `GetSamplerResponse` | NEW | P0 | Pending |
| `LossFnType` | UPDATE (add `:cispo`, `:dro`) | P0 | Pending |
| `ImageChunk` | UPDATE (add `expected_tokens`) | P0 | Pending |
| `LoadWeightsRequest` | UPDATE (add `load_optimizer_state`) | P1 | Pending |

---

## NEW: WeightsInfoResponse

### File Location
`lib/tinkex/types/weights_info_response.ex`

### Python Source
```python
class WeightsInfoResponse(BaseModel):
    """Minimal information for loading public checkpoints."""
    base_model: str
    is_lora: bool
    lora_rank: int | None = None
```

### Elixir Implementation

```elixir
defmodule Tinkex.Types.WeightsInfoResponse do
  @moduledoc """
  Minimal information for loading public checkpoints.

  Mirrors Python `tinker.types.WeightsInfoResponse`.

  ## Fields

  - `base_model` - The base model name (e.g., "Qwen/Qwen2.5-7B")
  - `is_lora` - Whether this checkpoint uses LoRA
  - `lora_rank` - The LoRA rank, if applicable (nil for non-LoRA)

  ## Wire Format

  ```json
  {"base_model": "Qwen/Qwen2.5-7B", "is_lora": true, "lora_rank": 32}
  ```
  """

  @enforce_keys [:base_model, :is_lora]
  defstruct [:base_model, :is_lora, :lora_rank]

  @type t :: %__MODULE__{
          base_model: String.t(),
          is_lora: boolean(),
          lora_rank: non_neg_integer() | nil
        }

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
    map = %{base_model: resp.base_model, is_lora: resp.is_lora}
    map = if resp.lora_rank, do: Map.put(map, :lora_rank, resp.lora_rank), else: map
    Jason.Encode.map(map, opts)
  end
end
```

### Tests Required

```elixir
defmodule Tinkex.Types.WeightsInfoResponseTest do
  use ExUnit.Case, async: true
  alias Tinkex.Types.WeightsInfoResponse

  describe "from_json/1" do
    test "parses complete response with lora_rank" do
      json = %{"base_model" => "Qwen/Qwen2.5-7B", "is_lora" => true, "lora_rank" => 32}

      assert %WeightsInfoResponse{
        base_model: "Qwen/Qwen2.5-7B",
        is_lora: true,
        lora_rank: 32
      } = WeightsInfoResponse.from_json(json)
    end

    test "parses response without lora_rank" do
      json = %{"base_model" => "Qwen/Qwen2.5-7B", "is_lora" => false}

      assert %WeightsInfoResponse{
        base_model: "Qwen/Qwen2.5-7B",
        is_lora: false,
        lora_rank: nil
      } = WeightsInfoResponse.from_json(json)
    end

    test "handles atom keys" do
      json = %{base_model: "test", is_lora: true, lora_rank: 16}
      assert %WeightsInfoResponse{} = WeightsInfoResponse.from_json(json)
    end
  end

  describe "Jason.Encoder" do
    test "includes lora_rank when present" do
      resp = %WeightsInfoResponse{base_model: "test", is_lora: true, lora_rank: 32}
      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)

      assert decoded["base_model"] == "test"
      assert decoded["is_lora"] == true
      assert decoded["lora_rank"] == 32
    end

    test "excludes lora_rank when nil" do
      resp = %WeightsInfoResponse{base_model: "test", is_lora: false, lora_rank: nil}
      encoded = Jason.encode!(resp)
      decoded = Jason.decode!(encoded)

      refute Map.has_key?(decoded, "lora_rank")
    end
  end
end
```

---

## NEW: GetSamplerResponse

### File Location
`lib/tinkex/types/get_sampler_response.ex`

### Python Source
```python
class GetSamplerResponse(BaseModel):
    sampler_id: str      # The sampler ID (sampling_session_id)
    base_model: str      # The base model name
    model_path: str | None = None  # Optional model path
```

### Elixir Implementation

```elixir
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
    "model_path": "tinker://run-id/weights/001"
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
    map = %{sampler_id: resp.sampler_id, base_model: resp.base_model}
    map = if resp.model_path, do: Map.put(map, :model_path, resp.model_path), else: map
    Jason.Encode.map(map, opts)
  end
end
```

---

## UPDATE: LossFnType

### File Location
`lib/tinkex/types/loss_fn_type.ex`

### Current State
```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo
```

### Required Changes

**Add to type:**
```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro
```

**Add parse clauses:**
```elixir
def parse("cispo"), do: :cispo
def parse("dro"), do: :dro
```

**Add to_string clauses:**
```elixir
def to_string(:cispo), do: "cispo"
def to_string(:dro), do: "dro"
```

### Full Updated Module

```elixir
defmodule Tinkex.Types.LossFnType do
  @moduledoc """
  Loss function type.

  Mirrors Python `tinker.types.LossFnType`.

  ## Supported Loss Functions

  - `:cross_entropy` - Standard cross-entropy loss
  - `:importance_sampling` - Importance-weighted sampling loss
  - `:ppo` - Proximal Policy Optimization loss
  - `:cispo` - Constrained Importance Sampling Policy Optimization loss
  - `:dro` - Distributionally Robust Optimization loss

  ## Wire Format

  String: `"cross_entropy"` | `"importance_sampling"` | `"ppo"` | `"cispo"` | `"dro"`
  """

  @type t :: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro

  @spec parse(String.t() | nil) :: t() | nil
  def parse("cross_entropy"), do: :cross_entropy
  def parse("importance_sampling"), do: :importance_sampling
  def parse("ppo"), do: :ppo
  def parse("cispo"), do: :cispo
  def parse("dro"), do: :dro
  def parse(_), do: nil

  @spec to_string(t()) :: String.t()
  def to_string(:cross_entropy), do: "cross_entropy"
  def to_string(:importance_sampling), do: "importance_sampling"
  def to_string(:ppo), do: "ppo"
  def to_string(:cispo), do: "cispo"
  def to_string(:dro), do: "dro"
end
```

---

## UPDATE: ImageChunk

### File Location
`lib/tinkex/types/image_chunk.ex`

### Current State
```elixir
defstruct [:data, :format, :height, :width, :tokens, type: "image"]
```

### Required Changes

**Add field to struct:**
```elixir
defstruct [:data, :format, :height, :width, :tokens, :expected_tokens, type: "image"]
```

**Update typespec:**
```elixir
@type t :: %__MODULE__{
  data: String.t(),
  format: format(),
  height: pos_integer(),
  width: pos_integer(),
  tokens: non_neg_integer(),
  expected_tokens: non_neg_integer() | nil,  # NEW
  type: String.t()
}
```

**Update new/5 to new/6:**
```elixir
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
```

**Update Jason.Encoder:**
```elixir
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

---

## UPDATE: LoadWeightsRequest

### File Location
`lib/tinkex/types/load_weights_request.ex`

### Current State
```elixir
@enforce_keys [:path]
defstruct [:path]
```

### Required Changes

**Update struct:**
```elixir
@enforce_keys [:path]
defstruct [:path, load_optimizer_state: false]
```

**Update typespec:**
```elixir
@type t :: %__MODULE__{
  path: String.t(),
  load_optimizer_state: boolean()
}
```

**Add/update constructor:**
```elixir
@spec new(String.t(), keyword()) :: t()
def new(path, opts \\ []) do
  %__MODULE__{
    path: path,
    load_optimizer_state: Keyword.get(opts, :load_optimizer_state, false)
  }
end
```

**Update Jason.Encoder:**
```elixir
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

## Validation Checklist

### New Types
- [ ] `WeightsInfoResponse` module created
- [ ] `WeightsInfoResponse` tests written and passing
- [ ] `GetSamplerResponse` module created
- [ ] `GetSamplerResponse` tests written and passing

### Updated Types
- [ ] `LossFnType` updated with `:cispo`, `:dro`
- [ ] `LossFnType` tests updated for new values
- [ ] `ImageChunk` updated with `expected_tokens`
- [ ] `ImageChunk` tests updated for new field
- [ ] `LoadWeightsRequest` updated with `load_optimizer_state`
- [ ] `LoadWeightsRequest` tests updated for new field

### Integration
- [ ] New types exported from `Tinkex.Types` (if using barrel module)
- [ ] All types compile without warnings
- [ ] `mix docs` generates correct documentation
- [ ] `mix dialyzer` passes (if configured)
