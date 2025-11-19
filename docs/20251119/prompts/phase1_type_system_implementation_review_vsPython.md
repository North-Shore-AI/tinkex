Here’s what I see when I line up the original Python type system against your Elixir port.

I’ll start with the serious “wire mismatch” issues (things that will send different JSON than the Python SDK), then softer type / API design mismatches, then a quick list of what already looks solid.

---

## 1. High-risk wire-format mismatches

These are places where the JSON your Elixir types produce does **not** match the Python types you said you were mirroring.

### 1.1 `LoadWeightsRequest` / `SaveWeightsRequest` / `SaveWeightsForSamplerRequest`

**Python** (from `tinker/types/load_weights_request.py`, `save_weights_request.py`, `save_weights_for_sampler_request.py`):

All three use a field named **`path`**:

```py
class LoadWeightsRequest(StrictBase):
    model_id: ModelID
    path: str
    seq_id: Optional[int] = None
    type: Literal["load_weights"] = "load_weights"
```

```py
class SaveWeightsRequest(StrictBase):
    model_id: ModelID
    path: Optional[str] = None
    seq_id: Optional[int] = None
    type: Literal["save_weights"] = "save_weights"
```

```py
class SaveWeightsForSamplerRequest(StrictBase):
    model_id: ModelID
    path: Optional[str] = None
    sampling_session_seq_id: Optional[int] = None
    seq_id: Optional[int] = None
    type: Literal["save_weights_for_sampler"] = "save_weights_for_sampler"
```

**Elixir**:

```elixir
defmodule Tinkex.Types.LoadWeightsRequest do
  @derive {Jason.Encoder, only: [:model_id, :checkpoint_name, :seq_id]}
  defstruct [:model_id, :checkpoint_name, :seq_id]
end
```

```elixir
defmodule Tinkex.Types.SaveWeightsRequest do
  @derive {Jason.Encoder, only: [:model_id, :checkpoint_name, :seq_id]}
  defstruct [:model_id, :checkpoint_name, :seq_id]
end
```

```elixir
defmodule Tinkex.Types.SaveWeightsForSamplerRequest do
  @derive {Jason.Encoder, only: [:model_id, :checkpoint_name, :seq_id]}
  defstruct [:model_id, :checkpoint_name, :seq_id]
end
```

**Problems:**

1. Field name is `checkpoint_name` on the Elixir side, but `path` in Python and (per the docs) in the backend schema.

   * JSON you send will look like:

     ```json
     {"model_id": "...", "checkpoint_name": "...", "seq_id": 1}
     ```

     instead of:

     ```json
     {"model_id": "...", "path": "tinker://...", "seq_id": 1}
     ```
2. `SaveWeightsForSamplerRequest` is also missing **`sampling_session_seq_id`** and `type`, which exist in Python.

👉 **Recommendation**

* Rename the field back to `path` on the wire, even if you expose a more ergonomic `checkpoint_name` internally.

  * Easiest: keep `defstruct [:model_id, :path, :seq_id]`, and if you want a higher-level “checkpoint name” concept, compute `path` in the client before building the struct.
* Extend `SaveWeightsForSamplerRequest` to include `sampling_session_seq_id` and (optionally) `type` for full parity.

---

### 1.2 `CreateSessionRequest`

**Python** (`create_session_request.py`):

```py
class CreateSessionRequest(StrictBase):
    tags: list[str]
    user_metadata: dict[str, Any] | None
    sdk_version: str
    type: Literal["create_session"] = "create_session"
```

**Elixir**:

```elixir
defmodule Tinkex.Types.CreateSessionRequest do
  @derive {Jason.Encoder, only: [:user_metadata]}
  defstruct [:user_metadata]

  @type t :: %__MODULE__{
          user_metadata: map() | nil
        }
end
```

**Problems:**

* You’re only encoding `user_metadata`.
* Missing required Python fields:

  * `tags: list[str]`
  * `sdk_version: str`
  * `type: "create_session"` discriminator

Unless you’re injecting these somewhere else before hitting the API, the JSON body from Elixir is not equivalent to the Python SDK.

👉 **Recommendation**

Change the struct to include the missing fields and encode them:

```elixir
@derive {Jason.Encoder, only: [:tags, :user_metadata, :sdk_version, :type]}
defstruct [
  :tags,
  :user_metadata,
  :sdk_version,
  type: "create_session"
]

@type t :: %__MODULE__{
        tags: [String.t()],
        user_metadata: map() | nil,
        sdk_version: String.t(),
        type: String.t()
      }
```

