# ADR-003: Telemetry Schema for Regularizers

## Status

**Proposed** - November 25, 2025

## Context

Structured regularizers require comprehensive telemetry for:
- Monitoring regularizer execution performance
- Debugging training dynamics
- Identifying gradient magnitude issues
- Tuning regularizer weights

### Existing Tinkex Telemetry

Tinkex uses Erlang's `:telemetry` library with events:
- `[:tinkex, :http, :request, :start|:stop|:exception]`
- `[:tinkex, :queue, :state_change]`

### Python SDK Metrics

The Python SDK returns a structured metrics dictionary:
```python
{
    "loss_total": float,
    "base_loss": {"value": float, "grad_norm": float, "custom": {}},
    "regularizers": {
        "<name>": {"value": float, "weight": float, "contribution": float, ...}
    },
    "regularizer_total": float,
    "total_grad_norm": float
}
```

## Decision

We will implement a hierarchical telemetry schema with events at multiple granularities:

### 1. Event Hierarchy

```
[:tinkex, :custom_loss, :start]
[:tinkex, :custom_loss, :stop]
[:tinkex, :custom_loss, :exception]
    │
    └── [:tinkex, :regularizer, :compute, :start]
        [:tinkex, :regularizer, :compute, :stop]
        [:tinkex, :regularizer, :compute, :exception]
```

**Rationale:**
- Follows Erlang telemetry naming conventions
- Enables filtering at different levels
- Consistent with existing Tinkex events

### 2. Event Specifications

#### Custom Loss Start

```elixir
:telemetry.execute(
  [:tinkex, :custom_loss, :start],
  %{system_time: System.system_time()},
  %{
    model_id: String.t(),
    data_count: non_neg_integer(),
    regularizer_count: non_neg_integer(),
    track_grad_norms: boolean()
  }
)
```

#### Custom Loss Stop

```elixir
:telemetry.execute(
  [:tinkex, :custom_loss, :stop],
  %{
    duration: native_time(),
    loss_total: float(),
    regularizer_total: float(),
    total_grad_norm: float() | nil
  },
  %{
    model_id: String.t(),
    regularizer_count: non_neg_integer(),
    track_grad_norms: boolean()
  }
)
```

#### Regularizer Compute Start

```elixir
:telemetry.execute(
  [:tinkex, :regularizer, :compute, :start],
  %{system_time: System.system_time()},
  %{
    regularizer_name: String.t(),
    weight: float(),
    async: boolean()
  }
)
```

#### Regularizer Compute Stop

```elixir
:telemetry.execute(
  [:tinkex, :regularizer, :compute, :stop],
  %{
    duration: native_time(),
    value: float(),
    contribution: float(),
    grad_norm: float() | nil
  },
  %{
    regularizer_name: String.t(),
    weight: float(),
    async: boolean()
  }
)
```

### 3. Metrics Output Structure

The `CustomLossOutput` struct serves as the primary metrics container:

```elixir
%CustomLossOutput{
  loss_total: 2.847,
  base_loss: %{
    value: 2.5,
    grad_norm: 3.14,
    custom: %{"perplexity" => 12.18}
  },
  regularizers: %{
    "sparsity" => %RegularizerOutput{
      name: "sparsity",
      value: 22.4,
      weight: 0.01,
      contribution: 0.224,
      grad_norm: 7.48,
      grad_norm_weighted: 0.0748,
      custom: %{"l1_mean" => 22.4}
    }
  },
  regularizer_total: 0.224,
  total_grad_norm: 5.67
}
```

**Rationale:**
- Mirrors Python SDK schema for API compatibility
- Enables cross-language tooling
- Self-contained for logging/storage

### 4. JSON Serialization

All metric types implement `Jason.Encoder`:

```elixir
defimpl Jason.Encoder, for: Tinkex.Types.CustomLossOutput do
  def encode(output, opts) do
    # Serialize to JSON matching Python schema
  end
end
```

**Rationale:**
- Easy export to logging systems
- Compatible with monitoring dashboards
- Human-readable output

