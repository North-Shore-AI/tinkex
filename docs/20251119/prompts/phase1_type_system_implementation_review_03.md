Here’s what I see from reviewing the Elixir types (lib + tests) against:

* the Python SDK design as documented in your port-research docs, and
* your Phase-1 type-system plan (`0102_types.md`, `01_type_system.md`), and
* internal consistency between modules/tests.

I’ll group this into:

1. **Likely bugs / real mismatches**
2. **Gray-area / “probably want to tighten” mismatches vs Python/plan**
3. **Stuff that matches well (so you don’t worry about it)**

---

## 1. Likely bugs / real mismatches

### 1.1 `SampleResponse.topk_prompt_logprobs` shape vs type spec

**Code:**

```elixir
defmodule Tinkex.Types.SampleResponse do
  defstruct [:sequences, :prompt_logprobs, :topk_prompt_logprobs, type: "sample"]

  @type topk_entry :: {integer(), float()}
  @type t :: %__MODULE__{
          sequences: [SampledSequence.t()],
          prompt_logprobs: [float() | nil] | nil,
          topk_prompt_logprobs: [[topk_entry()] | nil] | nil,
          type: String.t()
        }

  @spec from_json(map()) :: t()
  def from_json(json) do
    sequences =
      json["sequences"]
      |> Enum.map(&SampledSequence.from_json/1)

    %__MODULE__{
      sequences: sequences,
      prompt_logprobs: json["prompt_logprobs"],
      topk_prompt_logprobs: json["topk_prompt_logprobs"],
      type: json["type"] || "sample"
    }
  end
end
```

**Issue:**

* The Python wire format for `topk_prompt_logprobs` is (per docs) effectively:

  * `List[List[Tuple[int, float]] | None] | None` — i.e. outer list per prompt token, each inner value is either `null` or a list of `[token_id, logprob]` pairs.
* Your **type spec** says `[[topk_entry()] | nil] | nil` where `topk_entry` is **a tuple** `{integer(), float()}`.
* But `from_json` just passes through the decoded JSON; it **never converts `[id, logprob]` lists to `{id, logprob}` tuples**. So at runtime you actually have **nested lists of 2-element lists**, not tuples.

This is a concrete mismatch between:

* **Spec**: `[{int, float}]`
* **Actual runtime values**: `[[int, float]]`

➡️ **Fix options:**

* **Option A (recommended):** In `from_json/1`, map each `[[id, lp] ...]` into `{id, lp}` to match the typespec and your docs:

  ```elixir
  topk_prompt_logprobs =
    case json["topk_prompt_logprobs"] do
      nil -> nil
      list ->
        Enum.map(list, fn
          nil -> nil
          inner ->
            Enum.map(inner, fn [id, lp] -> {id, lp} end)
        end)
    end
  ```

  and assign that into the struct.

* **Option B:** If you’d rather keep raw JSON shape, **change the typespec** to reflect that it’s nested lists of two-element lists, not tuples.

Right now it’s just silently wrong.

---

### 1.2 `CreateModelRequest.lora_config` defaulting to `nil` instead of default config

**Code:**

```elixir
defmodule Tinkex.Types.CreateModelRequest do
  @derive {Jason.Encoder, only: [:session_id, :model_seq_id, :base_model, :user_metadata, :lora_config, :type]}
  defstruct [:session_id, :model_seq_id, :base_model, :user_metadata, :lora_config, type: "create_model"]

  @type t :: %__MODULE__{
          session_id: String.t(),
          model_seq_id: integer(),
          base_model: String.t(),
          user_metadata: map() | nil,
          lora_config: LoraConfig.t() | nil,
          type: String.t()
        }
end
```

**Docs / Python side:**

* `CreateModelRequest` in Python has `lora_config: LoraConfig` with **default values inside `LoraConfig`**, not `Optional[LoraConfig] = None`.
* Your own port docs treat `LoraConfig` as the thing that defines the LoRA layout, with defaults of `rank=32, train_mlp=True, ...`.

**Current Elixir behaviour:**

* `lora_config` defaults to `nil`.
* With the `@derive` encoder, `nil` will encode as `"lora_config": null` (it is *not* omitted).
* That means you’re sending `null` where Python is sending a fully-populated default config object.

Whether the backend currently tolerates `null` here is unknown, but it’s a real divergence from the Python SDK behaviour and from your own docs.