You can still provide helpers that fill `tags` and `sdk_version` from config, but the type should mirror the Python wire shape.

---

### 1.3 `CreateSamplingSessionRequest`

**Python** (`create_sampling_session_request.py`):

```py
class CreateSamplingSessionRequest(StrictBase):
    session_id: str
    sampling_session_seq_id: int
    base_model: Optional[str] = None
    model_path: Optional[str] = None
    type: Literal["create_sampling_session"] = "create_sampling_session"
```

**Elixir**:

```elixir
defmodule Tinkex.Types.CreateSamplingSessionRequest do
  @derive {Jason.Encoder, only: [:base_model, :model_path, :user_metadata]}
  defstruct [:base_model, :model_path, :user_metadata]

  @type t :: %__MODULE__{
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          user_metadata: map() | nil
        }
end
```

**Problems:**

* Missing required fields: `session_id`, `sampling_session_seq_id`, and `type`.
* Added `user_metadata`, which is **not** present in the Python type.

  * Given the backend also uses Pydantic `StrictBase` for server request validation, unknown fields are very likely to cause 422s if you send them directly to the Tinker API.

👉 **Recommendation**

* Align the struct field set to the Python one:

```elixir
@derive {Jason.Encoder,
         only: [:session_id, :sampling_session_seq_id, :base_model, :model_path, :type]}
defstruct [
  :session_id,
  :sampling_session_seq_id,
  :base_model,
  :model_path,
  type: "create_sampling_session"
]
```

* If you truly need `user_metadata` at sampling-session level, you’ll need a server change; right now it’s a divergence.

---

### 1.4 `CreateModelRequest`

**Python** (`create_model_request.py`):

```py
class CreateModelRequest(StrictBase):
    session_id: str
    model_seq_id: int
    base_model: str
    user_metadata: Optional[dict[str, Any]] = None
    lora_config: Optional[LoraConfig] = None
    type: Literal["create_model"] = "create_model"
```

**Elixir**:

```elixir
@derive {Jason.Encoder, only: [:session_id, :model_seq_id, :base_model, :lora_config, :user_metadata]}
defstruct [:session_id, :model_seq_id, :base_model, :lora_config, :user_metadata]

@type t :: %__MODULE__{
        session_id: String.t(),
        model_seq_id: integer(),
        base_model: String.t(),
        lora_config: LoraConfig.t(),
        user_metadata: map() | nil
      }
```

**Problems:**

1. Missing `type: "create_model"` field in the struct/encoding.
2. `lora_config` is **optional** in Python but non-optional in your typespec:

   * `defstruct` default is `nil`, but the spec says `LoraConfig.t()`, not `LoraConfig.t() | nil`.
   * `@derive` includes `:lora_config`, so you’ll emit `"lora_config": null` when you omit it.

👉 **Recommendation**

* Add the `type` field and relax the `lora_config` typespec:

```elixir
@derive {Jason.Encoder,
         only: [:session_id, :model_seq_id, :base_model, :lora_config, :user_metadata, :type]}
defstruct [:session_id, :model_seq_id, :base_model, :lora_config, :user_metadata, type: "create_model"]

@type t :: %__MODULE__{
        session_id: String.t(),
        model_seq_id: integer(),
        base_model: String.t(),
        lora_config: LoraConfig.t() | nil,
        user_metadata: map() | nil,
        type: String.t()
      }
```

---

### 1.5 `OptimStepResponse`

**Python** (`optim_step_response.py`):

```py
class OptimStepResponse(BaseModel):
    metrics: Optional[Dict[str, float]] = None
    """Optimization step metrics as key-value pairs"""
```

**Elixir**:

```elixir
defmodule Tinkex.Types.OptimStepResponse do
  @moduledoc """
  Response from optimizer step request.

  Mirrors Python tinker.types.OptimStepResponse.
  """

  defstruct [:success]

  @type t :: %__MODULE__{
          success: boolean()
        }

  @doc """
  Parse an optim step response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      success: Map.get(json, "success", true)
    }
  end
end
```

**Problems:**

* Python response has **`metrics`**, not `success`.
* There is no `success` field in the Python type at all.
* You are discarding potentially important optimizer metrics.

👉 **Recommendation**

Make this match the Python definition:

```elixir
defstruct [:metrics]

@type t :: %__MODULE__{
        metrics: %{String.t() => float()} | nil
      }

@spec from_json(map()) :: t()
def from_json(json) do
  %__MODULE__{
    metrics: json["metrics"] || nil
  }
end
```

