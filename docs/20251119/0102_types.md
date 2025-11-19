Here’s a focused **Phase 1 type-system implementation doc** you can drop into the port docs set (e.g. `0101_type_system_phase_1.md`).

---

# 0101 – Phase 1 Type System Implementation & Testing

> **Phase:** 1
> **Timebox:** Week 1 – Days 4–7
> **Objective:** Implement and validate all core types so that **Elixir <→ JSON** matches the verified Python/Tinker wire format.

This document spells out:

* Exactly **which modules & types** to implement in Phase 1
* How to wire them together (dependencies)
* How to **encode/decode** them correctly
* What **tests** must exist before Phase 1 is considered “done”

It assumes Phase 0’s **wire format verification** is complete and fixtures exist (StopReason, SampleRequest, image chunks, etc.).

---

## 1. Scope & Ordering

### 1.1 Implementation order (within Phase 1)

We follow this strict order to minimize churn:

1. **Enums & literals**

   * `StopReason`
   * `LossFnType`
   * `RequestErrorCategory`
   * `TensorDtype` (for `TensorData`)
2. **Data structures**

   * Core chunks: `EncodedTextChunk`, `ImageChunk`, `ImageAssetPointerChunk`
   * `ModelInput`, `ModelInputChunk` union
   * `TensorData`
   * `Datum`
   * `SamplingParams`
3. **Request types**

   * `ForwardBackwardInput`
   * `ForwardBackwardRequest`
   * `ForwardRequest` (if used)
   * `OptimStepRequest` + `AdamParams`
   * `SampleRequest`
   * `CreateModelRequest`, `CreateSamplingSessionRequest`, `CreateSessionRequest`
   * `SaveWeightsRequest`, `SaveWeightsForSamplerRequest`, `LoadWeightsRequest`, etc. (as needed by Clients later)
4. **Response types**

   * `ForwardBackwardOutput`
   * `OptimStepResponse`
   * `SampleResponse` + `SampledSequence`
   * `CreateModelResponse`
   * `CreateSamplingSessionResponse`
   * `CreateSessionResponse`
   * `CheckpointsListResponse`, `TrainingRunsResponse` (backing the CLI)
   * `FutureRetrieveResponse` union + `TryAgainResponse`
5. **Error type**

   * `Tinkex.Error` (SDK error struct wired to `RequestErrorCategory` and status codes)

**Phase 1 ends** when all of the above:

* Exist as Elixir structs with typespecs.
* Encode to JSON in a way that matches Python’s wire format.
* Have unit/property tests proving invariants.
* Pass Dialyzer with no type warnings.

---

## 2. Design patterns & conventions

### 2.1 Module naming & layout

Under `lib/tinkex/types/`:

* Enums / simple types:

  * `stop_reason.ex` → `Tinkex.Types.StopReason`
  * `loss_fn_type.ex` → `Tinkex.Types.LossFnType`
  * `request_error_category.ex` → `Tinkex.Types.RequestErrorCategory`
  * `tensor_dtype.ex` → `Tinkex.Types.TensorDtype`

* Core data:

  * `encoded_text_chunk.ex` → `Tinkex.Types.EncodedTextChunk`
  * `image_chunk.ex` → `Tinkex.Types.ImageChunk`
  * `image_asset_pointer_chunk.ex` → `Tinkex.Types.ImageAssetPointerChunk`
  * `model_input_chunk.ex` → `Tinkex.Types.ModelInputChunk` (type-only)
  * `model_input.ex` → `Tinkex.Types.ModelInput`
  * `tensor_data.ex` → `Tinkex.Types.TensorData`
  * `datum.ex` → `Tinkex.Types.Datum`
  * `sampling_params.ex` → `Tinkex.Types.SamplingParams`