➡️ **Recommended fix:**

* Change the defstruct to default to a real config:

  ```elixir
  defstruct [
    :session_id,
    :model_seq_id,
    :base_model,
    :user_metadata,
    lora_config: %LoraConfig{},
    type: "create_model"
  ]

  @type t :: %__MODULE__{
          ...,
          lora_config: LoraConfig.t(),
          ...
        }
  ```

* That brings Elixir in line with Python: you always send a config, and it has the same defaults.

---

### 1.3 `SampleResponse.topk_prompt_logprobs` typespec is slightly malformed

Even after fixing 1.1, the union is expressed in a slightly backwards way:

```elixir
@type topk_entry :: {integer(), float()}
@type t :: %__MODULE__{
        ...
        topk_prompt_logprobs: [[topk_entry()] | nil] | nil,
        ...
      }
```

This reads as:

* the **outer** list is `[[topk_entry()] | nil]`, but what you actually want is:

  * each element of the outer list is `nil` **or** `[topk_entry()]`.

So the intention is:

```elixir
topk_prompt_logprobs: [nil | [topk_entry()]] | nil
```

Right now Dialyzer will treat it differently than what the wire shape actually is.

---

## 2. Gray-area / “tighten this” vs Python or the plan

none of these are “on fire”, but they’re worth aligning.

### 2.1 `TensorData.from_nx/1` scalar shape behaviour vs docs

**Your code:**

```elixir
def from_nx(%Nx.Tensor{} = tensor) do
  {casted_tensor, dtype} = normalize_tensor(tensor)

  %__MODULE__{
    data: Nx.to_flat_list(casted_tensor),
    dtype: dtype,
    shape: Tuple.to_list(Nx.shape(casted_tensor))
  }
end
```

**Docs:**

> shape: Optional[List[int]]
> When shape is None, treat as 1D array.

In the Python pseudocode they do:

```python
shape = list(tensor.shape) if tensor.shape else None
```

So a scalar (`shape == ()`) becomes `shape = None` on the wire.

Your Elixir version **always** sets `shape` to a list; for a scalar that’s `[]`, not `nil`. That means you’ll send `"shape": []` where Python sends `"shape": null`.

This probably doesn’t matter in practice (you don’t train on scalars), but it is a subtle wire mismatch.

➡️ If you care about exact parity:

```elixir
shape_tuple = Nx.shape(casted_tensor)
shape =
  case shape_tuple do
    {} -> nil
    _  -> Tuple.to_list(shape_tuple)
  end
```

Your `to_nx/1` already handles `shape: nil` vs list correctly, so this is purely about what you emit on the wire.

---

### 2.2 Some types marked as required in specs but `defstruct` defaults are `nil`

Examples:

```elixir
defmodule Tinkex.Types.CreateSessionRequest do
  defstruct [:tags, :user_metadata, :sdk_version, type: "create_session"]

  @type t :: %__MODULE__{
          tags: [String.t()],
          user_metadata: map() | nil,
          sdk_version: String.t(),
          type: String.t()
        }
end
```

* `tags` and `sdk_version` have **no default** and are typed as **non-nil** (list/string), but at runtime they start out as `nil`.
* Same pattern for things like `CreateModelRequest.lora_config` (discussed above) and some other request structs.

This is mostly a **typespec honesty issue**:

* If you intend these to be required (and always set by client code), leaving defstruct fields `nil` is fine, but your specs are optimistic.
* If you intend to allow `nil` + send `null` to the server, then the typespec needs `| nil` to be truthful.

I’d either:

* tighten the structs (give “required” fields real defaults or enforce via smart constructors), **or**
* relax the specs to include `| nil` where that’s actually possible at runtime.

Right now Dialyzer can’t help you catch missing `sdk_version` etc.

---

### 2.3 `LoraConfig` and `CreateModelRequest` coupling vs Python

Your `LoraConfig` itself looks correct: defaults and field names match the docs.

The only discrepancy is that making `CreateModelRequest.lora_config` optional (and defaulting to `nil`) is not what your plan or Python code describes. Fixing 1.2 largely resolves this.

---

### 2.4 Minor shape of `TensorDtype.from_nx_type/1` vs expectations