If you want a convenience notion of `success`, you can define a helper function:

```elixir
@spec success?(t()) :: boolean()
def success?(_), do: true  # or inspect metrics if needed
```

…but the on-wire shape should stick to `metrics`.

---

### 1.6 Response / union shapes for Futures

Python defines:

* `TryAgainResponse`:

  ```py
  class TryAgainResponse(BaseModel):
      type: Literal["try_again"] = "try_again"
      request_id: str
      queue_state: Literal["active", "paused_capacity", "paused_rate_limit"]
  ```

* `RequestFailedResponse`:

  ```py
  class RequestFailedResponse(BaseModel):
      error: str
      category: RequestErrorCategory
  ```

* `FutureRetrieveResponse: TypeAlias = Union[...]` (full union content truncated, but we can see at least `TryAgainResponse` + failure case via `RequestFailedResponse`, plus the “real” result type).

Your Elixir side defines **brand-new wrappers**:

```elixir
defmodule Tinkex.Types.FuturePendingResponse do
  defstruct status: "pending"
end

defmodule Tinkex.Types.FutureCompletedResponse do
  defstruct [:status, :result]
end

defmodule Tinkex.Types.FutureFailedResponse do
  defstruct [:status, :error]
end

defmodule Tinkex.Types.TryAgainResponse do
  defstruct [:type, :request_id, :queue_state, :retry_after_ms]
end

defmodule Tinkex.Types.FutureRetrieveResponse do
  @type t ::
          FuturePendingResponse.t()
          | FutureCompletedResponse.t()
          | FutureFailedResponse.t()
          | TryAgainResponse.t()

  @spec from_json(map()) :: t()
  def from_json(%{"type" => "try_again"} = json), do: %TryAgainResponse{...}
  def from_json(%{"status" => "pending"}), do: %FuturePendingResponse{}
  ...
end
```

**Potential issues:**

* I don’t see any matching `FuturePendingResponse`/`FutureCompletedResponse`/`FutureFailedResponse` types in the Python type system you pasted. Python seems to treat:

  * `"type": "try_again"` as the “backpressure, please poll again” case.
  * `"error"` + `"category"` (via `RequestFailedResponse`) as failures.
  * Otherwise, it just returns the *actual* result model (`ForwardBackwardOutput`, `SampleResponse`, etc).
* You’ve invented a top-level `status` wrapper (`"status": "pending"/"completed"/"failed"`) that is not described in the Python types.

This may be intentional (if you’ve already added an extra “future status” wrapper layer on the server), but as written it does **not** mirror the original type system.

👉 **Recommendation**

* Double-check the actual `future.retrieve` JSON responses:

  * If they really are `{status, result}` wrappers, then the Python type alias must have been extended and your snippets are just truncated; in that case, update your docs to reflect that divergence from the earlier spec.
  * If the real responses are `Union[TryAgainResponse, RequestFailedResponse, ResultModel]` **without** a `status` field, then your Elixir union needs to be simplified to match that and you should lean on HTTP status + `RequestFailedResponse` for failures rather than your own `status` wrapper.

At minimum, this is an area where the Elixir code clearly doesn’t follow the *visible* Python type definitions.

---

## 2. Type-accuracy / API-surface issues (less severe, but worth fixing)

These aren’t guaranteed wire breaks, but they’re either type specs that don’t match runtime, or subtle semantic differences.

### 2.1 `SampleResponse.topk_prompt_logprobs` typespec

**Python**:

```py
topk_prompt_logprobs: Optional[list[Optional[list[tuple[int, float]]]]] = None
```

**Elixir**:

```elixir
defstruct [:sequences, :prompt_logprobs, :topk_prompt_logprobs, type: "sample"]

@type t :: %__MODULE__{
        sequences: [SampledSequence.t()],
        prompt_logprobs: [float() | nil] | nil,
        topk_prompt_logprobs: map() | nil,
        type: String.t()
      }

def from_json(json) do
  %__MODULE__{
    sequences: ...,
    prompt_logprobs: json["prompt_logprobs"],
    topk_prompt_logprobs: json["topk_prompt_logprobs"],
    type: json["type"] || "sample"
  }
end
```

Runtime, `json["topk_prompt_logprobs"]` is going to be a **list of lists of `[token_id, logprob]` tuples (or `nil`)**, not a map.

👉 **Recommendation**

Fix the typespec:

```elixir
@type topk_entry :: {integer(), float()}
@type t :: %__MODULE__{
        sequences: [SampledSequence.t()],
        prompt_logprobs: [float() | nil] | nil,
        topk_prompt_logprobs: [[topk_entry()] | nil] | nil,
        type: String.t()
      }
```

You can keep `from_json` exactly as is; it’s the spec that’s wrong.

---

### 2.2 `SampledSequence.stop_reason` optional vs required

**Python**:

```py
class SampledSequence(BaseModel):
    stop_reason: StopReason
    tokens: List[int]
    logprobs: Optional[List[float]] = None
```

**Elixir**:

```elixir
@type t :: %__MODULE__{
        tokens: [integer()],
        logprobs: [float()] | nil,
        stop_reason: StopReason.t() | nil
      }

def from_json(json) do
  %__MODULE__{
    tokens: json["tokens"],
    logprobs: json["logprobs"],
    stop_reason: StopReason.parse(json["stop_reason"])
  }
end
```

Here you’re allowing `stop_reason` to be `nil` (for unknown strings / missing fields) whereas the original type system treats it as required.

This is probably a **deliberate forward-compatibility choice**, and it’s fine as long as you’re aware it’s a divergence from the stricter Python type.

(If you want to more closely mirror Python, you could keep the typespec as `StopReason.t()` and explicitly raise when `parse/1` returns `nil`.)

---

### 2.3 `LoraConfig` default for `rank` and optionality

**Python** (`lora_config.py`):

```py
class LoraConfig(StrictBase):
    rank: int
    seed: Optional[int] = None
    train_unembed: bool = True
    train_mlp: bool = True
    train_attn: bool = True
```

`rank` has **no default**, so in Python it’s required whenever `lora_config` is present.

**Elixir**:

```elixir
defstruct [
  rank: 32,
  seed: nil,
  train_mlp: true,
  train_attn: true,
  train_unembed: true
]

@type t :: %__MODULE__{
        rank: pos_integer(),
        seed: integer() | nil,
        train_mlp: boolean(),
        train_attn: boolean(),
        train_unembed: boolean()
      }
```

Differences:

* You’ve given `rank` a default of `32`. That’s probably a reasonable choice (a common LoRA rank), but it’s **stricter** than Python’s type system: in Python the “required field” requirement is enforced at the *client*, not the server.
* Combined with the `CreateModelRequest` issue (where `lora_config` is non-optional in your spec), you’re effectively saying “if you pass a `lora_config` at all, rank will default to 32”.

This is safe, but it’s a behavior difference vs Python (where omitting `rank` is a client error).

---

### 2.4 `CreateModelRequest.lora_config` typespec vs reality

As noted above:

```elixir
@type t :: %__MODULE__{
        ...,
        lora_config: LoraConfig.t(),
        ...
      }
```

but `defstruct` uses `:lora_config` with no default, so at runtime it **will** be `nil` in many cases (no LoRA training), and you include it in JSON via `@derive`.

So:

* **Runtime**: `lora_config` is often `nil`.
* **Typespec**: pretends it’s always a `%LoraConfig{}`.

👉 Just change that spec to `LoraConfig.t() | nil` to match the original optionality and your runtime behavior.

---

### 2.5 `Tinkex.Error.from_response/2` vs `RequestFailedResponse`

Python has a `RequestFailedResponse` type with fields:

```py
class RequestFailedResponse(BaseModel):
    error: str
    category: RequestErrorCategory
```

Your Elixir `Error.from_response/2` (compressed here) does:

```elixir
def from_response(status, body) when is_map(body) do
  category =
    case body["category"] do
      nil -> nil
      cat -> RequestErrorCategory.parse(cat)
    end

  %__MODULE__{
    message: body["message"] || body["error"] || "Request failed",
    type: :request_failed,
    status: status,
    category: category,
    data: body,
    retry_after_ms: body["retry_after_ms"]
  }
end
```

Differences:

* Python type doesn’t mention `message` or `retry_after_ms` fields; it’s just `error` + `category`.
* You’re gracefully handling both shapes (which is good!), but the doc comment “mirrors Python…” is slightly misleading; this is more of a superset.

Not a bug, but worth being explicit in docs: your `Error` struct is a **richer** representation than `RequestFailedResponse`, not an exact mirror.

---

## 3. Things that actually look very good / aligned

To balance the nitpicks: these are places where your Elixir implementation matches the Python types quite closely, including weird edge semantics:

* **`AdamParams`**

  * Defaults: `learning_rate = 0.0001`, `beta1=0.9`, `beta2=0.95`, `eps=1e-12` — exactly match Python.
  * JSON keys use `eps` (not `epsilon`), as the tests assert.

* **`SamplingParams`**

  * Correct optional fields and defaults:

    * `max_tokens: Optional[int]`
    * `seed: Optional[int]`
    * `stop: Union[str, Sequence[str], Sequence[int], None]`
    * `temperature=1.0`, `top_k=-1`, `top_p=1.0`.

* **`SampleRequest`**

  * Fields and semantics line up very well:

    * `num_samples`, `prompt`, `sampling_params`, `base_model`, `model_path`, `sampling_session_id`, `seq_id`, `prompt_logprobs`, `topk_prompt_logprobs`, `type: "sample"`.
  * The tri-state `prompt_logprobs :: boolean | nil` is correct and tests verify `nil` → `null` in JSON.

* **`EncodedTextChunk`, `ImageChunk`, `ImageAssetPointerChunk`**

  * Field names and types mirror the Python models.
  * Custom `Jason.Encoder` implementations ensure:

    * `format` is serialized as `"png"`/`"jpeg"`, not atoms.
    * `data` is base64 string, matching Python’s `field_serializer`.

* **`ModelInput`**

  * `from_ints/1`, `to_ints/1`, `length/1` follow the same semantics as Python’s `ModelInput` helpers.
  * The length calculation correctly delegates to each chunk’s `length/1`, including images.

* **`TensorDtype` and `TensorData`**

  * Only `int64` and `float32` are permitted, matching `TensorDtype` in Python.
  * Aggressive casting from Nx types mirrors the Python `from_numpy`/`from_torch` behavior:

    * `float64 → float32`
    * `int32 → int64`
    * unsigned → `int64`
  * Tests exercise these conversions and the JSON encoding.

* **`LossFnType`, `StopReason`, `RequestErrorCategory`**

  * Wire strings are correct.
  * You’ve made parsing case-insensitive for `RequestErrorCategory`, which is a nice defensive improvement.

* **`Datum`**

  * The `new/1` helper converts:

    * `Nx.Tensor` → `TensorData`
    * lists → `TensorData` with inferred dtype/shape
  * This closely parallels the Python model validator that converts `torch`, `numpy`, and lists to `TensorData`.

---

## 4. Suggested “fix list”

If you want a concrete checklist of things to adjust next:

1. **Rename and align weight request types**

   * `LoadWeightsRequest`, `SaveWeightsRequest`, `SaveWeightsForSamplerRequest`:

     * Rename `checkpoint_name` → `path`.
     * Add `sampling_session_seq_id` and `type` to `SaveWeightsForSamplerRequest`.

2. **Fill out missing fields on session-related requests**

   * `CreateSessionRequest`:

     * Add `tags :: [String.t()]`, `sdk_version :: String.t()`, `type :: "create_session"`.
   * `CreateSamplingSessionRequest`:

     * Add `session_id`, `sampling_session_seq_id`, `type :: "create_sampling_session"`.
     * Consider **dropping** `user_metadata` here unless the backend actually supports it.

3. **Fix `CreateModelRequest` parity**

   * Add `type :: "create_model"`.
   * Make `lora_config :: LoraConfig.t() | nil`.

4. **Re-align `OptimStepResponse`**

   * Replace `success :: boolean()` with `metrics :: map() | nil` to match Python.
   * Provide a helper `success?/1` if you want a convenience flag.

5. **Fix `SampleResponse` typespec**

   * Update `topk_prompt_logprobs` spec from `map() | nil` to the nested list/tuple structure the API actually returns.

6. **Review the Futures response modeling**

   * Confirm whether the backend really returns `{status, result}` wrappers for futures.

     * If yes → update your docs to reflect that extended shape.
     * If no → simplify `FutureRetrieveResponse` and `from_json/1` to match the Python union (TryAgain + RequestFailedResponse + real result).

7. **Minor type/spec cleanups**

   * Relax `CreateModelRequest.lora_config` typespec.
   * Decide whether you want `SampledSequence.stop_reason` to be strictly non-nil (mirror Python) or explicitly optional for forward compatibility (just make that choice deliberate and documented).

---

If you’d like, next step I can draft patched Elixir modules for the obviously off ones (`CreateSessionRequest`, `CreateSamplingSessionRequest`, the *Weights* requests, `OptimStepResponse`, `SampleResponse`) so you can just drop them in and re-run your tests.
