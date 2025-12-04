# Tinkex Gap Analysis: Python → Elixir Parity

**Date:** 2025-12-03
**Versions:** Python tinker 0.6.3 → Elixir tinkex 0.1.19

## Executive Summary

The Elixir `tinkex` SDK has achieved **~95% feature parity** with the Python `tinker` SDK. Core training, sampling, checkpoint management, REST APIs, and telemetry upload are implemented with idiomatic Elixir patterns; remaining deltas are limited to metric reducer coverage, tensor conversion backends, and a few convenience builders.

### Parity Status by Area

| Area | Parity | Notes |
|------|--------|-------|
| ServiceClient | 95% | Parity mode needed to match Python timeouts/retries |
| TrainingClient | 95% | Elixir adds regularizer pipeline + grad norms; Python lacks |
| SamplingClient | 100% | `retry_config` accepted in both |
| RestClient | 95% | Same endpoints; return shapes differ |
| Telemetry | 90% | Both upload to `/api/v1/telemetry`; retry/window semantics differ |
| Data Handling | 90% | Missing `hash_unordered` reducer; ModelInput builders absent; tensor backends differ |
| CLI | 105% | Elixir adds checkpoint save/run sample; both download+extract archives |
| Tokenizer | 100% | Full parity via HF tokenizers |

### Intentional Exclusions

Per project requirements, the following are **not gaps**:
- Fancy CLI progress meters (intentionally excluded)
- Rich/Click terminal UI decorations

## Gap Categories

### Critical Gaps (Impact: High)
None identified.

### Remaining Gaps (Impact: Medium/Low)
1. ~~**Metric reducer coverage**~~ – ✅ `hash_unordered` now implemented in Elixir combiner
2. **Tensor conversion backends** – Python offers NumPy/PyTorch helpers; Elixir is Nx-only (+ `tolist/1`)
3. ~~**ModelInput builder helpers**~~ – ✅ `empty/0`, `append/2`, `append_int/2` now implemented
4. **Retry/timeout defaults** – Elixir defaults differ unless `parity_mode: :python` is set

## Detailed Reports

- [Training Features](./01_training_gaps.md)
- [Data Handling](./02_data_handling_gaps.md)
- [Telemetry](./03_telemetry_gaps.md)
- [CLI Features](./04_cli_comparison.md)
- [REST & Service Clients](./05_client_gaps.md)

## Recommendations

### Priority 1: Parity polish (COMPLETED)
1. ✅ `hash_unordered` metric reducer implemented
2. ✅ `ModelInput.empty/0`, `append/2`, `append_int/2` helpers implemented
3. ✅ `TensorData.tolist/1` added for API parity

### Priority 2: Developer experience
4. Document/optionally expose NumPy/PyTorch-friendly conversions or call out Nx-only scope
5. Make parity defaults obvious (`parity_mode: :python`) for timeout/retry alignment

## Architecture Notes

Both SDKs follow the same high-level patterns:
- **Client Hierarchy:** ServiceClient → TrainingClient/SamplingClient/RestClient
- **Async Model:** Python (Futures + async/await) ≈ Elixir (Task + GenServer)
- **Error Handling:** Python (Exceptions) ≈ Elixir ({:ok, _}/{:error, _})
- **HTTP Layer:** Python (httpx) ≈ Elixir (Finch)

The Elixir implementation makes idiomatic trade-offs that improve on Python in some areas (explicit timeout control, GenServer state management, macro-based telemetry capture).
