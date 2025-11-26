# ADR-001: Regularizer Architecture

## Status

**Proposed** - November 25, 2025

## Context

The Tinkex SDK needs to support structured regularizer composition for custom loss functions. This feature ports the Python SDK's structured regularizers (commit `22e6fc9b`) to Elixir.

### Current State

- `TrainingClient.forward/4` returns logprobs that can be converted to Nx tensors
- Custom loss computation is possible but requires manual composition
- No structured way to define multiple regularizers with independent weights
- No built-in gradient tracking per regularizer

### Requirements

1. Define multiple named regularizers with independent weights
2. Support both synchronous and asynchronous regularizers
3. Enable gradient magnitude tracking per regularizer
4. Maintain backward compatibility with existing API
5. Integrate with Elixir's type system (specs, dialyzer)

## Decision

We will implement structured regularizers using:

### 1. Type-Based Configuration

Regularizers are configured via a typed struct (`RegularizerSpec`) rather than plain maps or keyword lists.

```elixir
%RegularizerSpec{
  fn: &my_regularizer/2,
  weight: 0.01,
  name: "l1_sparsity",
  async: false
}
```

**Rationale:**
- Compile-time validation via dialyzer
- Self-documenting structure
- Consistent with existing Tinkex types (Datum, TensorData, etc.)

### 2. Behaviour-Based Extension

A `Tinkex.Regularizer` behaviour provides a formal interface for module-based regularizers.

```elixir
@callback compute(data, logprobs, opts) :: {Nx.Tensor.t(), map()}
@callback name() :: String.t()
```

**Rationale:**
- Enables reusable regularizer modules
- Clear contract for implementers
- Supports both anonymous functions and modules

### 3. Required Base Loss Function

The base loss function (`loss_fn`) is a required parameter, not optional.

```elixir
# API
forward_backward_custom(client, data, loss_fn, opts)
#                                      ^^^^^^^ required
```

**Rationale:**
- Every training configuration has an explicit primary objective
- Regularizers are conceptually "add-ons" to the base loss
- Clearer semantic model than making everything optional
- Matches Python SDK design decision (Option B)

### 4. Composition Model

Loss composition follows the formula:

```
loss_total = base_loss + Σ(weight_i × regularizer_i_loss)
```

The pipeline computes this by:
1. Executing base loss function
2. Executing regularizers (optionally in parallel)
3. Accumulating weighted contributions
4. Building structured output

**Rationale:**
- Standard regularization formulation from ML literature
- Each component independently trackable
- Weights enable hyperparameter tuning without code changes

## Alternatives Considered

### Alternative A: Map-Based Configuration

```elixir
# Rejected
regularizers: [
  %{fn: &my_fn/2, weight: 0.01, name: "l1"}
]
```

**Why rejected:**
- No compile-time type checking
- Easy to misspell keys
- Less discoverable API

### Alternative B: Optional Base Loss

```elixir
# Rejected
forward_backward_custom(client, data, loss_fn: nil, regularizers: [...])
```

**Why rejected:**
- Semantic ambiguity: what's the "base" objective?
- More complex validation logic
- Harder to reason about training dynamics

### Alternative C: DSL-Based Configuration

```elixir
# Rejected
use Tinkex.Regularizers

training_config do
  base_loss :cross_entropy
  regularizer :l1_sparsity, weight: 0.01
  regularizer :entropy, weight: 0.001
end
```

**Why rejected:**
- Macro complexity for marginal benefit
- Harder to compose dynamically
- Less interop with plain Elixir code

### Alternative D: Server-Side Regularizers

Push regularizer computation to the Tinker server.

**Why rejected:**
- Requires server changes
- Limits regularizer expressiveness
- Can't access local resources (knowledge bases, etc.)
- Doesn't leverage Elixir's Nx ecosystem

## Consequences

### Positive

1. **Type Safety**: Dialyzer catches configuration errors at compile time
2. **Extensibility**: Behaviour enables community regularizer libraries
3. **Clarity**: Required base loss makes training objectives explicit
4. **Compatibility**: API mirrors Python SDK for cross-language consistency

### Negative

1. **Verbosity**: Struct instantiation more verbose than maps
2. **Learning Curve**: Developers must understand the type hierarchy
3. **Migration**: Existing custom loss code needs adaptation

### Risks

1. **Nx Compatibility**: Some tensor operations may not support autodiff
   - Mitigation: Document limitations, provide workarounds

2. **Performance**: Extra struct allocation overhead
   - Mitigation: Minimal in practice, profile if needed

## Related Decisions

- ADR-002: Concurrency Model
- ADR-003: Telemetry Schema

## References

- Python SDK commit: `22e6fc9b4f85c7dbb07e72aa415a26fb454ef504`
- Nx documentation: https://hexdocs.pm/nx
- Elixir Behaviours: https://hexdocs.pm/elixir/behaviours.html
