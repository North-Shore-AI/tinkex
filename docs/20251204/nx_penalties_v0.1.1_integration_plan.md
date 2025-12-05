# NxPenalties v0.1.1 Integration Plan

**Date**: 2024-12-04
**Scope**: Update tinkex regularizer adapters for nx_penalties v0.1.1 compatibility
**Dependency**: `{:nx_penalties, "~> 0.1.1"}` (already updated in mix.exs)

---

## Summary

NxPenalties v0.1.1 introduces several new features that tinkex adapters should expose:

| Feature | NxPenalties Module | Tinkex Adapter |
|---------|-------------------|----------------|
| KL direction (forward/reverse) | `Divergences.kl_divergence/3` | `Regularizers.KLDivergence` |
| KL symmetric mode | `Divergences.kl_divergence/3` | `Regularizers.KLDivergence` |
| Entropy temperature | `Divergences.entropy/2` | `Regularizers.Entropy` |
| Pipeline.Multi | `Pipeline.Multi` | New helper module |
| Polaris transforms | `Integration.Polaris` | Documentation/examples |
| Axon integration | `Integration.Axon` | Documentation/examples |

---

## Phase 1: Adapter Updates

### 1.1 KLDivergence Adapter

**File**: `lib/tinkex/regularizers/kl_divergence.ex`

**Current call**:
```elixir
NxPenalties.Divergences.kl_divergence(logprobs, reference, reduction: reduction)
```

**New options to expose**:
- `:direction` - `:forward` (default), `:reverse`, or atom
- `:symmetric` - boolean, computes `(KL(P||Q) + KL(Q||P)) / 2`

**Changes**:
```elixir
def compute(data, logprobs, opts \\ []) do
  # ... existing reference resolution ...
  reduction = Keyword.get(opts, :reduction, :mean)
  direction = Keyword.get(opts, :direction, :forward)
  symmetric = Keyword.get(opts, :symmetric, false)

  value = NxPenalties.Divergences.kl_divergence(logprobs, reference,
    reduction: reduction,
    direction: direction,
    symmetric: symmetric
  )

  metrics = %{
    "kl_divergence" => Nx.to_number(value),
    "kl_direction" => Atom.to_string(direction),
    "kl_symmetric" => symmetric
    # ... existing min/max metrics ...
  }

  {value, metrics}
end
```

**Test cases**:
- Forward KL (default behavior, existing tests pass)
- Reverse KL (mode-seeking behavior)
- Symmetric KL (balanced divergence)

---

### 1.2 Entropy Adapter

**File**: `lib/tinkex/regularizers/entropy.ex`

**Current call**:
```elixir
NxPenalties.Divergences.entropy(logprobs, mode: nx_mode, reduction: reduction, normalize: normalize)
```

**New option to expose**:
- `:temperature` - float, scales logprobs before computing entropy (default: 1.0)

**Changes**:
```elixir
def compute(data, logprobs, opts \\ []) do
  mode = Keyword.get(opts, :mode, :maximize)
  reduction = Keyword.get(opts, :reduction, :mean)
  normalize = Keyword.get(opts, :normalize, false)
  temperature = Keyword.get(opts, :temperature, 1.0)

  nx_mode = if mode == :maximize, do: :penalty, else: :bonus

  value = NxPenalties.Divergences.entropy(logprobs,
    mode: nx_mode,
    reduction: reduction,
    normalize: normalize,
    temperature: temperature
  )

  metrics = %{
    "entropy" => Nx.to_number(value),
    "mode" => Atom.to_string(mode),
    "temperature" => temperature
  }

  {value, metrics}
end
```

**Test cases**:
- Temperature = 1.0 (default, existing tests pass)
- Temperature < 1.0 (sharper distribution)
- Temperature > 1.0 (flatter distribution)

---

## Phase 2: New Helper Module

### 2.1 Pipeline.Multi Wrapper (Optional)

**Rationale**: NxPenalties v0.1.1 introduces `Pipeline.Multi` for multi-input penalties (KL, consistency). Tinkex could provide a thin wrapper that integrates with its data/logprobs pattern.

**File**: `lib/tinkex/regularizer/multi_pipeline.ex` (new)

**Scope**: Low priority. Current adapters handle reference resolution internally. Consider if users need direct Pipeline.Multi access.

**Decision**: Document in examples rather than wrap. The existing adapter pattern (resolve reference from `loss_fn_inputs`) is sufficient for most use cases.

---

## Phase 3: Example Updates

### 3.1 Update structured_regularizers.exs

**File**: `examples/structured_regularizers.exs`

**Additions**:
1. KL divergence with `:direction` and `:symmetric` options
2. Entropy with `:temperature` scaling
3. Comments explaining when to use each variant

