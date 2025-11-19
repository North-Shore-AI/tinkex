# Phase 1: Type System Implementation - Agent Prompt

> **Target:** Implement and test all core Tinkex types so that Elixir ↔ JSON matches the verified Python/Tinker wire format.
> **Timebox:** Week 1 - Days 4-7
> **Location:** `S:\tinkex` (pure Elixir library)

---

## 1. Project Orientation

You are implementing the **Tinkex SDK**, an Elixir port of the Python Tinker SDK for ML model training and sampling. This is a **pure Elixir library** - no Phoenix, no Ecto for core functionality.

### 1.1 First Steps - Get Acclimated

Before writing any code, familiarize yourself with the project:

1. **Explore project structure:**
   ```
   S:\tinkex\
   ├── lib/tinkex/           # Main source code
   ├── test/                  # Tests mirror lib structure
   ├── docs/20251119/         # Implementation documentation
   │   ├── port_research/     # Core research docs (00-07)
   │   └── 010*.md            # Phase implementation guides
   └── mix.exs                # Dependencies
   ```

2. **Check current state:**
   - Run `mix deps.get` to ensure dependencies are installed
   - Run `mix compile` to see current compilation state
   - Run `mix test` to see existing test status
   - Run `mix dialyzer` to check type status

---

## 2. Required Reading - Documentation

Read these documents **in order** to understand the type system requirements:

### 2.1 Core Research Documents

Read the complete port research documentation in `docs/20251119/port_research/`:

| File | Purpose | Key Sections to Focus On |
|------|---------|--------------------------|
| `00_overview.md` | Project summary and correction history | All "Key Corrections" sections to understand what was fixed |
| `01_type_system.md` | **PRIMARY REFERENCE** - All type definitions | Sections 1-5 (Core Types, Enums, Request/Response, JSON Encoding, Error Parsing) |
| `02_client_architecture.md` | Client design patterns | Skim for context on how types will be used |
| `03_async_model.md` | Future/async patterns | Section on Future types |
| `04_http_layer.md` | HTTP/retry logic | JSON encoding section, error handling |
| `05_error_handling.md` | Error categories and retry logic | RequestErrorCategory section, error type definitions |
| `06_telemetry.md` | Telemetry types | Skim for telemetry-related types |
| `07_porting_strategy.md` | Implementation plan | Phase breakdown, Pre-Implementation Checklist, Critical Type Verification section |

### 2.2 Phase Implementation Guides

Read these implementation-specific documents:

| File | Purpose |
|------|---------|
| `docs/20251119/0100_tinkex_sdk_impl_proc_claude.md` | Overall implementation process |
| `docs/20251119/0101_testing_process.md` | Testing methodology and fixtures |

---

## 3. Critical Wire Format Knowledge

Before implementing types, you MUST understand these verified wire format facts:

### 3.1 Confirmed Wire Formats

| Type | Wire Format | Evidence |
|------|-------------|----------|
| `StopReason` | `"length"` \| `"stop"` | `Literal["length", "stop"]` in Python |
| `RequestErrorCategory` | `"unknown"` \| `"server"` \| `"user"` (lowercase!) | StrEnum.auto() returns lowercase in Python 3.11+ |
| `LossFnType` | `"cross_entropy"` \| `"importance_sampling"` \| `"ppo"` | Literal values in Python |
| `TensorDtype` | `"int64"` \| `"float32"` (only 2 types!) | Backend limitation |
| `ImageChunk` fields | `data`, `format`, `height`, `width`, `tokens`, `type` | NOT `image_data` or `image_format` |
| `ImageAssetPointerChunk` | Uses `location` field | NOT `asset_id` |

### 3.2 JSON Encoding Rules

- **nil → null**: Optional fields serialize as `null`, NOT omitted
- **No global nil-stripping**: Match Python's behavior exactly
- **NotGiven sentinel**: Only used for client options, NOT request schemas
- **Discriminator fields**: Use `type` field with lowercase string values

---

## 4. Implementation Plan

### 4.1 Implementation Order

Implement types in this **strict order** to minimize dependency issues:

#### Group 1: Enums & Literals (implement first)
```
lib/tinkex/types/
├── stop_reason.ex
├── loss_fn_type.ex
├── request_error_category.ex
└── tensor_dtype.ex
```

#### Group 2: Core Data Structures
```
lib/tinkex/types/
├── encoded_text_chunk.ex
├── image_chunk.ex
├── image_asset_pointer_chunk.ex
├── model_input_chunk.ex      # type alias only
├── model_input.ex
├── tensor_data.ex
├── datum.ex
└── sampling_params.ex
```