```elixir
def from_nx_type({:f, 32}), do: :float32
def from_nx_type({:f, 64}), do: :float32
def from_nx_type({:s, 64}), do: :int64
def from_nx_type({:s, 32}), do: :int64
def from_nx_type({:u, _}), do: :int64
```

* That matches the “aggressive casting” described, but you don’t handle other Nx dtypes (`{:bf, 16}`, etc.).
* The docs explicitly call those unsupported, so having `from_nx_type/1` just return `nil` for them is fine – but consumers should be ready for `nil`.

Right now you don’t use `from_nx_type/1` inside `TensorData.from_nx/1`, so this isn’t a bug; just be aware that this function is lossy by design and should only be used where you already know the dtype is supported.

---

### 2.5 Missing “Phase 1” types from the plan

From your own `0102_types.md` “scope & ordering”, Phase 1 included types like:

* `ModelInputChunk` type-only module
* `ForwardRequest`
* `CheckpointsListResponse`, `TrainingRunsResponse`
* `FutureRetrieveRequest`, telemetry responses, etc.

In the actual codebase you’ve implemented:

* Enums (`StopReason`, `LossFnType`, `RequestErrorCategory`, `TensorDtype`)
* All chunk types, `ModelInput`, `TensorData`, `Datum`, `SamplingParams`
* The core training/sampling requests/responses
* `FutureRetrieveResponse` union + `TryAgainResponse`
* `Tinkex.Error`

…but **you don’t yet have**:

* `Tinkex.Types.ModelInputChunk` module (only inline type in `ModelInput`).
* `ForwardRequest` (just F/B).
* Any of the checkpoint / training-run list response types.
* `FutureRetrieveRequest`.

That’s totally fine if you’re mid-Phase-1, but relative to the plan, these are “missing pieces” to call out.

---

### 2.6 Queue / future types: strings vs atoms

In your docs, `TryAgainResponse.queue_state` is a string in the wire format:

> `"active" | "paused_capacity" | "paused_rate_limit"`

Your Elixir implementation:

```elixir
defmodule Tinkex.Types.TryAgainResponse do
  defstruct [:type, :request_id, :queue_state, :retry_after_ms]

  @type queue_state :: :active | :paused_capacity | :paused_rate_limit
  ...
  def parse_queue_state("active"), do: :active
  ...
  def parse_queue_state(_), do: :active
end
```

* Internally you’re storing **atoms** via `parse_queue_state/1`.
* There is **no Jason encoder** for `TryAgainResponse`, so you’re only **decoding** these; you never send them back.

That’s a perfectly fine internal representation and matches the intent; just be aware it diverges from the literal text in `01_type_system.md` (strings) but not from the wire format.

---

## 3. Things that look correct / in good shape

These are areas where the implementation hews very closely to both Python and your port docs.

### 3.1 `AdamParams`

* Defaults: `0.0001`, `0.9`, `0.95`, `1e-12` — match the “CORRECTED” values from the docs.
* Field name is `eps`, not `epsilon`, and tests assert the JSON uses `"eps"`.
* `new/1` validation for learning rate, betas, and eps is consistent with docs, including rejecting `beta` outside `[0, 1)`.

👍 This one is nailed.

---

### 3.2 Enum types

* `StopReason`: `"length"`/`"stop"` only, with `parse/1` returning `nil` for unknowns. Matches your updated doc that earlier `"max_tokens"/"eos"` docs were incorrect.
* `LossFnType`: 3 values (`cross_entropy`, `importance_sampling`, `ppo`), `parse/1` and `to_string/1` match docs.
* `RequestErrorCategory`:

  * Wire strings are lowercase `"unknown"/"server"/"user"`; parser is case-insensitive and defaults to `:unknown` – exactly what the docs say.
  * `retryable?/1` returns false for `:user`, true for others.
* `TensorDtype`: only `:int64` and `:float32`, matching the “ONLY two types” call-out.

Tests reinforce all of this.

---

### 3.3 `TensorData`

* Aggressive casting matches the Python behaviour described:

  * `{:f, 64}` → `{:f, 32}` → `:float32`.
  * `{:s, 32}` → `{:s, 64}` → `:int64`.
  * All unsigned → `{ :s, 64 }`.
* `from_nx/1` uses `Nx.to_flat_list/1` and `Nx.shape/1` to produce `[data]` and `shape`.
* `to_nx/1` respects `shape: nil` as “1D tensor” and uses `TensorDtype.to_nx_type/1`.
* Tests cover:

  * dtype conversion,
  * multi-dimensional shapes,
  * unsupported dtype error,
  * roundtrip back to Nx.