```elixir
# KL Divergence variants
kl_forward = RegularizerSpec.new(%{
  fn: fn data, logprobs ->
    Regularizers.KLDivergence.compute(data, logprobs,
      reference_field: :reference_logprobs,
      direction: :forward  # Default: minimize surprise
    )
  end,
  weight: 0.01,
  name: "kl_forward"
})

kl_reverse = RegularizerSpec.new(%{
  fn: fn data, logprobs ->
    Regularizers.KLDivergence.compute(data, logprobs,
      reference_field: :reference_logprobs,
      direction: :reverse  # Mode-seeking behavior
    )
  end,
  weight: 0.01,
  name: "kl_reverse"
})

kl_symmetric = RegularizerSpec.new(%{
  fn: fn data, logprobs ->
    Regularizers.KLDivergence.compute(data, logprobs,
      reference_field: :reference_logprobs,
      symmetric: true  # Balanced divergence
    )
  end,
  weight: 0.01,
  name: "kl_symmetric"
})

# Entropy with temperature
entropy_sharp = RegularizerSpec.new(%{
  fn: fn data, logprobs ->
    Regularizers.Entropy.compute(data, logprobs,
      mode: :maximize,
      temperature: 0.5  # Sharper distribution
    )
  end,
  weight: 0.001,
  name: "entropy_sharp"
})
```

### 3.2 Update structured_regularizers_live.exs

**File**: `examples/structured_regularizers_live.exs`

**Additions**: Same new options demonstrated against live API.

---

## Phase 4: Test Updates

### 4.1 Adapter Tests

**File**: `test/tinkex/regularizers/adapters_test.exs`

**New test cases**:

```elixir
describe "KLDivergence adapter" do
  # ... existing tests ...

  test "supports direction: :reverse option" do
    data = [%{loss_fn_inputs: %{reference_logprobs: @reference}}]
    {loss, metrics} = Regularizers.KLDivergence.compute(data, @logprobs,
      reference_field: :reference_logprobs,
      direction: :reverse
    )
    assert Nx.shape(loss) == {}
    assert metrics["kl_direction"] == "reverse"
  end

  test "supports symmetric: true option" do
    data = [%{loss_fn_inputs: %{reference_logprobs: @reference}}]
    {loss, metrics} = Regularizers.KLDivergence.compute(data, @logprobs,
      reference_field: :reference_logprobs,
      symmetric: true
    )
    assert Nx.shape(loss) == {}
    assert metrics["kl_symmetric"] == true
  end
end

describe "Entropy adapter" do
  # ... existing tests ...

  test "supports temperature option" do
    {loss, metrics} = Regularizers.Entropy.compute([], @logprobs,
      mode: :maximize,
      temperature: 0.5
    )
    assert Nx.shape(loss) == {}
    assert metrics["temperature"] == 0.5
  end

  test "temperature affects output value" do
    {loss_default, _} = Regularizers.Entropy.compute([], @logprobs, mode: :maximize)
    {loss_sharp, _} = Regularizers.Entropy.compute([], @logprobs, mode: :maximize, temperature: 0.5)
    {loss_flat, _} = Regularizers.Entropy.compute([], @logprobs, mode: :maximize, temperature: 2.0)

    # Different temperatures produce different values
    refute Nx.to_number(loss_default) == Nx.to_number(loss_sharp)
    refute Nx.to_number(loss_default) == Nx.to_number(loss_flat)
  end
end
```

---

## Phase 5: Documentation Updates

### 5.1 examples/README.md

Update the structured_regularizers sections to mention new options.

### 5.2 docs/guides/regularizers.md

Add sections:
- "KL Divergence Direction" - when to use forward vs reverse vs symmetric
- "Entropy Temperature Scaling" - effect on exploration/exploitation

### 5.3 CHANGELOG.md

```markdown
## [Unreleased]

### Changed
- Updated `nx_penalties` dependency to `~> 0.1.1`
- `Regularizers.KLDivergence` now supports `:direction` (`:forward`/`:reverse`) and `:symmetric` options
- `Regularizers.Entropy` now supports `:temperature` option for distribution sharpening/flattening

### Added
- New examples demonstrating KL direction variants and entropy temperature scaling
```

---

## Implementation Checklist

- [ ] **Phase 1.1**: Update `KLDivergence` adapter with `:direction` and `:symmetric`
- [ ] **Phase 1.2**: Update `Entropy` adapter with `:temperature`
- [ ] **Phase 3.1**: Update `structured_regularizers.exs` examples
- [ ] **Phase 3.2**: Update `structured_regularizers_live.exs` examples
- [ ] **Phase 4.1**: Add adapter tests for new options
- [ ] **Phase 5.1**: Update `examples/README.md`
- [ ] **Phase 5.2**: Update `docs/guides/regularizers.md`
- [ ] **Phase 5.3**: Update `CHANGELOG.md`

---

## Quality Gates

```bash
mix deps.get
mix compile --warnings-as-errors
mix test
mix dialyzer
mix format --check-formatted
```

---

## Out of Scope

The following nx_penalties v0.1.1 features are **not** being wrapped in tinkex adapters:

1. **Pipeline.Multi**: Tinkex adapters already handle reference resolution internally. Direct Pipeline.Multi usage is an advanced pattern better left to power users who import nx_penalties directly.

2. **Axon Integration Functions**: Tinkex is a Tinker SDK, not an Axon training framework. Users building Axon models should use `NxPenalties.Integration.Axon` directly.

3. **Polaris Transforms**: Same rationale. Gradient-level transforms are optimizer concerns, not regularizer adapter concerns.

These features remain available via direct `NxPenalties` imports for advanced use cases.
