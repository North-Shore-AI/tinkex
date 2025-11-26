# Python vs Tinkex: Custom Loss Implementation Comparison

This document provides a side-by-side comparison of custom loss implementation between the Python SDK and Tinkex.

---

## Architecture Comparison

| Aspect | Python | Tinkex |
|--------|--------|--------|
| Autodiff Engine | PyTorch autograd | Nx.Defn + EXLA |
| Tensor Library | torch.Tensor | Nx.Tensor |
| Async Model | asyncio (single event loop) | OTP (processes + Tasks) |
| Callback Type | `Callable[[List[Datum], List[Tensor]], Tuple[Tensor, Dict]]` | `fn(list(Nx.Tensor), list(map)) -> {Nx.Tensor, map}` |
| Gradient Method | Symbolic (autograd) | Numerical or Symbolic |

---

## Code Comparison

### Regularizer Definition

**Python**:
```python
def sparsity_penalty(data: List[types.Datum], logprobs_list: List[torch.Tensor]):
    l1_norms = [torch.norm(lp, p=1) for lp in logprobs_list]
    total_l1 = torch.sum(torch.stack(l1_norms))
    mean_l1 = total_l1 / len(logprobs_list)

    return mean_l1, {"l1_total": total_l1.item(), "l1_mean": mean_l1.item()}
```

**Tinkex**:
```elixir
def sparsity_penalty(logprobs_list, _data) do
  l1_norms = Enum.map(logprobs_list, fn lp ->
    Nx.sum(Nx.abs(lp))
  end)

  total_l1 = Enum.reduce(l1_norms, Nx.tensor(0.0), &Nx.add/2)
  mean_l1 = Nx.divide(total_l1, length(logprobs_list))

  metrics = %{
    "l1_total" => Nx.to_number(total_l1),
    "l1_mean" => Nx.to_number(mean_l1)
  }

  {mean_l1, metrics}
end
```

### Regularizer Configuration

**Python**:
```python
regularizers = [
    {"fn": topological_consistency, "weight": 0.1, "name": "topology"},
    {"fn": sparsity_penalty, "weight": 0.01, "name": "sparsity"}
]

future = await client.forward_backward_custom_async(data, regularizers=regularizers)
```

**Tinkex**:
```elixir
regularizers = [
  RegularizerSpec.sync("topology", 0.1, &topological_consistency/2),
  RegularizerSpec.sync("sparsity", 0.01, &sparsity_penalty/2)
]

{:ok, task} = TrainingClient.forward_backward_custom(client, data, regularizers: regularizers)
{:ok, result} = Task.await(task)
```

### Async Regularizer

**Python**:
```python
async def knowledge_consistency(data, logprobs_list):
    async with aiohttp.ClientSession() as session:
        claims = extract_claims(data)
        results = await asyncio.gather(*[verify_claim(session, c) for c in claims])

    penalties = [torch.tensor(0.0 if r.verified else r.confidence) for r in results]
    loss = torch.mean(torch.stack(penalties))

    return loss, {"verified_ratio": sum(1 for r in results if r.verified) / len(results)}
```

**Tinkex**:
```elixir
def knowledge_consistency(logprobs_list, data) do
  # Returns a Task (not the result directly)
  Task.async(fn ->
    claims = extract_claims(data)

    results =
      claims
      |> Enum.map(&verify_claim_async/1)
      |> Enum.map(&Task.await/1)

    penalties = Enum.map(results, fn
      %{verified: true} -> Nx.tensor(0.0)
      %{verified: false, confidence: c} -> Nx.tensor(c)
    end)

    loss = penalties |> Nx.stack() |> Nx.mean()
    verified_count = Enum.count(results, & &1.verified)

    {loss, %{"verified_ratio" => verified_count / length(results)}}
  end)
end

# Usage:
RegularizerSpec.async("kb", 0.05, &knowledge_consistency/2)
```

---

## Gradient Computation

### Python (PyTorch Autograd)

```python
# 1. Convert logprobs to tensors with gradient tracking
logprobs_list = []
for out in forward_result.loss_fn_outputs:
    logprob = torch.tensor(out["logprobs"].data).clone().detach().requires_grad_(True)
    logprobs_list.append(logprob)

# 2. Run user callback
loss, metrics = loss_fn(data, logprobs_list)

# 3. Compute gradients automatically
loss.backward()  # PyTorch magic

# 4. Extract gradients
grads = [logprob.grad for logprob in logprobs_list]
```

### Tinkex (Nx Options)

**Option A: Numerical Gradient (works for any function)**
```elixir
def compute_numerical_gradients(logprobs_list, loss_fn, epsilon \\ 1.0e-5) do
  Enum.map(logprobs_list, fn logprob ->
    shape = Nx.shape(logprob)
    flat_size = Tuple.product(shape)

    grads =
      for i <- 0..(flat_size - 1) do
        plus = perturb_at(logprob, i, epsilon)
        minus = perturb_at(logprob, i, -epsilon)

        {loss_plus, _} = loss_fn.([plus], nil)
        {loss_minus, _} = loss_fn.([minus], nil)

        (Nx.to_number(loss_plus) - Nx.to_number(loss_minus)) / (2 * epsilon)
      end

    Nx.tensor(grads) |> Nx.reshape(shape)
  end)
end
```

