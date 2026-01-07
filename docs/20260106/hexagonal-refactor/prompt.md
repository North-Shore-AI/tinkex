Agent Prompt: Tinkex Hexagonal Refactor

# Tinkex Hexagonal Refactor - Complete Implementation

## Mission

Transform ~/p/g/North-Shore-AI/tinkex from a standalone SDK into a thin manifest-driven wrapper over Pristine. Pristine is the GENERALIZATION of Tinkex - all infrastructure moves to Pristine, tinkex keeps only domain-specific code (~200-500 lines).

## Required Reading (Do This First)

### Documentation (Read in order)
1. `~/p/g/North-Shore-AI/tinkex/docs/20260106/hexagonal-refactor/plan.md` - Full 6-phase plan
2. `~/p/g/North-Shore-AI/tinkex/docs/20260106/hexagonal-refactor/CHECKLIST.md` - Detailed checklist
3. `~/p/g/North-Shore-AI/tinkex/docs/20260106/hexagonal-refactor/REPLACEMENT_MAP.md` - Module replacement mapping
4. `~/p/g/North-Shore-AI/tinkex/CLAUDE.md` OR `~/p/g/North-Shore-AI/tinkex/AGENTS.md` - Project instructions (update as you work)
5. `~/p/g/North-Shore-AI/pristine/CLAUDE.md` - Pristine project context
6. Ignore `~/p/g/North-Shore-AI/pristine/examples/` entirely (not a reference source for this refactor).

### Source Analysis (Understand before changing)
1. `~/p/g/North-Shore-AI/tinkex/mix.exs` - Current dependencies
2. `~/p/g/North-Shore-AI/tinkex/lib/tinkex/` - Full source tree structure
3. `~/p/g/n/foundation/lib/foundation/` - Foundation library (retry, circuit_breaker, rate_limit, semaphore)
4. `~/p/g/n/sinter/lib/sinter/` - Sinter library (not_given, transform, schema)
5. `~/p/g/n/multipart_ex/lib/` - Multipart encoding library

### Reference Implementation
- `~/p/g/North-Shore-AI/pristine/lib/pristine/ports/` - How ports are defined
- `~/p/g/North-Shore-AI/pristine/lib/pristine/adapters/` - How adapters are implemented
- `~/p/g/North-Shore-AI/pristine/lib/pristine/core/` - Pipeline/context patterns

---

## Absolute Requirements

### Testing (Non-Negotiable)
- **ALL tests must pass after EVERY change** - never break tests
- Run `mix test` after each module replacement
- Run `mix test --seed 12345` and `mix test --seed 99999` to verify seed independence
- If a test fails, fix it before proceeding
- Add tests for new code (TDD: Red-Green-Refactor)

### Code Quality (Non-Negotiable)
- `mix compile --warnings-as-errors` - ZERO warnings
- `mix dialyzer` - ZERO errors
- `mix credo --strict` - ZERO issues
- `mix format` - All code formatted

### Documentation (Non-Negotiable)
- Update `CLAUDE.md` or `AGENTS.md` after each phase with:
- What was changed
- New module locations
- Updated commands
- Any gotchas discovered
- Update `docs/20260106/hexagonal-refactor/CHECKLIST.md` - check off completed items

---

## Phase 1: Integrate Foundation/Sinter

### Step 1.1: Add Dependencies