### 5. Conditional Gradient Tracking

Gradient norms are only computed/reported when `track_grad_norms: true`:

```elixir
# Without gradient tracking
%RegularizerOutput{grad_norm: nil, grad_norm_weighted: nil}

# With gradient tracking
%RegularizerOutput{grad_norm: 7.48, grad_norm_weighted: 0.0748}
```

**Rationale:**
- Gradient computation has overhead
- Not always needed for production
- Explicit opt-in via option

## Alternatives Considered

### Alternative A: Flat Metrics Map

```elixir
# Rejected
%{
  "loss_total" => 2.847,
  "sparsity_value" => 22.4,
  "sparsity_contribution" => 0.224,
  "entropy_value" => 1.5,
  ...
}
```

**Why rejected:**
- Loses hierarchical structure
- Dynamic keys harder to type
- Doesn't match Python SDK schema

### Alternative B: OpenTelemetry Integration

```elixir
# Rejected
OpenTelemetry.Span.set_attributes(span, %{
  "regularizer.name" => "sparsity",
  "regularizer.value" => 22.4
})
```

**Why rejected:**
- Requires OpenTelemetry dependency
- More complex setup
- `:telemetry` is sufficient for most use cases
- Can add OpenTelemetry adapter later

### Alternative C: Prometheus Metrics

```elixir
# Rejected
Prometheus.Gauge.set([name: :regularizer_value, labels: [:name]], value)
```

**Why rejected:**
- Pull-based model doesn't fit per-batch metrics
- Cardinality issues with many regularizers
- Better suited for aggregated metrics

### Alternative D: Custom Logger Backend

```elixir
# Rejected
Logger.info("Regularizer computed", regularizer: name, value: value)
```

**Why rejected:**
- Unstructured text harder to query
- No standard schema
- `:telemetry` provides better hooks

## Consequences

### Positive

1. **Schema Compatibility**: Same structure as Python SDK
2. **Flexible Attachment**: `:telemetry.attach/4` for custom handlers
3. **Performance Monitoring**: Duration tracking at both levels
4. **Debugging Support**: Rich metadata for troubleshooting

### Negative

1. **Telemetry Overhead**: Event emission has small cost
   - Mitigated by conditional emission

2. **Schema Rigidity**: Changes require version bumps
   - Standard versioning practices

3. **Storage Volume**: Detailed metrics generate data
   - Users control attachment granularity

### Risks

1. **Handler Performance**: Slow handlers block execution
   - Mitigation: Use async handlers for I/O

2. **Missing Events**: Exceptions may skip stop events
   - Mitigation: Always emit exception events

## Example Handler Implementation

```elixir
defmodule MyApp.RegularizerLogger do
  require Logger

  def attach do
    :telemetry.attach_many(
      "regularizer-logger",
      [
        [:tinkex, :custom_loss, :stop],
        [:tinkex, :regularizer, :compute, :stop]
      ],
      &handle_event/4,
      %{}
    )
  end

  defp handle_event([:tinkex, :custom_loss, :stop], measurements, metadata, _config) do
    Logger.info(
      "Custom loss: total=#{measurements.loss_total} " <>
      "regs=#{metadata.regularizer_count} " <>
      "duration=#{System.convert_time_unit(measurements.duration, :native, :millisecond)}ms"
    )
  end

  defp handle_event([:tinkex, :regularizer, :compute, :stop], measurements, metadata, _config) do
    Logger.debug(
      "Regularizer #{metadata.regularizer_name}: " <>
      "value=#{measurements.value} contribution=#{measurements.contribution}"
    )
  end
end
```

## Related Decisions

- ADR-001: Regularizer Architecture
- ADR-002: Concurrency Model

## References

- Erlang Telemetry: https://hexdocs.pm/telemetry/readme.html
- Telemetry.Metrics: https://hexdocs.pm/telemetry_metrics/Telemetry.Metrics.html
- Jason library: https://hexdocs.pm/jason/readme.html