**Option B: Symbolic Gradient (requires defn-compatible function)**
```elixir
import Nx.Defn

# User must define regularizer as defn
defn my_loss(logprobs) do
  Nx.sum(Nx.abs(logprobs))
end

# Then we can use Nx.Defn.grad
def compute_symbolic_gradient(logprobs, loss_defn) do
  grad_fn = Nx.Defn.grad(loss_defn)
  grad_fn.(logprobs)
end
```

**Option C: User-Provided Gradient**
```elixir
# User provides both loss and gradient function
RegularizerSpec.with_grad("my_reg", 0.1,
  &my_loss/2,       # loss function
  &my_loss_grad/2   # gradient function
)
```

---

## Telemetry Output

Both produce identical structured telemetry:

```json
{
  "loss_total": 2.847,
  "base_loss": {
    "value": 2.5,
    "custom": {"perplexity": 12.18}
  },
  "regularizers": {
    "topology": {
      "value": 1.23,
      "weight": 0.1,
      "contribution": 0.123,
      "custom": {"beta_1_mean": 3.2}
    },
    "sparsity": {
      "value": 22.4,
      "weight": 0.01,
      "contribution": 0.224,
      "custom": {"l1_norm": 22.4}
    }
  },
  "regularizer_total": 0.347
}
```

---

## Key Differences

### 1. Gradient Computation

| Python | Tinkex |
|--------|--------|
| PyTorch autograd is automatic | Must choose gradient method |
| Always symbolic (exact) | Numerical by default (approximate) |
| Any Python function works | Symbolic requires `defn` |
| Fast for complex graphs | Numerical is O(n) slower |

### 2. Async Model

| Python | Tinkex |
|--------|--------|
| `async def` + `await` | `Task.async` + `Task.await` |
| Single event loop | Process per task |
| `asyncio.gather` for parallel | `Enum.map(&Task.async/1)` |
| Cancellation via `asyncio.CancelledError` | `Task.shutdown` |

### 3. Error Handling

| Python | Tinkex |
|--------|--------|
| `try/except` | `try/rescue` or `{:ok, _}/{:error, _}` |
| Raise on gradient failure | Return `{:error, reason}` |
| Stack traces in exceptions | Erlang-style error tuples |

### 4. Type System

| Python | Tinkex |
|--------|--------|
| `TypedDict` for regularizer spec | `defstruct` with `@type` |
| Runtime type checking (optional) | Dialyzer static analysis |
| `Union[Callable, Awaitable]` for async | Separate `async: boolean` field |

---

## Migration Guide: Python → Tinkex

### Step 1: Convert Regularizer Function

Python:
```python
def my_reg(data, logprobs_list):
    loss = compute_loss(logprobs_list)
    return loss, {"my_metric": loss.item()}
```

Tinkex:
```elixir
def my_reg(logprobs_list, data) do  # Note: arg order swapped
  loss = compute_loss(logprobs_list)
  {loss, %{"my_metric" => Nx.to_number(loss)}}
end
```

### Step 2: Convert Regularizer Config

Python:
```python
{"fn": my_reg, "weight": 0.1, "name": "my_reg"}
```

Tinkex:
```elixir
RegularizerSpec.sync("my_reg", 0.1, &my_reg/2)
```

### Step 3: Convert Training Loop

Python:
```python
result = await client.forward_backward_custom_async(data, regularizers=regularizers)
```

Tinkex:
```elixir
{:ok, task} = TrainingClient.forward_backward_custom(client, data, regularizers: regularizers)
{:ok, result} = Task.await(task)
```

### Step 4: Convert Tensor Operations

| Python (PyTorch) | Tinkex (Nx) |
|------------------|-------------|
| `torch.tensor([1,2,3])` | `Nx.tensor([1,2,3])` |
| `torch.sum(x)` | `Nx.sum(x)` |
| `torch.mean(x)` | `Nx.mean(x)` |
| `torch.abs(x)` | `Nx.abs(x)` |
| `torch.norm(x, p=1)` | `Nx.sum(Nx.abs(x))` |
| `x.item()` | `Nx.to_number(x)` |
| `torch.stack([...])` | `Nx.stack([...])` |
| `x.backward()` | `Nx.Defn.grad(fn)` or numerical |

---

## When to Use Each

### Use Python When:

- You need complex autodiff (nested gradients, higher-order)
- You're using PyTorch-specific libraries (GUDHI bindings, etc.)
- You want symbolic gradients for arbitrary functions
- You're prototyping and want maximum flexibility

### Use Tinkex When:

- You're building production Elixir systems
- You want OTP supervision and fault tolerance
- Your regularizers are numerically simple (L1, L2, etc.)
- You can express critical regularizers as `defn` functions
- You want to avoid Python in your deployment

### Hybrid Approach:

- Use Python for research/prototyping
- Port stable regularizers to Tinkex for production
- Keep complex topology/logic regularizers in Python
