Here’s what Tinker is actually doing with **NumPy** and **PyTorch**, plus a quick survey of other “heavy” libraries it pulls in. I’ll keep it focused on what matters for an Elixir port of a hosted API client.

---

## 1. High-level conclusion

For the core purpose of the SDK — **talk to a hosted Tinker API over HTTP** — the heavy ML libraries are:

* **Not required for basic usage**
* Used mainly as **convenience bridges** between:

  * User’s local tensors (torch / numpy) and
  * Tinker’s JSON-serializable wire format (`TensorData`, `Datum`, etc.)
* One advanced feature **does rely on PyTorch autograd**: a “custom loss function” training helper.

So if you port this to Elixir:

* You can implement the **core client** without NumPy or PyTorch equivalents at all.
* You only need Nx/Bumblebee/Axon equivalents if you also want:

  * Helpers that accept Nx tensors / gradients and convert them to the API’s tensor format.
  * The “custom loss” helper that computes gradients on the client side.

Details below.

---

## 2. NumPy usage

### 2.1 Where it’s imported

1. **`src/tinker/types/tensor_data.py`**

   * This is the main place where `numpy` is used.
2. Tests (not all shown in the snippet, but used there to validate behavior).

No NumPy usage in the HTTP client, CLI, or main SDK flow.

### 2.2 The `TensorData` type

`TensorData` (in `src/tinker/types/tensor_data.py`) is the core wire format for tensors:

* Fields:

  * `data: Union[List[int], List[float]]` – flattened numeric values
  * `dtype: Literal["int64", "float32"]`
  * `shape: Optional[List[int]]` – optional, for reconstructing array shape

This is designed to be **JSON-friendly** and API-agnostic.

NumPy comes in only for **conversion helpers**:

#### `TensorData.from_numpy(array) -> TensorData`

* Converts a `numpy.ndarray` to `TensorData`:

  * Determines `dtype` via `_convert_numpy_dtype_to_tensor(array.dtype)` (maps NumPy dtypes to `"int64"` / `"float32"`).
  * Flattens data: `array.flatten().tolist()`.
  * Stores original `shape` (list of ints).

There’s **no numerical computation** here; it’s just dtype & shape metadata plus flattening.

#### `TensorData.to_numpy() -> np.ndarray`

* Reconstructs a NumPy array from `TensorData`:

  * `numpy_dtype = _convert_tensor_dtype_to_numpy(self.dtype)`
  * `arr = np.array(self.data, dtype=numpy_dtype)`
  * If `self.shape` is set: `arr = arr.reshape(self.shape)`

Again, this is purely structural conversion.

#### Dtype mapping helpers

* `_convert_tensor_dtype_to_numpy(dtype: TensorDtype) -> np.dtype`
* `_convert_numpy_dtype_to_tensor(dtype: np.dtype) -> TensorDtype`

These functions map between:

* Tinker internal enum (`"int64" | "float32"`)
* NumPy dtypes (`np.int64`, `np.float32`, etc.)

No math beyond mapping and constructing arrays.

### 2.3 Where this matters for a port

For an Elixir client:

* Replace `numpy` with whatever you want (or nothing at all).
* The **essential logic** is:

  * Flatten nested numeric tensors to `list(number)` for JSON.
  * Track `dtype` as a small enum (`:int64 | :float32`).
  * Keep a `shape` for reconstruction.
* For Nx integration, you’d essentially implement:

  * `TensorData.from_nx(t)` and `to_nx(tensor_data)` doing the same flatten/reshape logic.

There are **no algorithms** here that depend on NumPy; it’s purely data marshaling.

---

## 3. PyTorch usage

PyTorch is used in three main places:

1. Conversion helpers around `TensorData`
2. Automatic conversion in `Datum` (training data wrapper)
3. A **custom loss training helper** in `TrainingClient` that uses PyTorch autograd

### 3.1 Optional dependency pattern

Both in `tensor_data.py` and `datum.py` you see:

```python
import torch  # type: ignore[import-not-found]
_HAVE_TORCH = True
...
_HAVE_TORCH = False
```

So:

* Import is wrapped in a try/except (truncated in the snippet, but implied by the flags).
* Most of the torch-dependent code checks `_HAVE_TORCH` before using it.