#### Group 3: Request Types
```
lib/tinkex/types/
├── adam_params.ex
├── forward_backward_input.ex
├── forward_backward_request.ex
├── forward_request.ex
├── optim_step_request.ex
├── sample_request.ex
├── create_model_request.ex
├── create_sampling_session_request.ex
├── create_session_request.ex
├── save_weights_request.ex
├── save_weights_for_sampler_request.ex
└── load_weights_request.ex
```

#### Group 4: Response Types
```
lib/tinkex/types/
├── forward_backward_output.ex
├── optim_step_response.ex
├── sampled_sequence.ex
├── sample_response.ex
├── create_model_response.ex
├── create_sampling_session_response.ex
├── create_session_response.ex
├── future_pending_response.ex
├── future_completed_response.ex
├── future_failed_response.ex
├── try_again_response.ex
├── future_retrieve_response.ex   # type alias for union
├── checkpoints_list_response.ex
└── training_runs_response.ex
```

#### Group 5: Error Type
```
lib/tinkex/types/
└── error.ex → Tinkex.Error
```

### 4.2 Module Template

Use this pattern for ALL types:

```elixir
defmodule Tinkex.Types.ExampleType do
  @moduledoc """
  ExampleType

  Mirrors Python tinker.types.example_type.ExampleType.
  Wire format verified via Phase 0 fixtures.
  """

  @derive {Jason.Encoder,
           only: [
             :field1,
             :field2,
             :type
           ]}
  defstruct [
    :field1,
    field2: "default",
    type: "example"   # literal discriminator
  ]

  @type t :: %__MODULE__{
          field1: String.t() | nil,
          field2: String.t(),
          type: String.t()
        }

  # Constructor with validation (where needed)
  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts \\ []) do
    # validation logic
  end
end
```

---

## 5. Test-Driven Development Process

For EACH type, follow this workflow:

### 5.1 Per-Type Workflow

1. **Create test file first** in `test/tinkex/types/{type_name}_test.exs`
2. **Write failing tests** for:
   - Basic construction
   - JSON encoding (matches wire format)
   - Validation logic (where applicable)
   - Edge cases
3. **Implement the type** to make tests pass
4. **Run Dialyzer** to verify typespecs
5. **Move to next type**

### 5.2 Test File Structure

```elixir
defmodule Tinkex.Types.StopReasonTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.StopReason

  describe "parse/1" do
    test "parses lowercase wire values" do
      assert StopReason.parse("length") == :length
      assert StopReason.parse("stop") == :stop
    end

    test "returns nil for unknown values" do
      assert StopReason.parse("unknown_value") == nil
      assert StopReason.parse(nil) == nil
    end
  end

  describe "to_string/1" do
    test "converts atoms to wire format strings" do
      assert StopReason.to_string(:length) == "length"
      assert StopReason.to_string(:stop) == "stop"
    end
  end
end
```

### 5.3 JSON Encoding Tests

Test that JSON encoding matches Python wire format:

```elixir
defmodule Tinkex.Types.SampleRequestTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{SampleRequest, ModelInput, SamplingParams}

  describe "JSON encoding" do
    test "encodes prompt_logprobs nil as null" do
      req = %SampleRequest{
        num_samples: 1,
        prompt: ModelInput.from_ints([1, 2, 3]),
        sampling_params: %SamplingParams{max_tokens: 100},
        prompt_logprobs: nil,
        type: "sample"
      }

      json = Jason.encode!(req)
      decoded = Jason.decode!(json)

      # nil should become null in JSON, not be omitted
      assert Map.has_key?(decoded, "prompt_logprobs")
      assert decoded["prompt_logprobs"] == nil
    end

    test "encodes all required fields" do
      req = %SampleRequest{
        num_samples: 2,
        prompt: ModelInput.from_ints([1, 2]),
        sampling_params: %SamplingParams{},
        type: "sample"
      }

      json = Jason.encode!(req)
      decoded = Jason.decode!(json)

      assert decoded["num_samples"] == 2
      assert decoded["type"] == "sample"
      assert is_map(decoded["prompt"])
      assert is_map(decoded["sampling_params"])
    end
  end
end
```

### 5.4 TensorData Roundtrip Tests