* Requests & responses:

  * `forward_backward_input.ex`, `forward_backward_request.ex`, `forward_backward_output.ex`
  * `forward_request.ex` (if ported)
  * `optim_step_request.ex`, `optim_step_response.ex`
  * `sample_request.ex`, `sample_response.ex`, `sampled_sequence.ex`
  * `create_model_request.ex`, `create_model_response.ex`
  * `create_sampling_session_request.ex`, `create_sampling_session_response.ex`
  * `create_session_request.ex`, `create_session_response.ex`
  * `save_weights_request.ex`, `save_weights_response.ex`
  * `save_weights_for_sampler_request.ex`, `save_weights_for_sampler_response.ex`
  * `load_weights_request.ex`, `load_weights_response.ex`
  * `checkpoint.ex`, `checkpoints_list_response.ex`
  * `training_run.ex`, `training_runs_response.ex`
  * `future_retrieve_request.ex`, `future_retrieve_response.ex`, `try_again_response.ex`
  * `get_info_request.ex`, `get_info_response.ex`
  * `health_response.ex`, `telemetry_*` types (for reporter)

* Error:

  * `error.ex` → `Tinkex.Error`

Tests live under `test/tinkex/types/*.exs`, mirroring file names.

### 2.2 Structs, typespecs, and JSON

General pattern for all request/response structs:

```elixir
defmodule Tinkex.Types.SampleRequest do
  @moduledoc """
  SampleRequest

  Mirrors Python tinker.types.sample_request.SampleRequest.
  Wire format verified via Phase 0 fixtures.
  """

  @derive {Jason.Encoder,
           only: [
             :num_samples,
             :prompt,
             :sampling_params,
             :base_model,
             :model_path,
             :sampling_session_id,
             :seq_id,
             :prompt_logprobs,
             :topk_prompt_logprobs,
             :type
           ]}
  defstruct [
    num_samples: 1,
    :prompt,
    :sampling_params,
    :base_model,
    :model_path,
    :sampling_session_id,
    :seq_id,
    prompt_logprobs: nil,
    topk_prompt_logprobs: 0,
    type: "sample" # literal discriminator
  ]

  @type t :: %__MODULE__{
          num_samples: pos_integer(),
          prompt: Tinkex.Types.ModelInput.t(),
          sampling_params: Tinkex.Types.SamplingParams.t(),
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          sampling_session_id: String.t() | nil,
          seq_id: integer() | nil,
          prompt_logprobs: boolean() | nil,
          topk_prompt_logprobs: non_neg_integer(),
          type: String.t()
        }
end
```

**Rules:**

* Use `@derive Jason.Encoder` with an explicit `only:` list to avoid leaking internal fields.
* `nil` fields are **not stripped** globally. Jason will encode them as `null`, which matches Python’s behavior for Optional fields.
* **Discriminator fields** (`type`) use the lowercase string values from Python wire format, unless we prove otherwise.

### 2.3 Validation strategy

Phase 1 validation is **lightweight and pure**:

* No Ecto.
* Use constructor helpers + plain functions for checks.

Pattern examples:

* `AdamParams.new/1` with range checks on learning rate, betas, eps.
* `TensorData.from_nx/1` raising `ArgumentError` for unsupported dtypes.

---

## 3. Detailed implementation per group

### 3.1 Enums & literals

#### 3.1.1 `StopReason`

Python wire: `Literal["length", "stop"]` (docs updated to this).

Elixir:

```elixir
defmodule Tinkex.Types.StopReason do
  @type t :: :length | :stop

  @spec to_string(t()) :: String.t()
  def to_string(:length), do: "length"
  def to_string(:stop), do: "stop"

  @spec parse(String.t() | nil) :: t() | nil
  def parse("length"), do: :length
  def parse("stop"), do: :stop
  def parse(_), do: nil
end
```

You don’t usually encode/derive this standalone; it appears inside `SampledSequence`. Tests will assert:

* JSON from `SampleResponse` uses `"length"`/`"stop"` (lowercase).
* Parser tolerates future values safely (returns nil or `:length`/`:stop` only).

#### 3.1.2 `LossFnType`

Python: `Literal["cross_entropy", "importance_sampling", "ppo"]`.

Elixir:

```elixir
defmodule Tinkex.Types.LossFnType do
  @type t :: :cross_entropy | :importance_sampling | :ppo

  def to_string(:cross_entropy), do: "cross_entropy"
  def to_string(:importance_sampling), do: "importance_sampling"
  def to_string(:ppo), do: "ppo"

  def parse("cross_entropy"), do: :cross_entropy
  def parse("importance_sampling"), do: :importance_sampling
  def parse("ppo"), do: :ppo
  def parse(_), do: nil
end
```