This means: **torch is optional for most of the library**, except where it’s used explicitly (like the custom loss helper).

### 3.2 `TensorData` ↔ torch conversions

In `src/tinker/types/tensor_data.py`:

#### `TensorData.from_torch(tensor: torch.Tensor) -> TensorData`

* Extracts:

  * `dtype` from tensor dtype via `_convert_torch_dtype_to_tensor`
  * `shape` from `tensor.shape`
  * `data` as a flattened `tensor.view(-1).tolist()` (or similar)

Again: **no heavy computation**, just structure & dtype mapping.

#### `TensorData.to_torch() -> torch.Tensor`

* Convert back:

  * `torch_dtype = _convert_tensor_dtype_to_torch(self.dtype)`
  * `tensor = torch.tensor(self.data, dtype=torch_dtype)`
  * Reshape if `self.shape` is set.

#### `_convert_torch_dtype_to_tensor` / `_convert_tensor_dtype_to_torch`

* Simple mapping between:

  * `torch.float32`, `torch.int64`, etc.
  * `"float32"` / `"int64"`.

So PyTorch here is only used as a **holder for tensor metadata and storage**, not for math.

### 3.3 `Datum` and automatic tensor conversion

In `src/tinker/types/datum.py`, `Datum` has:

* `loss_fn_inputs: Dict[str, TensorData]`
* `model_input: ModelInput`

A `model_validator` (`convert_tensors`) runs *before* model construction:

* It walks `loss_fn_inputs` values.
* For each value, `_maybe_convert_array` can:

  * If `_HAVE_TORCH` and value is `torch.Tensor`:

    * Convert via `TensorData.from_torch`.
  * If value is a NumPy array:

    * Convert via `TensorData.from_numpy`.
  * If value is a simple 1-D list of numbers:

    * Convert directly to TensorData, inferring dtype from the key (`_key_to_type` map).

So here PyTorch is just a **type to recognize and convert**, not a computation engine.

### 3.4 TrainingClient custom loss helper (real PyTorch usage)

The only place PyTorch is used for **actual computation** is in:

* `src/tinker/lib/public_interfaces/training_client.py`

There’s a type alias:

```python
CustomLossFnV1 = Callable[[List[types.Datum], List[Any]], Tuple[Any, Dict[str, float]]]
```

And a method roughly like `forward_backward_custom(...)` (name truncated but behavior is clear):

1. Performs a standard forward pass via `self.forward_async(...)`:

   * Gets back `ForwardBackwardOutput` objects with `loss_fn_outputs`.
   * Those contain `TensorData` entries, e.g. log probabilities.

2. Converts remote logprobs into PyTorch tensors:

   * For each loss output:

     * `logprob = torch.tensor(out["logprobs"].data).clone().detach().requires_grad_(True)`
   * Collects them into a list of `torch.Tensor` objects.
   * Also passes through the original `Datum` objects.

3. Calls the **user-provided custom loss function**:

   ```python
   custom_loss, custom_metrics = custom_loss_fn(data, logprobs)
   ```

   * `data`: original `Datum` list
   * `logprobs`: list of torch tensors with `requires_grad=True`

4. Computes gradients via PyTorch autograd:

   * Calls `custom_loss.backward()` or equivalent.
   * Reads gradient from `logprob.grad` for each logprob tensor.

5. Wraps gradients as weights back into API-level structures:

   * Builds new `Datum` objects (call this `linear_loss_data`), where:

     * `loss_fn_inputs["weights"] = -grad` (as a tensor or list, which gets converted to `TensorData` via the same machinery as before).

6. Calls a **second** API request using `forward_backward_async(linear_loss_data, "cross_entropy")` (or similar) to actually apply gradients on the remote side, now using the weighted logprobs as the loss.

7. Wraps the resulting future in `_CombinedAPIFuture` to attach `custom_metrics` into the final result.

So this feature:

* Uses PyTorch for:

  * Differentiating a scalar custom loss w.r.t. logprobs.
  * Basic tensor construction (`torch.tensor`, `clone`, `detach`, `requires_grad_`).