```elixir
defmodule Tinkex.Types.TensorDataTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.TensorData

  describe "from_nx/1" do
    test "converts float64 to float32" do
      tensor = Nx.tensor([1.0, 2.0, 3.0], type: {:f, 64})
      td = TensorData.from_nx(tensor)

      assert td.dtype == :float32
      assert td.data == [1.0, 2.0, 3.0]
      assert td.shape == [3]
    end

    test "converts int32 to int64" do
      tensor = Nx.tensor([1, 2, 3], type: {:s, 32})
      td = TensorData.from_nx(tensor)

      assert td.dtype == :int64
    end

    test "preserves shape for multi-dimensional tensors" do
      tensor = Nx.tensor([[1, 2], [3, 4]], type: {:s, 64})
      td = TensorData.from_nx(tensor)

      assert td.shape == [2, 2]
      assert td.data == [1, 2, 3, 4]
    end

    test "raises for unsupported dtypes" do
      tensor = Nx.tensor([1, 2], type: {:bf, 16})

      assert_raise ArgumentError, ~r/Unsupported tensor dtype/, fn ->
        TensorData.from_nx(tensor)
      end
    end
  end

  describe "to_nx/1" do
    test "roundtrips correctly" do
      original = Nx.tensor([1.5, 2.5, 3.5], type: {:f, 32})
      td = TensorData.from_nx(original)
      result = TensorData.to_nx(td)

      assert Nx.to_flat_list(result) == Nx.to_flat_list(original)
    end
  end

  describe "JSON encoding" do
    test "encodes to correct wire format" do
      td = %TensorData{
        data: [1.0, 2.0, 3.0],
        dtype: :float32,
        shape: [3]
      }

      json = Jason.encode!(td)
      decoded = Jason.decode!(json)

      assert decoded["dtype"] == "float32"
      assert decoded["data"] == [1.0, 2.0, 3.0]
      assert decoded["shape"] == [3]
    end
  end
end
```

---

## 6. Detailed Type Specifications

### 6.1 Enums

#### StopReason
```elixir
@type t :: :length | :stop

# Functions:
# - parse/1: String.t() | nil -> t() | nil
# - to_string/1: t() -> String.t()
```

#### LossFnType
```elixir
@type t :: :cross_entropy | :importance_sampling | :ppo

# Same parse/to_string pattern
```

#### RequestErrorCategory
```elixir
@type t :: :unknown | :server | :user

# Functions:
# - parse/1: String.t() | nil -> t()  # case-insensitive, defaults to :unknown
# - retryable?/1: t() -> boolean()    # :user -> false, others -> true
```

#### TensorDtype
```elixir
@type t :: :int64 | :float32

# Only 2 types supported!
```

### 6.2 Core Data Structures

#### EncodedTextChunk
```elixir
defstruct [:tokens, type: "encoded_text"]

@type t :: %__MODULE__{
  tokens: [integer()],
  type: String.t()
}

# Functions:
# - length/1: t() -> non_neg_integer()
```

#### ImageChunk
```elixir
defstruct [:data, :format, :height, :width, :tokens, type: "image"]

@type format :: :png | :jpeg
@type t :: %__MODULE__{
  data: String.t(),        # base64 encoded
  format: format(),
  height: pos_integer(),
  width: pos_integer(),
  tokens: non_neg_integer(),
  type: String.t()
}

# Functions:
# - new/5: (binary, format, height, width, tokens) -> t()
# - length/1: t() -> non_neg_integer()
```

#### ImageAssetPointerChunk
```elixir
defstruct [:location, :format, :height, :width, :tokens, type: "image_asset_pointer"]

# Same structure as ImageChunk but with location instead of data
```

#### ModelInput
```elixir
defstruct [:chunks]

@type t :: %__MODULE__{
  chunks: [ModelInputChunk.t()]
}

# Functions:
# - from_ints/1: [integer()] -> t()
# - to_ints/1: t() -> [integer()]
# - length/1: t() -> non_neg_integer()
```

#### TensorData
```elixir
defstruct [:data, :dtype, :shape]

@type dtype :: :int64 | :float32
@type t :: %__MODULE__{
  data: [number()],
  dtype: dtype(),
  shape: [non_neg_integer()] | nil
}

# Functions:
# - from_nx/1: Nx.Tensor.t() -> t()    # with aggressive type casting
# - to_nx/1: t() -> Nx.Tensor.t()
```

#### Datum
```elixir
defstruct [:model_input, :loss_fn_inputs]

@type t :: %__MODULE__{
  model_input: ModelInput.t(),
  loss_fn_inputs: %{String.t() => TensorData.t()}
}

# Functions:
# - new/1: map() -> t()   # auto-converts Nx tensors and lists
```

#### SamplingParams
```elixir
defstruct [
  :max_tokens,
  :seed,
  :stop,
  temperature: 1.0,
  top_k: -1,
  top_p: 1.0
]

@type t :: %__MODULE__{
  max_tokens: non_neg_integer() | nil,
  seed: integer() | nil,
  stop: String.t() | [String.t()] | [integer()] | nil,
  temperature: float(),
  top_k: integer(),
  top_p: float()
}
```

### 6.3 Request Types

#### AdamParams
```elixir
defstruct [
  learning_rate: 0.0001,
  beta1: 0.9,
  beta2: 0.95,
  eps: 1.0e-12
]

# Functions:
# - new/1: keyword() -> {:ok, t()} | {:error, String.t()}
# Include validation for ranges
```

