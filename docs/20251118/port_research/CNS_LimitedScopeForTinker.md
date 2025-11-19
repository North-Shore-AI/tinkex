# 🧠 Analysis: CNS Tinker SDK Usage Summary

Based on your `train_claim_extractor.py` script, you are **only using the basic, core API features** of the CNS Tinker SDK, relying on the server to handle all complex machine learning computations.

This is a **lightweight implementation** that primarily uses the Tinker SDK as an **HTTP client** for remote training operations.

---

## ✅ What You **ARE** Using (Core API)

You are utilizing the standard API pattern, which focuses on client-server communication via simple, JSON-serializable data structures.

* **1. Basic HTTP Client:**
  * `service_client = tinker.ServiceClient()`
  * `training_client = service_client.create_lora_training_client(base_model=...)`
* **2. Standard Training Loop:**
  * `fwdbwd_future = training_client.forward_backward(datums, loss_fn="cross_entropy")`
  * `optim_future = training_client.optim_step(types.AdamParams(learning_rate=...))`
  * You use the **server-side `"cross_entropy"` loss function**.
* **3. Manual `TensorData` Construction:**
  * You build `types.Datum` and `tinker.TensorData` directly from **Python lists**, specifying `data`, `dtype`, and `shape`.
  * No automatic array/tensor conversion helpers are used.
* **4. Tokenizer Access:**
  * `tokenizer = training_client.get_tokenizer()` (Uses Hugging Face transformers).
* **5. Checkpointing:**
  * `training_client.save_weights_for_sampler(...)`

---

## 🚫 What You Are **NOT** Using (Advanced Features)

You can confidently **skip** the implementation of these complex features in your Elixir port.

| Feature | Tinker SDK Feature | Status |
|:---|:---|:---|
| **Custom Loss / Autograd** | `forward_backward_custom(...)` | ❌ Not used |
| **Client-side Gradients** | Computing gradients on the client | ❌ Not used |
| **NumPy Conversion** | `TensorData.from_numpy()`, `to_numpy()` | ❌ Not used |
| **PyTorch Conversion** | `TensorData.from_torch()`, `to_torch()` | ❌ Not used |
| **Auto Tensor Conversion** | Automatic conversion logic within `Datum` | ❌ Not used |

---

## ⚖️ "Weighted Loss" Clarification

Your citation validity penalty **is NOT** a custom loss function.

* **Process:** You compute and multiply per-token weights (which include your citation penalty) on the **client side**.
* **Tinker Usage:** You send these weights to Tinker as a tensor within `loss_fn_inputs`.
* **Server-Side:** Tinker's **standard server-side cross-entropy** uses these weights to compute the weighted loss.

This is a **standard feature (weighted cross-entropy)** and does not require the advanced custom loss/autograd machinery.

---

## 🛠️ Elixir Port Requirements

Your Elixir port for the CNS experiment should focus on the following priorities:

### P0 - Must Have (Core API Implementation)

* **HTTP Client:** Async request/response handling (e.g., Finch/Mint/HTTPoison) and a Future/Promise pattern for pipelined calls.
* **TensorData Struct:** Manual construction from Elixir lists (no Nx required for this).
  ```elixir
  defmodule Tinker.TensorData do
    @enforce_keys [:data, :dtype, :shape]
    defstruct [:data, :dtype, :shape]
    @type t :: %__MODULE__{
      data: list(integer()) | list(float()),
      dtype: :int64 | :float32,
      shape: list(non_neg_integer())
    }
  end
  ```
* **Training API Calls:** Implement clients for `create_lora_training_client/1`, `forward_backward/2` (specifically with `loss_fn: "cross_entropy"`), `optim_step/1`, and `save_weights_for_sampler/1`.
* **Data Types/Structs:** Implement basic structs for `Datum`, `ModelInput`, `AdamParams`, and response types.

### P1 - Nice to Have (Convenience)

* **Tokenizer Integration:** Integration with a library like **Bumblebee** to provide an analog to `get_tokenizer()`. This is optional if you choose to send pre-tokenized data.

### P3 - Don't Need (Skip)

* **Nx/PyTorch Conversion Helpers:** `TensorData.from_nx` or `TensorData.to_nx`.
* **Custom Loss/Autograd Features:** Skip all client-side ML logic.

---

Would you like me to outline the structure of the Elixir modules and functions based on these "Must Have" requirements?