* Does **not** run any model forward pass locally. All real training is still remote.

For a port:

* The analog would be:

  * Represent the API-returned `TensorData` as Nx tensors.
  * Provide a custom loss callback that returns an Nx scalar.
  * Use Nx’s autodiff to compute gradients w.r.t. logprobs.
  * Feed gradients back into the API as weights, same as now.

If you don’t care about this feature:

* You can omit it and still support:

  * Plain forward/backward passes based on loss functions defined server-side.
  * Optimizer steps, save/load weights, etc.

---

## 4. Other notable “complex” third-party libraries

You asked specifically for NumPy and PyTorch; I’ll just briefly call out other non-stdlib libs that are *not* pydantic and might matter conceptually for a port.

### 4.1 `transformers` (Hugging Face)

Used in:

* `src/tinker/lib/public_interfaces/training_client.py` (via `_get_tokenizer` helper).
* There’s a `PreTrainedTokenizer` type, and `_get_tokenizer(model_id, holder)`:

  * Calls the Tinker API (`GetInfoRequest`) to get `model_data` for a given model ID.

  * Reads `model_data.model_name` / `model_data.tokenizer_id`.

  * Derives a HF tokenizer ID, with some heuristics:

    * If tokenizer_id is set, use it.
    * For certain models (e.g. Llama 3 variants), override to a special `baseten/Meta-Llama-3-tokenizer`.
    * Otherwise build `"{org}/{model}"` or just `model_name`.

  * Loads the tokenizer via Hugging Face (`AutoTokenizer.from_pretrained` or similar).

  * Returns a `PreTrainedTokenizer`.

Used for:

* Converting text to token IDs for `ModelInput`.
* This is entirely **client convenience**; the API itself just sees token IDs.

For an Elixir port:

* This interface would be an obvious target for integration with Bumblebee.

### 4.2 CLI / UX libs

* **Click** (`click`)

  * Used in `src/tinker/cli/*` to define CLI commands (`tinker run list`, `tinker checkpoint info`, etc.).
  * Purely presentation / developer tooling.

* **Rich** (`rich`)

  * Only used in `src/tinker/cli/output.py` to print tables to the terminal.

These are not involved in the core network / training logic.

### 4.3 HTTP / async / misc

* **httpx** (and `httpx_aiohttp` optional)

  * Underlies `BaseClient`, `AsyncAPIClient`, and all HTTP traffic.
  * For Elixir you’d obviously swap in HTTPoison/Finch/Mint/etc.

* **anyio**, **sniffio**, **distro**, etc.

  * Used for async compatibility and platform detection.
  * All “standard concerns” rather than ML-specific.

I’m skipping pydantic as requested.

---

## 5. Summary for a potential Elixir port

Putting it all together:

1. **Core SDK (hosted API client)**

   * Does **not** fundamentally depend on NumPy or PyTorch.
   * Talks JSON over HTTP and uses simple Python types + its own `TensorData` / `Datum` models.

2. **NumPy is used only for**:

   * Converting between `numpy.ndarray` and the wire format (`TensorData`).
   * No numerical algorithms, just flatten/reshape and dtype mapping.
   * Easy to replace with Nx or custom list/shape code.

3. **PyTorch is used for**:

   * Converting between `torch.Tensor` and `TensorData`.
   * An optional, higher-level **custom loss helper** that:

     * Uses PyTorch autograd on client-side logprobs.
     * Then calls the hosted API again using those gradients as weights.

4. **Transformers** is used for:

   * Loading Hugging Face tokenizers based on model metadata from the API.
   * Again, a convenience wrapper; the API just expects token IDs.

5. **Porting implications**:

   * You can cleanly separate:

     * **Core Elixir HTTP client** (no ML libs required).
     * Optional **Elixir-ML integration layer** that:

       * Converts Nx tensors ↔ Tinker’s `TensorData`-like struct.
       * Provides a “custom loss” helper using Nx autograd if you want parity with the PyTorch helper.
       * Integrates Bumblebee for tokenization instead of transformers.

If you tell me which parts of the Python surface you plan to expose in Elixir (plain client vs full training helper suite), I can map out a more explicit “must-port / nice-to-have / can-drop” list of features.
