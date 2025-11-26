# Tinkex Custom Loss Implementation Checklist

---

## Phase 1: EXLA Dependency

- [ ] **mix.exs**: Add `{:exla, "~> 0.7"}`
- [ ] **config/config.exs**: Configure EXLA backend
  ```elixir
  config :nx, :default_backend, EXLA.Backend
  config :exla, :default_client, :host
  ```
- [ ] **mix.lock**: Update dependencies
- [ ] **CI**: Ensure EXLA compiles in CI environment
- [ ] **Tests**: Verify existing tests still pass

---

## Phase 2: Expose Forward API

### Files to Modify

- [ ] **lib/tinkex/training_client.ex**
  - [ ] Add `forward/4` public function (line ~66)
  - [ ] Add `handle_call({:forward, ...}, ...)` handler
  - [ ] Add `send_forward_request/5` helper
  - [ ] Add `await_forward_results/2` helper

- [ ] **lib/tinkex/api/training.ex**
  - Already has `forward/2` at line 73-81 (no changes needed)

### Tests

- [ ] **test/tinkex/training_client_test.exs**
  - [ ] Add test for `forward/4` returns logprobs
  - [ ] Add test for forward handles chunking

---

## Phase 3: Core Types

### New Files

- [ ] **lib/tinkex/custom_loss/regularizer_spec.ex**
  ```elixir
  defstruct [:name, :weight, :fn, async: false]
  @type t :: %__MODULE__{...}
  def sync(name, weight, fun)
  def async(name, weight, fun)
  ```

- [ ] **lib/tinkex/custom_loss/runner.ex**
  ```elixir
  def run_regularizers(regularizers, logprobs, data)
  defp run_sync(reg, logprobs, data)
  defp run_async(reg, logprobs, data)
  ```

- [ ] **lib/tinkex/custom_loss/grad_computer.ex**
  ```elixir
  def compute_gradients(logprobs, reg_results, base_result, opts)
  def compute_numerical_gradients(...)
  def compute_symbolic_gradients(...)
  defp perturb_at(tensor, index, delta)
  defp build_telemetry(...)
  ```

### Tests

- [ ] **test/tinkex/custom_loss/regularizer_spec_test.exs**
- [ ] **test/tinkex/custom_loss/runner_test.exs**
- [ ] **test/tinkex/custom_loss/grad_computer_test.exs**
  - [ ] Test numerical gradients for sum
  - [ ] Test numerical gradients for mean
  - [ ] Test numerical gradients for weighted combination
  - [ ] Test symbolic gradients (if EXLA available)

---

## Phase 4: TrainingClient Integration

### Files to Modify

- [ ] **lib/tinkex/training_client.ex**
  - [ ] Add `forward_backward_custom/3` public function
  - [ ] Add `handle_call({:forward_backward_custom, ...}, ...)` handler
  - [ ] Add `extract_logprobs_as_nx/1` helper
  - [ ] Add `linearize_gradients/2` helper

### Tests

- [ ] **test/tinkex/training_client_custom_loss_test.exs**
  - [ ] Test single sync regularizer
  - [ ] Test multiple regularizers
  - [ ] Test async regularizer
  - [ ] Test mixed sync/async
  - [ ] Test base_loss_fn only
  - [ ] Test regularizers + base_loss_fn
  - [ ] Test error on no regularizers or base_loss_fn
  - [ ] Test telemetry structure

---

## Phase 5: Telemetry

### Files to Modify

- [ ] **lib/tinkex/telemetry.ex**
  - [ ] Add `emit_regularizer_metrics/3`
  - [ ] Add `emit_gradient_computation/3`

### New Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:tinkex, :training, :custom_loss, :regularizer]` | `%{value, weight, contribution}` | `%{regularizer: name}` |
| `[:tinkex, :training, :custom_loss, :gradient]` | `%{duration_ms}` | `%{method: :numerical/:symbolic}` |

---

## Phase 6: Documentation

- [ ] **lib/tinkex/custom_loss.ex** - Module docs with overview
- [ ] **docs/guides/custom_loss.md** - Guide with examples
- [ ] **README.md** - Add custom loss to features list
- [ ] **CHANGELOG.md** - Document v2.0 custom loss feature

---

## Estimated Effort

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| 1. EXLA | 2-4 hours | None |
| 2. Forward API | 4-6 hours | Phase 1 |
| 3. Core Types | 8-12 hours | Phase 1 |
| 4. Integration | 8-12 hours | Phase 2, 3 |
| 5. Telemetry | 2-4 hours | Phase 4 |
| 6. Documentation | 4-6 hours | Phase 4 |
| **Total** | **~30-44 hours** | |

---

## Key Implementation Notes

### Numerical Gradient Accuracy

```elixir
# Use central difference for O(ε²) error
∂f/∂x ≈ (f(x + ε) - f(x - ε)) / (2ε)

# Choose ε carefully
epsilon = 1.0e-5  # Balance: too small → floating point error, too large → approximation error
```

### Async Regularizer Handling

```elixir
# Use Task.Supervisor for fault isolation
Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn ->
  run_expensive_regularizer(...)
end)

# Timeout handling
Task.await(task, timeout)  # Let it crash on timeout, or...
Task.yield(task, timeout) || Task.shutdown(task)  # Graceful fallback
```

### Memory Considerations

For large batches, gradients can be memory-intensive:
- Logprobs: `batch_size × seq_len × vocab_size` floats
- Gradients: Same size

Consider:
- Stream processing for very large batches
- Gradient checkpointing (recompute rather than store)
- Batched numerical gradient computation

---

## Verification Checklist

Before marking complete:

- [ ] All tests pass
- [ ] Dialyzer clean
- [ ] Credo clean
- [ ] Documentation complete
- [ ] Examples work end-to-end
- [ ] Telemetry emits correctly
- [ ] Backward compat maintained for existing TrainingClient usage