#### SampleRequest
```elixir
defstruct [
  num_samples: 1,
  :prompt,
  :sampling_params,
  :base_model,
  :model_path,
  :sampling_session_id,
  :seq_id,
  prompt_logprobs: nil,      # CRITICAL: tri-state boolean | nil
  topk_prompt_logprobs: 0,
  type: "sample"
]
```

#### ForwardBackwardRequest
```elixir
defstruct [:forward_backward_input, :model_id, :seq_id]
```

### 6.4 Response Types

#### SampledSequence
```elixir
defstruct [:tokens, :logprobs, :stop_reason]

@type t :: %__MODULE__{
  tokens: [integer()],
  logprobs: [float()] | nil,
  stop_reason: StopReason.t()
}
```

#### SampleResponse
```elixir
defstruct [:sequences, :prompt_logprobs, :topk_prompt_logprobs, type: "sample"]
```

#### ForwardBackwardOutput
```elixir
defstruct [:loss_fn_output_type, :loss_fn_outputs, :metrics]

# Note: No 'loss' field - only metrics and loss_fn_outputs
```

### 6.5 Error Type

#### Tinkex.Error
```elixir
defstruct [:message, :type, :status, :category, :data, :retry_after_ms]

@type error_type ::
  :api_connection
  | :api_timeout
  | :api_status
  | :request_failed
  | :validation

@type t :: %__MODULE__{
  message: String.t(),
  type: error_type(),
  status: integer() | nil,
  category: RequestErrorCategory.t() | nil,
  data: map() | nil,
  retry_after_ms: non_neg_integer() | nil
}

# Functions:
# - user_error?/1: t() -> boolean()
# - retryable?/1: t() -> boolean()
```

---

## 7. Quality Gates

Phase 1 is **complete** when ALL of the following are true:

### 7.1 Implementation Checklist

- [ ] All enum types implemented with parse/to_string functions
- [ ] All core data structures implemented with required functions
- [ ] All request types implemented with proper defaults
- [ ] All response types implemented
- [ ] Tinkex.Error implemented with helper functions

### 7.2 Testing Checklist

- [ ] Every type has a corresponding test file
- [ ] Every type has JSON encoding tests
- [ ] TensorData has roundtrip tests
- [ ] RequestErrorCategory has case-insensitive parse tests
- [ ] SampleRequest has tri-state prompt_logprobs tests
- [ ] All tests pass: `mix test`

### 7.3 Type Safety Checklist

- [ ] All types have `@type t` specs
- [ ] All public functions have `@spec`
- [ ] Dialyzer passes with no warnings: `mix dialyzer`

### 7.4 Documentation Checklist

- [ ] Every module has `@moduledoc` referencing Python type
- [ ] Complex functions have `@doc` explaining behavior

---

## 8. Common Pitfalls to Avoid

1. **Don't strip nil values globally** - Use `Jason.Encoder` as-is
2. **Don't use capitalized error categories** - Wire format is lowercase
3. **Don't support float64/int32 in TensorData** - Only int64/float32
4. **Don't forget the `type` discriminator field** - Most structs need it
5. **Don't use `image_data` or `asset_id`** - Use `data` and `location`
6. **Don't default `prompt_logprobs` to `false`** - Use `nil` for tri-state

---

## 9. Execution Commands

### 9.1 Development Cycle

```bash
# Run specific test file
mix test test/tinkex/types/stop_reason_test.exs

# Run all type tests
mix test test/tinkex/types/

# Check types
mix dialyzer

# Format code
mix format

# Full check before moving on
mix test && mix dialyzer && mix format --check-formatted
```

### 9.2 Completion Verification

```bash
# Final verification before Phase 1 sign-off
mix compile --warnings-as-errors
mix test --cover
mix dialyzer
```

---

## 10. Next Steps After Phase 1

Once Phase 1 is complete:

1. **Phase 2**: HTTP Layer (`Tinkex.HTTP`, retry logic, connection pools)
2. **Phase 3**: Futures and polling (`Tinkex.Future`)
3. **Phase 4**: Client implementations (TrainingClient, SamplingClient)

The types you implement in Phase 1 are the foundation for all subsequent phases. Take time to get them right - they should not need revision later.

---

## Summary

Your task is to implement the complete Tinkex type system following test-driven development. Read all documentation first, then implement types in the specified order, writing tests before implementation. Every type must:

1. Have a test file with JSON encoding tests
2. Use `@derive Jason.Encoder` with explicit field lists
3. Have proper `@type` and `@spec` annotations
4. Pass Dialyzer with no warnings
5. Match the verified Python wire format exactly

Good luck! 🚀
