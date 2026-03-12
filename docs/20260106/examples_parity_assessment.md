# Examples Parity Assessment (Current vs Goal)

## Goal
All scripts under `examples/` and documentation in `examples/README.md` run unchanged, with identical behavior and shapes to the original SDK.

## Current Snapshot
The current public surface is thin:
- Core config/env/error/version: `Tinkex.Config`, `Tinkex.Env`, `Tinkex.Error`, `Tinkex.Version`.
- Domain helpers: `Tinkex.Tokenizer`, `Tinkex.ModelInput`, `Tinkex.ByteEstimator`.
- Manifest + generated client: `Tinkex.Manifest`, `Tinkex.Generated.*`, `Tinkex.Generated.Types.*`.
- A small subset of legacy types remains under `Tinkex.Types.*` (Datum/TensorData/etc).

## Example Coverage Delta (Observed)
From static analysis of `examples/*.exs` + `examples/README.md`:
- Modules referenced: 69
- Modules present in `lib/tinkex`: 6
- Missing modules: 63

Present in current code (examples can resolve these):
- `Tinkex.Config`
- `Tinkex.Error`
- `Tinkex.Tokenizer`
- `Tinkex.Types.Datum`
- `Tinkex.Types.TensorData`
- `Tinkex.Version`

Missing from current code (examples will fail to compile):
- API layer: `Tinkex.API`, `Tinkex.API.Service`, `Tinkex.API.Session`, `Tinkex.API.Rest`
- Clients: `Tinkex.ServiceClient`, `Tinkex.SamplingClient`, `Tinkex.TrainingClient`,
  `Tinkex.RestClient`, `Tinkex.SessionManager`
- Observability: `Tinkex.Telemetry`, `Tinkex.Telemetry.Reporter`, `Tinkex.Telemetry.Capture`,
  `Tinkex.Metrics`
- Control and retries: `Tinkex.Retry`, `Tinkex.QueueStateObserver`, `Tinkex.QueueStateLogger`,
  `Tinkex.Recovery`
- Regularizers: `Tinkex.Regularizer`, `Tinkex.Regularizers`
- IO tooling: `Tinkex.Multipart`, `Tinkex.Files.Transform`
- CLI: `Tinkex.CLI`
- Types: `Tinkex.Types.*` for most request/response structs used across examples

Net result: examples do not compile today without manual edits.

## Shape Parity Gaps
The generated API (`Tinkex.Generated.*`) does not match the legacy shapes expected by the
examples. The largest mismatches:
- **Types namespace**: Examples use `Tinkex.Types.*` (e.g., `SamplingParams`, `LoraConfig`,
  `ModelInput`), but the generated types live under `Tinkex.Generated.Types.*`.
- **Client API**: Examples expect `ServiceClient` + `SamplingClient` + `TrainingClient`
  GenServers and higher-level helpers; only the generated client exists.
- **Direct raw HTTP**: Examples call `Tinkex.API.post/get` and `Tinkex.API.Session.create`;
  these functions are absent.
- **Telemetry/metrics/recovery/regularizers**: These features were removed entirely.
- **Queue state observer**: Examples depend on queue warnings/telemetry callbacks that are
  no longer present.
- **Multipart/files**: Examples rely on `Tinkex.Multipart` and `Tinkex.Files.Transform`.
- **CLI**: `Tinkex.CLI` is missing.

## Functional Parity Risks
Even if missing modules are reintroduced as wrappers, parity is not guaranteed without
explicit compatibility behavior:
- `Tinkex.Types.*` structs originally had custom constructors, validation, and JSON
  encoding; generated types have different defaults/validators.
- Legacy clients handled retry, queue state logging, and telemetry; the generated runtime
  does not currently expose those behaviors through the same entrypoints.
- Legacy `ServiceClient` started pools/telemetry processes; there is no equivalent startup
  path in the current thin SDK.

## Required Work to Meet the Goal (Examples Unchanged)
To make all examples run untouched, the SDK needs a compatibility layer:
1. **Reintroduce client facade modules**:
   - `Tinkex.ServiceClient`, `Tinkex.SamplingClient`, `Tinkex.TrainingClient`,
     `Tinkex.RestClient`, `Tinkex.SessionManager`.
   - These should wrap `Tinkex.Generated.*` resources while preserving old function
     signatures and return shapes.
2. **Reintroduce API helpers**:
   - `Tinkex.API` (raw request helpers) and typed modules (`Tinkex.API.Session`, etc)
     as thin delegates to the generated client and `Pristine.Runtime`.
3. **Restore types under legacy namespace**:
   - Provide `Tinkex.Types.*` modules that mirror old structs and functions, delegating
     to `Tinkex.Generated.Types.*` where safe or implementing compatibility transforms.
4. **Telemetry/metrics/retry/recovery/regularizers**:
   - Rebuild modules or re-export from Pristine if moved there. Examples depend on these
     workflows explicitly.
5. **Queue state observer/logging**:
   - Restore queue state telemetry hooks and observer behavior expected by examples.
6. **Multipart/files utilities**:
   - Reintroduce `Tinkex.Multipart` and `Tinkex.Files.Transform` or provide compatible
     replacements.
7. **CLI**:
   - Restore `Tinkex.CLI` interface or wrap the new generated client.
8. **Runtime bootstrap**:
   - Ensure Finch pools/telemetry processes are started when examples create clients.

## Recommendation
We are **not close** to example parity today. The generated client exists, but the legacy
shape is missing. The fastest path is a compatibility layer that preserves the old module
names and behavior while delegating to the manifest-driven runtime.

If the goal is "examples unchanged", the work must be focused on reintroducing the
missing modules and type wrappers rather than further shrinking the codebase.