Used in `ForwardBackwardInput.loss_fn`.

#### 3.1.3 `RequestErrorCategory`

Python: StrEnum auto → wire `"unknown"/"server"/"user"` (lowercase).

Elixir implementation (already sketched in `01_type_system`):

* `parse/1` case-insensitive.
* `retryable?/1` semantics centralize error handling.

Tests:

* `parse("Server") == :server`
* `retryable?(:user) == false`, others true.

#### 3.1.4 `TensorDtype`

Python: `Literal["int64", "float32"]`.

Elixir:

```elixir
defmodule Tinkex.Types.TensorDtype do
  @type t :: :int64 | :float32

  def to_string(:int64), do: "int64"
  def to_string(:float32), do: "float32"

  def parse("int64"), do: :int64
  def parse("float32"), do: :float32
  def parse(_), do: nil
end
```

Used by `TensorData`.

---

### 3.2 Core data structures

#### 3.2.1 `EncodedTextChunk`

Matches `types/encoded_text_chunk.py`:

```elixir
defmodule Tinkex.Types.EncodedTextChunk do
  @derive Jason.Encoder
  defstruct [:tokens, type: "encoded_text"]

  @type t :: %__MODULE__{
          tokens: [integer()],
          type: String.t()
        }

  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{tokens: tokens}), do: length(tokens)
end
```

#### 3.2.2 `ImageChunk`

Wire fields from Python:

* `data: bytes` (serialized as base64 string)
* `format: "png" | "jpeg"`
* `height`, `width`, `tokens`
* `type: "image"`

Elixir:

```elixir
defmodule Tinkex.Types.ImageChunk do
  @derive Jason.Encoder
  defstruct [:data, :format, :height, :width, :tokens, type: "image"]

  @type format :: :png | :jpeg

  @type t :: %__MODULE__{
          data: String.t(),   # base64 string
          format: format(),
          height: pos_integer(),
          width: pos_integer(),
          tokens: non_neg_integer(),
          type: String.t()
        }

  @spec new(binary(), format(), pos_integer(), pos_integer(), non_neg_integer()) :: t()
  def new(image_binary, format, height, width, tokens) do
    %__MODULE__{
      data: Base.encode64(image_binary),
      format: format,
      height: height,
      width: width,
      tokens: tokens,
      type: "image"
    }
  end

  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{tokens: tokens}), do: tokens
end
```

Tests use Phase 0 fixtures to compare JSON encoding.

#### 3.2.3 `ImageAssetPointerChunk`

Wire fields: `location`, `format`, `height`, `width`, `tokens`, `type`.

Elixir:

```elixir
defmodule Tinkex.Types.ImageAssetPointerChunk do
  @derive Jason.Encoder
  defstruct [:location, :format, :height, :width, :tokens, type: "image_asset_pointer"]

  @type format :: :png | :jpeg

  @type t :: %__MODULE__{
          location: String.t(),
          format: format(),
          height: pos_integer(),
          width: pos_integer(),
          tokens: non_neg_integer(),
          type: String.t()
        }

  def length(%__MODULE__{tokens: tokens}), do: tokens
end
```

#### 3.2.4 `ModelInputChunk` union

Elixir type alias only; JSON representation is handled by the individual chunk structs:

```elixir
defmodule Tinkex.Types.ModelInputChunk do
  @type t ::
          Tinkex.Types.EncodedTextChunk.t()
          | Tinkex.Types.ImageChunk.t()
          | Tinkex.Types.ImageAssetPointerChunk.t()
end
```

#### 3.2.5 `ModelInput`

Python:

* `chunks: List[ModelInputChunk]`
* `from_ints`, `to_ints`, `length` methods.

Elixir:

```elixir
defmodule Tinkex.Types.ModelInput do
  @derive Jason.Encoder
  defstruct [:chunks]

  @type t :: %__MODULE__{
          chunks: [Tinkex.Types.ModelInputChunk.t()]
        }

  @spec from_ints([integer()]) :: t()
  def from_ints(tokens) when is_list(tokens) do
    %__MODULE__{
      chunks: [%Tinkex.Types.EncodedTextChunk{tokens: tokens}]
    }
  end

  @spec to_ints(t()) :: [integer()]
  def to_ints(%__MODULE__{chunks: chunks}) do
    Enum.flat_map(chunks, fn
      %Tinkex.Types.EncodedTextChunk{tokens: tokens} -> tokens
      other ->
        raise ArgumentError,
              "Cannot convert non-text chunk to ints: #{inspect(other.type)}"
    end)
  end

  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{chunks: chunks}) do
    Enum.reduce(chunks, 0, fn chunk, acc ->
      acc + apply_length(chunk)
    end)
  end

  defp apply_length(%Tinkex.Types.EncodedTextChunk{} = c), do: Tinkex.Types.EncodedTextChunk.length(c)
  defp apply_length(%Tinkex.Types.ImageChunk{} = c), do: Tinkex.Types.ImageChunk.length(c)
  defp apply_length(%Tinkex.Types.ImageAssetPointerChunk{} = c),
    do: Tinkex.Types.ImageAssetPointerChunk.length(c)
end
```

#### 3.2.6 `TensorData` (with Nx integration)

Python:

* `data: List[int]` or `List[float]`
* `dtype: "int64" | "float32"`
* `shape: Optional[List[int]]`
* Aggressive casting rules for `from_torch`/`from_numpy`.

Elixir:

```elixir
defmodule Tinkex.Types.TensorData do
  @moduledoc "Flattened tensor data compatible with Tinker backend."

  @derive Jason.Encoder
  defstruct [:data, :dtype, :shape]

  @type dtype :: :int64 | :float32
  @type t :: %__MODULE__{
          data: [number()],
          dtype: dtype(),
          shape: [non_neg_integer()] | nil
        }

  @spec from_nx(Nx.Tensor.t()) :: t()
  def from_nx(%Nx.Tensor{} = tensor) do
    {tensor, dtype} = normalize_dtype(tensor)

    %__MODULE__{
      data: Nx.to_flat_list(tensor),
      dtype: dtype,
      shape: if(tensor.shape == {}, do: nil, else: Tuple.to_list(tensor.shape))
    }
  end

  @spec to_nx(t()) :: Nx.Tensor.t()
  def to_nx(%__MODULE__{data: data, dtype: dtype, shape: nil}) do
    Nx.tensor(data, type: tensor_dtype_to_nx(dtype))
  end

  def to_nx(%__MODULE__{data: data, dtype: dtype, shape: shape}) do
    data
    |> Nx.tensor(type: tensor_dtype_to_nx(dtype))
    |> Nx.reshape(List.to_tuple(shape))
  end

  defp normalize_dtype(%Nx.Tensor{type: {:f, 64}} = t),
    do: {Nx.as_type(t, {:f, 32}), :float32}

  defp normalize_dtype(%Nx.Tensor{type: {:f, 32}} = t), do: {t, :float32}
  defp normalize_dtype(%Nx.Tensor{type: {:s, 64}} = t), do: {t, :int64}

  defp normalize_dtype(%Nx.Tensor{type: {:s, 32}} = t),
    do: {Nx.as_type(t, {:s, 64}), :int64}

  defp normalize_dtype(%Nx.Tensor{type: {:u, _}} = t),
    do: {Nx.as_type(t, {:s, 64}), :int64}

  defp normalize_dtype(%Nx.Tensor{type: type}) do
    raise ArgumentError, "Unsupported tensor dtype: #{inspect(type)}"
  end

  defp tensor_dtype_to_nx(:float32), do: {:f, 32}
  defp tensor_dtype_to_nx(:int64), do: {:s, 64}
end
```

Tests:

* Roundtrip various shapes and dtypes.
* Assert `dtype` is one of `:int64 | :float32` only.

#### 3.2.7 `Datum`

Python:

* `loss_fn_inputs: Dict[str, TensorData]`
* `model_input: ModelInput`
* validator converts torch/np/list → TensorData.

Elixir:

```elixir
defmodule Tinkex.Types.Datum do
  @derive Jason.Encoder
  defstruct [:model_input, :loss_fn_inputs]

  @type t :: %__MODULE__{
          model_input: Tinkex.Types.ModelInput.t(),
          loss_fn_inputs: %{String.t() => Tinkex.Types.TensorData.t()}
        }

  @spec new(%{
          model_input: Tinkex.Types.ModelInput.t(),
          loss_fn_inputs: map()
        }) :: t()
  def new(%{model_input: mi, loss_fn_inputs: inputs}) do
    %__MODULE__{
      model_input: mi,
      loss_fn_inputs: convert_tensors(inputs)
    }
  end

  defp convert_tensors(inputs) do
    Map.new(inputs, fn {k, v} -> {k, maybe_convert_tensor(v)} end)
  end

  defp maybe_convert_tensor(%Nx.Tensor{} = t),
    do: Tinkex.Types.TensorData.from_nx(t)

  defp maybe_convert_tensor(%Tinkex.Types.TensorData{} = td), do: td

  defp maybe_convert_tensor(list) when is_list(list) do
    dtype =
      case Enum.at(list, 0) do
        x when is_integer(x) -> :int64
        x when is_float(x) -> :float32
        nil -> :float32
        _ -> raise ArgumentError, "Cannot infer dtype from list entry"
      end

    %Tinkex.Types.TensorData{
      data: list,
      dtype: dtype,
      shape: [length(list)]
    }
  end

  defp maybe_convert_tensor(other), do: other
end
```

#### 3.2.8 `SamplingParams`

Straightforward mapping from Python:

```elixir
defmodule Tinkex.Types.SamplingParams do
  @derive Jason.Encoder
  defstruct [
    :max_tokens,
    :seed,
    :stop,
    temperature: 1.0,
    top_k: -1,
    top_p: 1.0
  ]

  @type stop_t :: String.t() | [String.t()] | [integer()] | nil

  @type t :: %__MODULE__{
          max_tokens: non_neg_integer() | nil,
          seed: integer() | nil,
          stop: stop_t(),
          temperature: float(),
          top_k: integer(),
          top_p: float()
        }
end
```

---

### 3.3 Request types

Most requests mirror the Python classes exactly; the main subtlety is **Optional vs required** and `seq_id` semantics.

#### 3.3.1 `ForwardBackwardInput` / `ForwardBackwardRequest`

```elixir
defmodule Tinkex.Types.ForwardBackwardInput do
  @derive Jason.Encoder
  defstruct [:data, :loss_fn, :loss_fn_config]

  @type t :: %__MODULE__{
          data: [Tinkex.Types.Datum.t()],
          loss_fn: Tinkex.Types.LossFnType.t(),
          loss_fn_config: %{String.t() => float()} | nil
        }
end

defmodule Tinkex.Types.ForwardBackwardRequest do
  @derive Jason.Encoder
  defstruct [:forward_backward_input, :model_id, :seq_id]

  @type t :: %__MODULE__{
          forward_backward_input: Tinkex.Types.ForwardBackwardInput.t(),
          model_id: String.t(),  # ModelID type alias
          seq_id: integer() | nil
        }
end
```

Same pattern for `ForwardRequest`, if you choose to port it.

#### 3.3.2 `OptimStepRequest` & `AdamParams`

```elixir
defmodule Tinkex.Types.AdamParams do
  @derive Jason.Encoder
  defstruct learning_rate: 0.0001,
            beta1: 0.9,
            beta2: 0.95,
            eps: 1.0e-12

  @type t :: %__MODULE__{
          learning_rate: float(),
          beta1: float(),
          beta2: float(),
          eps: float()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts \\ []) do
    lr = Keyword.get(opts, :learning_rate, 0.0001)
    b1 = Keyword.get(opts, :beta1, 0.9)
    b2 = Keyword.get(opts, :beta2, 0.95)
    eps = Keyword.get(opts, :eps, 1.0e-12)

    with {:ok, lr} <- validate_learning_rate(lr),
         {:ok, b1} <- validate_beta(b1),
         {:ok, b2} <- validate_beta(b2),
         {:ok, eps} <- validate_eps(eps) do
      {:ok, %__MODULE__{learning_rate: lr, beta1: b1, beta2: b2, eps: eps}}
    end
  end

  # validations...
end

defmodule Tinkex.Types.OptimStepRequest do
  @derive Jason.Encoder
  defstruct [:adam_params, :model_id, :seq_id]

  @type t :: %__MODULE__{
          adam_params: Tinkex.Types.AdamParams.t(),
          model_id: String.t(),
          seq_id: integer() | nil
        }
end
```