Edit `mix.exs` to add:
```elixir
{:foundation, path: "../pristine/deps/foundation"},
{:sinter, path: "../pristine/deps/sinter"},
{:multipart_ex, path: "../pristine/deps/multipart_ex"},

Run: mix deps.get && mix compile

Step 1.2: Replace RetryConfig/RetryHandler

Files to modify:
- Find all usages: grep -r "RetryConfig\|RetryHandler" lib/
- Replace with Foundation.Retry.Policy and Foundation.Retry

Replacement pattern:
# OLD
config = Tinkex.RetryConfig.new(max_retries: 3, base_delay_ms: 500)
Tinkex.RetryHandler.execute(fn -> ... end, config)

# NEW
policy = Foundation.Retry.Policy.new(
max_attempts: 4,
backoff: %Foundation.Backoff.Policy{type: :exponential, base_ms: 500}
)
Foundation.Retry.run(fn -> ... end, policy)

Delete after replacement:
- lib/tinkex/retry_config.ex
- lib/tinkex/retry_handler.ex
- lib/tinkex/retry.ex (if exists)
- lib/tinkex/api/retry.ex
- lib/tinkex/api/retry_config.ex

Verify: mix test && mix dialyzer

Step 1.3: Replace CircuitBreaker

Files to modify:
- lib/tinkex/circuit_breaker.ex → Use Foundation.CircuitBreaker
- lib/tinkex/circuit_breaker/registry.ex → Use Foundation.CircuitBreaker.Registry

API is identical - direct drop-in replacement.

Delete after replacement:
- lib/tinkex/circuit_breaker.ex
- lib/tinkex/circuit_breaker/registry.ex

Verify: mix test && mix dialyzer

Step 1.4: Replace RateLimiter

File: lib/tinkex/rate_limiter.ex
Replace with: Foundation.RateLimit.BackoffWindow

Delete after replacement:
- lib/tinkex/rate_limiter.ex

Verify: mix test && mix dialyzer

Step 1.5: Replace Semaphores

Files:
- lib/tinkex/retry_semaphore.ex → Foundation.Semaphore.Counting
- lib/tinkex/bytes_semaphore.ex → Foundation.Semaphore.Weighted
- lib/tinkex/semaphore.ex → Delete (wrapper)

Verify: mix test && mix dialyzer

Step 1.6: Replace NotGiven/Transform

Files:
- lib/tinkex/not_given.ex → Sinter.NotGiven
- lib/tinkex/transform.ex → Sinter.Transform

Note: Sentinel atom changes from :__tinkex_not_given__ to :__sinter_not_given__

Verify: mix test && mix dialyzer

Step 1.7: Replace Multipart

Files:
- lib/tinkex/multipart/encoder.ex → Multipart.Encoder
- lib/tinkex/multipart/form_serializer.ex → Multipart.Form

Delete after replacement:
- lib/tinkex/multipart/ directory

Verify: mix test && mix dialyzer

---
Phase 2: Stabilize

Run full verification suite:
mix test
mix test --seed 12345
mix test --seed 99999
mix test --seed 1
mix dialyzer
mix credo --strict
mix compile --warnings-as-errors

ALL must pass. Fix any issues before proceeding.

Update CHECKLIST.md - mark Phase 1 & 2 complete.
Update CLAUDE.md/AGENTS.md with changes made.

---
Phase 3: Hexagonal Refactor

Step 3.1: Create Ports Directory

Note: the original tinkex does not have ports/adapters; they are created in this phase.

Create lib/tinkex/ports/ with behavior modules:

lib/tinkex/ports/http_transport.ex:
defmodule Tinkex.Ports.HTTPTransport do
@moduledoc "Port for HTTP transport operations."

@type method :: :get | :post | :put | :delete | :patch
@type headers :: [{String.t(), String.t()}]
@type response :: %{status: integer(), headers: headers(), body: term()}

@callback request(method(), String.t(), headers(), term(), keyword()) ::
    {:ok, response()} | {:error, term()}

@callback stream(method(), String.t(), headers(), term(), keyword()) ::
    {:ok, Enumerable.t()} | {:error, term()}
end

Create similar ports for:
- lib/tinkex/ports/retry_strategy.ex
- lib/tinkex/ports/circuit_breaker.ex
- lib/tinkex/ports/rate_limiter.ex
- lib/tinkex/ports/serializer.ex
- lib/tinkex/ports/telemetry.ex

Step 3.2: Create Adapters Directory

Create lib/tinkex/adapters/ with implementations:

lib/tinkex/adapters/finch_transport.ex:
defmodule Tinkex.Adapters.FinchTransport do
@moduledoc "Finch-based HTTP transport adapter."
@behaviour Tinkex.Ports.HTTPTransport

@impl true
def request(method, url, headers, body, opts) do
    # Implementation using Finch
end

@impl true
def stream(method, url, headers, body, opts) do
    # Implementation using Finch streaming
end
end

Create similar adapters for:
- lib/tinkex/adapters/foundation_retry.ex - wraps Foundation.Retry
- lib/tinkex/adapters/foundation_cb.ex - wraps Foundation.CircuitBreaker
- lib/tinkex/adapters/foundation_rate.ex - wraps Foundation.RateLimit
- lib/tinkex/adapters/jason_serializer.ex - wraps Jason

Step 3.3: Create Context

lib/tinkex/context.ex:
defmodule Tinkex.Context do
@moduledoc "Carries adapter configuration through the request pipeline."

defstruct [
    :config,
    transport: Tinkex.Adapters.FinchTransport,
    retry: Tinkex.Adapters.FoundationRetry,
    circuit_breaker: Tinkex.Adapters.FoundationCB,
    rate_limiter: Tinkex.Adapters.FoundationRate,
    serializer: Tinkex.Adapters.JasonSerializer,
    telemetry: Tinkex.Adapters.DefaultTelemetry
]

@type t :: %__MODULE__{...}

def new(config, opts \\ []) do
    %__MODULE__{
    config: config,
    transport: Keyword.get(opts, :transport, Tinkex.Adapters.FinchTransport),
    # ... etc
    }
end
end

Step 3.4: Reorganize Domain Logic

Move domain modules to lib/tinkex/domain/:

lib/tinkex/domain/
├── sampling/
│   └── client.ex      # From lib/tinkex/sampling_client.ex
├── training/
│   ├── client.ex      # From lib/tinkex/training_client.ex
│   └── custom_loss.ex # From lib/tinkex/training/custom_loss.ex
├── futures/
│   └── poller.ex      # From lib/tinkex/future.ex
└── rest/
    └── client.ex      # From lib/tinkex/rest_client.ex

Step 3.5: Refactor Clients to Use Context

Each client should:
1. Accept a Context (or build one from Config)
2. Use ports via context, never direct implementation
3. Have zero imports of infrastructure modules

Example pattern:
defmodule Tinkex.Domain.Sampling.Client do
alias Tinkex.Context

def sample(context, prompt, params, opts \\ []) do
    # Use context.transport for HTTP
    # Use context.retry for retry logic
    # Use context.circuit_breaker for CB
    # Never import Finch, Foundation, etc directly
end
end

Step 3.6: Delete Old API Layer

After refactoring is complete, delete:
- lib/tinkex/api/api.ex
- lib/tinkex/api/request.ex
- lib/tinkex/api/response.ex
- lib/tinkex/api/response_handler.ex
- lib/tinkex/api/compression.ex
- lib/tinkex/api/headers.ex
- lib/tinkex/api/url.ex
- lib/tinkex/api/helpers.ex
- lib/tinkex/api/telemetry.ex
- lib/tinkex/api/stream_response.ex

Keep (these become port implementations):
- lib/tinkex/api/sampling.ex → refactor to use ports
- lib/tinkex/api/training.ex → refactor to use ports
- lib/tinkex/api/futures.ex → refactor to use ports
- lib/tinkex/api/models.ex → refactor to use ports
- lib/tinkex/api/rest.ex → refactor to use ports

Verify after EACH deletion: mix test && mix compile

---
Phase 4: Stabilize

Run full verification suite:
mix test
mix test --seed 12345
mix dialyzer
mix credo --strict
mix compile --warnings-as-errors

Verify domain modules have ZERO infrastructure imports:
grep -r "Finch\|Foundation\|Jason" lib/tinkex/domain/
# Should return nothing (only Context references allowed)

Update CHECKLIST.md - mark Phase 3 & 4 complete.
Update CLAUDE.md/AGENTS.md.

---
Phase 5: Extract to Pristine

Step 5.1: Move Ports to Pristine

Copy lib/tinkex/ports/*.ex to ~/p/g/North-Shore-AI/pristine/lib/pristine/ports/

Update module names:
- Tinkex.Ports.HTTPTransport → Pristine.Ports.HTTPTransport
- etc.

Step 5.2: Move Adapters to Pristine

Copy lib/tinkex/adapters/*.ex to ~/p/g/North-Shore-AI/pristine/lib/pristine/adapters/

Update module names:
- Tinkex.Adapters.FinchTransport → Pristine.Adapters.Transport.Finch
- etc.

Step 5.3: Move Context to Pristine

Copy lib/tinkex/context.ex to ~/p/g/North-Shore-AI/pristine/lib/pristine/core/context.ex

Step 5.4: Update Tinkex to Use Pristine

In tinkex's mix.exs:
{:pristine, path: "../../pristine"},

Update all imports:
# OLD
alias Tinkex.Context
alias Tinkex.Ports.HTTPTransport

# NEW
alias Pristine.Core.Context
alias Pristine.Ports.HTTPTransport

Step 5.5: Create Manifest

Create lib/tinkex/manifest.yaml with ALL tinkex endpoints:
- List all 40+ API endpoints
- Define all request/response types
- Configure adapters, retry policies, circuit breakers, pools

See REPLACEMENT_MAP.md for endpoint list from lib/tinkex/api/*.ex

Verify both projects:
# In pristine
cd ~/p/g/North-Shore-AI/pristine && mix test && mix dialyzer

# In tinkex
cd ~/p/g/North-Shore-AI/tinkex && mix test && mix dialyzer

---
Phase 6: Thin Tinkex

Step 6.1: Generate Client from Manifest

mix pristine.generate --manifest lib/tinkex/manifest.yaml --output lib/tinkex/generated

Step 6.2: Delete Moved Infrastructure

Delete from tinkex (created in Phase 3 and moved in Phase 5; skip if not present):
- lib/tinkex/ports/
- lib/tinkex/adapters/
- lib/tinkex/context.ex

Step 6.3: Final Structure

Tinkex should have ONLY:
lib/tinkex/
├── manifest.yaml           # API definition
├── config.ex               # SDK config (keep)
├── error.ex                # Error types (keep)
├── generated/              # Generated from manifest
│   ├── client.ex
│   ├── sampling.ex
│   ├── training.ex
│   └── types/*.ex
├── domain/                 # Domain-specific (~200 lines total)
│   ├── tokenizer.ex        # TikToken integration
│   ├── byte_estimator.ex   # Token counting
│   └── model_input.ex      # Input transformation
└── types/                  # Keep domain types that aren't generated

Step 6.4: Final Verification

# Count hand-written lines (should be <500)
find lib/tinkex/domain -name "*.ex" | xargs wc -l

# All tests pass
mix test
mix test --seed 12345
mix test --seed 99999

# Code quality
mix dialyzer
mix credo --strict
mix compile --warnings-as-errors

---
Final Checklist

Before declaring complete:

- mix test passes (all ~1700 tests)
- mix test --seed N passes for multiple seeds
- mix dialyzer - zero errors
- mix credo --strict - zero issues
- mix compile --warnings-as-errors - zero warnings
- Hand-written tinkex code < 500 lines
- All infrastructure in Pristine
- CHECKLIST.md fully checked off
- CLAUDE.md/AGENTS.md updated with final state
- Pristine tests still pass: cd ~/p/g/North-Shore-AI/pristine && mix test

---
Troubleshooting

Test Failures

- Never skip failing tests
- Fix the test or the code, not both
- Check if the failure is seed-dependent: run with multiple seeds

Dialyzer Errors

- Usually type mismatches from API changes
- Add proper @spec annotations
- May need to update callback types in behaviours

Circular Dependencies

- Ports should have zero dependencies
- Adapters depend only on ports and external libs
- Domain depends on ports, never adapters directly

Foundation/Sinter API Differences

- Check the actual source in ~/p/g/n/foundation/ and ~/p/g/n/sinter/
- APIs may have slight differences from tinkex originals
- Adapt calling code to match library APIs

---
Context Summary

Goal: Pristine = thick infrastructure library. Tinkex = thin manifest + ~200 lines domain code.

Key insight: Tinkex's infrastructure (retry, circuit breaker, rate limiting, HTTP, streaming) is general-purpose. It belongs in Pristine. Only tokenizer/byte estimation/model input are tinkex-specific.

Work location: ~/p/g/North-Shore-AI/tinkex (original, not pristine/examples)

Dependencies:
- Foundation: retry, circuit breaker, rate limiting, semaphores
- Sinter: schema validation, transform, not_given
- Multipart_ex: multipart encoding
- Pristine: ports, adapters, context, pipeline, codegen

Success = tinkex is ~200-500 lines of hand-written domain code, everything else is generated or in Pristine.
