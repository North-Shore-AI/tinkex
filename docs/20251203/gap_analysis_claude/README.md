# Tinkex Gap Analysis: Python → Elixir Parity

**Date:** 2025-12-03
**Versions:** Python tinker 0.6.3 → Elixir tinkex 0.1.18

## Executive Summary

The Elixir `tinkex` SDK has achieved **~90% feature parity** with the Python `tinker` SDK. Most core functionality for training, sampling, checkpoint management, and REST operations is fully implemented with idiomatic Elixir patterns.

### Parity Status by Area

| Area | Parity | Notes |
|------|--------|-------|
| ServiceClient | 95% | Missing explicit retry_config on sampling client |
| TrainingClient | 85% | Missing gradient norm tracking, thread pool regularizers |
| SamplingClient | 100% | Full parity |
| RestClient | 95% | All endpoints present, telemetry integration differs |
| Telemetry | 70% | Event model differs, Python has server upload batching |
| Data Handling | 80% | Missing chunked output combiner, ModelInput builders |
| CLI | 110% | Elixir has MORE features (checkpoint save, run sample) |
| Tokenizer | 100% | Full parity via HuggingFace Tokenizers |

### Intentional Exclusions

Per project requirements, the following are **not gaps**:
- Fancy CLI progress meters (intentionally excluded)
- Rich/Click terminal UI decorations

## Gap Categories

### Critical Gaps (Impact: High)
1. **Gradient Norm Tracking** - Training introspection missing
2. **Chunked Output Combiner** - Large batch handling incomplete
3. **Server Telemetry Upload** - Event batching to API missing

### Minor Gaps (Impact: Low)
4. **ModelInput Builder Methods** - Convenience methods missing
5. **Key-based Dtype Inference** - Field-specific type inference
6. **Retry Config on Sampling** - Explicit configuration missing
7. **Thread Pool Regularizers** - Parallel regularizer execution

## Detailed Reports

- [Training Features](./01_training_gaps.md)
- [Data Handling](./02_data_handling_gaps.md)
- [Telemetry](./03_telemetry_gaps.md)
- [CLI Features](./04_cli_comparison.md)
- [REST & Service Clients](./05_client_gaps.md)

## Recommendations

### Priority 1: Critical for ML Workflows
1. Add `combine_fwd_bwd_output_results/1` for chunked training
2. Implement gradient norm tracking in `CustomLoss`

### Priority 2: Operational Excellence
3. Add server-side telemetry batch upload
4. Expose `retry_config` on `SamplingClient`

### Priority 3: Developer Experience
5. Add `ModelInput.empty/0`, `append/2`, `append_int/2`
6. Add key-based dtype inference for Datum fields

## Architecture Notes

Both SDKs follow the same high-level patterns:
- **Client Hierarchy:** ServiceClient → TrainingClient/SamplingClient/RestClient
- **Async Model:** Python (Futures + async/await) ≈ Elixir (Task + GenServer)
- **Error Handling:** Python (Exceptions) ≈ Elixir ({:ok, _}/{:error, _})
- **HTTP Layer:** Python (httpx) ≈ Elixir (Finch)

The Elixir implementation makes idiomatic trade-offs that improve on Python in some areas (explicit timeout control, GenServer state management, macro-based telemetry capture).