#### 3.3.3 `SampleRequest`

We already sketched this; critical detail is `prompt_logprobs :: boolean() | nil` (tri-state).

Use Phase 0 golden JSON fixtures to assert:

* `nil` → `{"prompt_logprobs": null}` (or omitted if you choose field-level omission).
* May also test `true` and `false` explicitly.

---

### 3.4 Response types

#### 3.4.1 `ForwardBackwardOutput`

Python: no `loss` field, only metrics and `loss_fn_outputs`.

```elixir
defmodule Tinkex.Types.ForwardBackwardOutput do
  @derive Jason.Encoder
  defstruct [:loss_fn_output_type, :loss_fn_outputs, :metrics]

  @type t :: %__MODULE__{
          loss_fn_output_type: String.t(),
          loss_fn_outputs: [map()], # can later refine to TensorData maps
          metrics: %{String.t() => float()}
        }
end
```

Any combined outputs you construct later must respect this shape.

#### 3.4.2 `SampleResponse` & `SampledSequence`

```elixir
defmodule Tinkex.Types.SampledSequence do
  @derive Jason.Encoder
  defstruct [:tokens, :logprobs, :stop_reason]

  @type t :: %__MODULE__{
          tokens: [integer()],
          logprobs: [float()] | nil,
          stop_reason: Tinkex.Types.StopReason.t()
        }
end

defmodule Tinkex.Types.SampleResponse do
  @derive Jason.Encoder
  defstruct [:sequences, :prompt_logprobs, :topk_prompt_logprobs, type: "sample"]

  @type t :: %__MODULE__{
          sequences: [Tinkex.Types.SampledSequence.t()],
          prompt_logprobs: [float() | nil] | nil,
          topk_prompt_logprobs:
            [[{integer(), float()}] | nil] | nil,
          type: String.t()
        }
end
```

#### 3.4.3 Future responses

Define individual structs and a union type:

```elixir
defmodule Tinkex.Types.FuturePendingResponse do
  @derive Jason.Encoder
  defstruct status: "pending"

  @type t :: %__MODULE__{status: String.t()}
end

defmodule Tinkex.Types.FutureCompletedResponse do
  @derive Jason.Encoder
  defstruct status: "completed", result: %{}

  @type t :: %__MODULE__{status: String.t(), result: map()}
end

defmodule Tinkex.Types.FutureFailedResponse do
  @derive Jason.Encoder
  defstruct status: "failed", error: %{}

  @type t :: %__MODULE__{status: String.t(), error: map()}
end

defmodule Tinkex.Types.TryAgainResponse do
  @derive Jason.Encoder
  defstruct type: "try_again", request_id: nil, queue_state: nil, retry_after_ms: nil

  @type t :: %__MODULE__{
          type: String.t(),
          request_id: String.t(),
          queue_state: String.t(),
          retry_after_ms: integer() | nil
        }
end

defmodule Tinkex.Types.FutureRetrieveResponse do
  @type t ::
          Tinkex.Types.FuturePendingResponse.t()
          | Tinkex.Types.FutureCompletedResponse.t()
          | Tinkex.Types.FutureFailedResponse.t()
          | Tinkex.Types.TryAgainResponse.t()
end
```

For Phase 1, you mostly care about **encoding tests**; full decode/dispatch logic lands in Phase 3 (Futures).

---

### 3.5 Error type

`Tinkex.Error` centralizes status/category and additional metadata.

```elixir
defmodule Tinkex.Error do
  @moduledoc "Client error type."

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
          category: Tinkex.Types.RequestErrorCategory.t() | nil,
          data: map() | nil,
          retry_after_ms: non_neg_integer() | nil
        }
end
```

Phase 1 tests only need to check **construction** and possibly `user_error?/1` & `retryable?/1` once you implement them (pulling from `05_error_handling.md`).

---

## 4. Per-type process & testing

For **each** type, follow this workflow:

1. **Read spec**

   * Use `01_type_system.md` and the Python source (provided in the packed repo) + Phase 0 fixtures.