Apart from the scalar shape nit noted above, this is exactly what your docs promise.

---

### 3.4 Image & text chunks, `ModelInput`

* `ImageChunk`:

  * Fields: `data`, `format`, `height`, `width`, `tokens`, `type`.
  * JSON encoding uses `"data"` and `"format"`, not `image_data`/`image_format`.
  * Tests explicitly assert field names and base64 encoding.
* `ImageAssetPointerChunk`:

  * Uses `location`, not `asset_id` or `url`.
  * JSON encoder uses that plus `format`, `height`, `width`, `tokens`, `type`.
  * Tests assert no stray fields and correct token count.
* `EncodedTextChunk` and `ModelInput`:

  * `from_ints/1`, `to_ints/1`, and `length/1` all match the Python semantics in `01_type_system`.
  * `ModelInput.length/1` correctly delegates to chunk `length/1` functions for text and images.
  * JSON encoding is only `chunks`, and tests validate the shape.

These align very nicely with the Phase-1 plan and the “CRITICAL: field names” section of docs.

---

### 3.5 `SampleRequest` and prompt_logprobs tri-state

* Struct defaults:

  ```elixir
  num_samples: 1,
  prompt_logprobs: nil,
  topk_prompt_logprobs: 0,
  type: "sample"
  ```

* Typespec uses `prompt_logprobs: boolean() | nil`, matching the `Optional[bool] = None` behaviour in Python.

* You explicitly **do not** strip `nil` on encode, and tests assert:

  * `nil` → key present with `null`.
  * `false` and `true` encode to booleans, not omitted.
  * All required fields are present.

That’s exactly what the docs emphasise as “CRITICAL” – this part is in great shape.

---

### 3.6 Future union types & `Tinkex.Error`

* Future types (`FuturePendingResponse`, `FutureCompletedResponse`, `FutureFailedResponse`, `TryAgainResponse`, `FutureRetrieveResponse`) are wired as per the union in the docs.
* `from_json/1` dispatches on `"type" => "try_again"` vs `"status"` string exactly as described.
* `Tinkex.Error`:

  * `from_response/2` parses `category` using `RequestErrorCategory.parse/1`.
  * `user_error?/1` matches the truth table in your docs: category `:user` or 4xx except 408/429 → user error.
  * `retryable?/1` is simply “not user_error?”, consistent with Python.

Tests cover the 4xx/5xx vs category matrix.

---

## 4. Tiny plan vs implementation deltas

These aren’t correctness issues, just “note them” items:

* You inlined the `ModelInputChunk` union type inside `ModelInput` rather than a separate `Tinkex.Types.ModelInputChunk` module. That’s fine, just a minor divergence from the doc’s file layout.
* Some response types mentioned in the plan (`CheckpointsListResponse`, `TrainingRunsResponse`, etc.) simply aren’t implemented yet – presumably intentional at this stage.

---

## TL;DR / Actionable TODOs

If I had to prioritize fixes:

1. **Fix `SampleResponse.topk_prompt_logprobs`**:

   * Either convert inner `[token_id, logprob]` lists into `{token_id, logprob}` tuples in `from_json/1` (and keep the typespec),
   * or adjust the typespec to reflect the actual nested list structure. Right now they disagree.

2. **Make `CreateModelRequest.lora_config` default to `%LoraConfig{}` instead of `nil`**:

   * And update the typespec to drop `| nil`. That aligns with the Python SDK and your own docs.

3. **Optionally align `TensorData.from_nx/1` scalar shape**:

   * Use `shape: nil` for scalars to match the “shape is optional and None for scalars” semantics from Python.

4. **Tighten typespecs vs `defstruct` defaults**:

   * For “required” fields like `tags`, `sdk_version`, `lora_config`, either give them defaults or extend the spec to allow `nil`.

5. **Tidy the `topk_prompt_logprobs` spec**:

   * Change to `[nil | [topk_entry()]] | nil` to express what you actually mean.

Everything else in the type system looks very close to both the Python design and your port docs, and your tests are already catching the important “wire shape” invariants (AdamParams, image fields, prompt_logprobs, tensor dtypes, error categories, etc.).