2. **Identify dependencies**

   * E.g. SampleRequest → ModelInput, SamplingParams.
   * Make sure dependent modules exist or are stubbed.
3. **Implement struct + @type**

   * Use Elixir idiomatic names; keep exact JSON field names (especially when they differ from Elixir field names, though we mostly keep 1:1).
4. **Implement validation where needed**

   * For “domain” logic (e.g. AdamParams ranges), via pure functions or `new/1` constructors.
5. **Add `@derive Jason.Encoder`**

   * Ensure `only:` or `except:` is used to avoid leaking internal fields (e.g. ETS references).
6. **Write unit tests**

   * Construction tests.
   * JSON encoding tests using Phase 0 fixtures where available.
7. **Write property tests (where useful)**

   * For TensorData (roundtrips), ModelInput (length), etc.

### 4.1 Testing structure

Put tests under:

* `test/tinkex/types/stop_reason_test.exs`
* `test/tinkex/types/request_error_category_test.exs`
* `test/tinkex/types/tensor_data_test.exs`
* … etc.

Examples:

**JSON equality vs fixtures:**

```elixir
test "SampleRequest prompt_logprobs tri-state matches Python" do
  base = %SampleRequest{
    prompt: Tinkex.Types.ModelInput.from_ints([1, 2]),
    sampling_params: %SamplingParams{}
  }

  cases = [
    {:null, %{base | prompt_logprobs: nil}, "sample_request_prompt_logprobs_null.json"},
    {:true, %{base | prompt_logprobs: true}, "sample_request_prompt_logprobs_true.json"},
    {:false, %{base | prompt_logprobs: false}, "sample_request_prompt_logprobs_false.json"}
  ]

  Enum.each(cases, fn {_label, req, fixture} ->
    json = Jason.encode!(req)
    expected = File.read!("test/support/fixtures/wire/" <> fixture)
    assert Jason.decode!(json) == Jason.decode!(expected)
  end)
end
```

**TensorData property-style tests:**

```elixir
property "TensorData.from_nx/to_nx roundtrips for 1D float64 tensors" do
  check all list <- StreamData.list_of(StreamData.float(), min_length: 1, max_length: 10) do
    t = Nx.tensor(list, type: {:f, 64})
    td = TensorData.from_nx(t)
    rt = TensorData.to_nx(td)

    assert td.dtype == :float32
    assert Tuple.to_list(rt.shape) == Tuple.to_list(Nx.as_type(t, {:f, 32}).shape)
  end
end
```

(You can plug `stream_data` as a test dependency if you like; if not, keep basic property tests manual.)

---

## 5. Phase 1 Quality Gate

Phase 1 is **complete** when:

1. **Types implemented**

   * All enumerated modules above exist and compile.
2. **Tests**

   * Unit tests written & passing for:

     * Enums & parsers (`StopReason`, `LossFnType`, `RequestErrorCategory`, `TensorDtype`).
     * Core data (`ModelInput`, `TensorData`, `Datum`, chunk types, `SamplingParams`).
     * Requests/responses that are wire-facing (`SampleRequest`, `ForwardBackward*`, `OptimStep*`, `SampleResponse`, `ForwardBackwardOutput`).
   * Golden JSON tests exist for:

     * `SampleRequest` tri-state fields.
     * Image JSON structures.
     * At least one `ForwardBackwardRequest` and `SampleResponse` case.
3. **Dialyzer**

   * `mix dialyzer` produces no warnings for `Tinkex.Types.*` and `Tinkex.Error`.
4. **Encoding semantics**

   * No global nil-stripping. Tests assert `nil → null` behavior where Python uses Optional fields.
5. **Documentation**

   * Each module has a short `@moduledoc` referencing the Python type it mirrors.

Once this gate is hit, the HTTP layer (Phase 2) can rely on these types as stable building blocks, and we don’t have to revisit wire semantics unless upstream API changes.

If you’d like, next I can:

* Draft the **exact module skeletons** (without tests) you can paste into `lib/tinkex/types/`, or
* Draft the initial **Phase 1 test modules** (`tensor_data_test.exs`, `sample_request_test.exs`, etc.) so you can start from ready-made ExUnit files.
