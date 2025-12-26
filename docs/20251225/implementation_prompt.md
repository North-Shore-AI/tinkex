# Tinkex Implementation Prompt

**For:** Fresh Agent Implementation of Tinkex Enhancements
**Date:** 2025-12-25
**Repository:** /home/home/p/g/North-Shore-AI/tinkex

---

## Mission Statement

You are implementing enhancements to Tinkex, the Elixir SDK for the Tinker ML Training and Inference API. This is a mature, production-ready library with ~20,000 lines of source code and ~9,500 lines of tests. Your task is to extend functionality while maintaining the high quality standards already established.

---

## Required Reading

Before making any changes, you MUST read and understand these files:

### Core Architecture (READ FIRST)
1. `/home/home/p/g/North-Shore-AI/tinkex/mix.exs` - Dependencies, version, config
2. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex.ex` - Main module facade
3. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/application.ex` - OTP supervision tree
4. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/config.ex` - Configuration system (647 lines)

### Primary Clients (READ CAREFULLY)
5. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/service_client.ex` - Session management (648 lines)
   - Lines 34-45: `start_link/1` entry point
   - Lines 46-80: `create_lora_training_client/3`
   - Lines 133-181: `create_sampling_client/2`
   - Lines 182-200: `create_rest_client/1`

6. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/training_client.ex` - Training operations (1044 lines)
   - Lines 161-186: `forward_backward/4`
   - Lines 187-201: `forward/4`
   - Lines 202-218: `optim_step/3`
   - Lines 219-271: `save_weights_for_sampler/3`
   - Lines 351-410: `forward_backward_custom/4`

7. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/sampling_client.ex` - Inference (552 lines)
   - Lines 103-117: `sample/4`
   - Lines 118-132: `compute_logprobs/3`

8. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/rest_client.ex` - REST operations (533 lines)

### API Layer (UNDERSTAND PATTERNS)
9. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/api.ex` - HTTP client (317 lines)
10. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/retry.ex` - Retry logic
11. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/headers.ex` - Header construction

### Type System (FOLLOW CONVENTIONS)
12. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/datum.ex` - Training data type
13. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/model_input.ex` - Prompt type
14. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/sampling_params.ex` - Sampling config
15. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/sample_response.ex` - Response type

### Supporting Infrastructure
16. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/future.ex` - Async polling (448 lines)
17. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/tokenizer.ex` - Tokenization (380 lines)
18. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry.ex` - Observability (126 lines)
19. `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/recovery/policy.ex` - Recovery config

### Test Patterns (FOLLOW STYLE)
20. `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/training_client_test.exs` - Training tests (713 lines)
21. `/home/home/p/g/North-Shore-AI/tinkex/test/tinkex/sampling_client_test.exs` - Sampling tests
22. `/home/home/p/g/North-Shore-AI/tinkex/test/support/http_case.ex` - Test helper with Bypass

### Documentation Examples
23. `/home/home/p/g/North-Shore-AI/tinkex/docs/guides/api_reference.md` - API overview
24. `/home/home/p/g/North-Shore-AI/tinkex/docs/guides/getting_started.md` - Quick start

---

## Current Module Structure

```
lib/tinkex/
├── tinkex.ex                    # Facade module
├── application.ex               # OTP application (supervises pools, ETS, managers)
├── config.ex                    # Config struct with env/app fallbacks
├── service_client.ex            # GenServer: session management, client factory
├── training_client.ex           # GenServer: forward_backward, optim_step, save_weights
├── sampling_client.ex           # Stateless: sample/4, compute_logprobs/3
├── rest_client.ex               # Struct-based REST client
├── future.ex                    # Task-based polling abstraction
├── tokenizer.ex                 # HuggingFace + Kimi K2 tokenization
├── session_manager.ex           # Session lifecycle + heartbeats
├── checkpoint_download.ex       # Streaming archive downloads
├── cli.ex                       # Escript entrypoint
│
├── api/                         # Low-level HTTP layer
│   ├── api.ex                   # Main HTTP client (implements HTTPClient behaviour)
│   ├── futures.ex               # Future retrieval
│   ├── headers.ex               # Header construction
│   ├── helpers.ex               # Shared utilities
│   ├── models.ex                # Model endpoints
│   ├── rest.ex                  # REST endpoints
│   ├── retry.ex                 # Exponential backoff retry
│   ├── sampling.ex              # Sampling endpoints
│   ├── service.ex               # Service endpoints (health, capabilities)
│   ├── session.ex               # Session endpoints
│   ├── training.ex              # Training endpoints
│   ├── weights.ex               # Weights endpoints
│   ├── compression.ex           # Gzip handling
│   ├── response_handler.ex      # Response parsing
│   ├── request.ex               # Request preparation
│   ├── url.ex                   # URL building
│   └── stream_response.ex       # SSE response wrapper
│
├── types/                       # 65 type modules (request/response structs)
│   ├── adam_params.ex
│   ├── checkpoint.ex
│   ├── datum.ex
│   ├── forward_backward_*.ex
│   ├── model_input.ex
│   ├── sample_*.ex
│   ├── sampling_params.ex
│   ├── tensor_data.ex
│   ├── training_run.ex
│   └── ... (60+ more)
│
├── regularizers/                # Nx-based regularization
├── regularizer/                 # Regularizer pipeline
├── training/                    # Training utilities
├── training_client/             # TrainingClient internals
├── telemetry/                   # Observability infrastructure
├── recovery/                    # Crash recovery system
├── files/                       # File handling
├── multipart/                   # Multipart form encoding
├── streaming/                   # SSE decoder
└── (supporting modules)
```

---

## API Coverage Summary

### Implemented Endpoints

| Category | Endpoint | Module |
|----------|----------|--------|
| Session | `POST /api/v1/create_session` | `API.Session` |
| Session | `POST /api/v1/session_heartbeat` | `API.Session` |
| Session | `GET /api/v1/sessions` | `API.Rest` |
| Session | `GET /api/v1/sessions/:id` | `API.Rest` |
| Model | `POST /api/v1/create_model` | `API.Models` |
| Model | `POST /api/v1/get_info` | `API.Models` |
| Model | `POST /api/v1/unload_model` | `API.Models` |
| Training | `POST /api/v1/forward_backward` | `API.Training` |
| Training | `POST /api/v1/forward` | `API.Training` |
| Training | `POST /api/v1/optim_step` | `API.Training` |
| Weights | `POST /api/v1/save_weights` | `API.Weights` |
| Weights | `POST /api/v1/load_weights` | `API.Weights` |
| Sampling | `POST /api/v1/create_sampling_session` | `API.Sampling` |
| Sampling | `POST /api/v1/sample` | `API.Sampling` |
| Checkpoint | `GET /api/v1/checkpoints` | `API.Rest` |
| Checkpoint | `DELETE /api/v1/checkpoints/:id` | `API.Rest` |
| Checkpoint | `POST /api/v1/publish_checkpoint` | `API.Rest` |
| Future | `POST /api/v1/retrieve_future` | `API.Futures` |
| Service | `GET /api/v1/health` | `API.Service` |
| Service | `GET /api/v1/capabilities` | `API.Service` |

---

## Integration with crucible_train

### Adapter Pattern

Tinkex is used by `tinkex_cookbook` for training recipes. The integration pattern is:

```elixir
# In tinkex_cookbook recipes
alias Tinkex.{ServiceClient, TrainingClient, SamplingClient}

# 1. Create service client
{:ok, service} = ServiceClient.start_link(config: Tinkex.Config.new())

# 2. Create training client for LoRA
{:ok, trainer} = ServiceClient.create_lora_training_client(service, base_model, lora_config: lora)

# 3. Training loop
for batch <- batches do
  data = Enum.map(batch, &build_datum/1)
  {:ok, task} = TrainingClient.forward_backward(trainer, data, loss_fn)
  {:ok, result} = Task.await(task)

  {:ok, optim_task} = TrainingClient.optim_step(trainer, adam_params)
  {:ok, _} = Task.await(optim_task)
end

# 4. Save checkpoint
{:ok, save_task} = TrainingClient.save_weights_for_sampler(trainer, "checkpoint-name")
{:ok, result} = Task.await(save_task)
```

### Future Adapter Interface

Consider implementing this behaviour for crucible integration:

```elixir
defmodule Tinkex.Adapters.TrainingPlatform do
  @callback create_session(config :: map()) :: {:ok, session} | {:error, term()}
  @callback forward_backward(session, data :: [Datum.t()], loss_fn :: atom()) :: {:ok, result}
  @callback optim_step(session, params :: AdamParams.t()) :: {:ok, result}
  @callback save_checkpoint(session, name :: String.t()) :: {:ok, path}
end
```

---

## TDD Approach

### Test-First Requirements

1. **Write tests BEFORE implementation**
2. **Follow existing test patterns** in `test/tinkex/`
3. **Use Bypass for HTTP mocking** (see `test/support/http_case.ex`)

### Test Structure

```elixir
defmodule Tinkex.NewFeatureTest do
  use Tinkex.HTTPCase, async: false  # Use HTTPCase for HTTP tests

  alias Tinkex.{Config, NewFeature}

  setup :setup_http_client  # Sets up Bypass and config

  describe "new_function/2" do
    test "returns expected result on success", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        # Mock HTTP response
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result": "success"}))
      end)

      # Call function
      assert {:ok, result} = NewFeature.new_function(arg1, config: config)
      assert result.field == expected_value
    end

    test "handles error response", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, fn conn ->
        conn
        |> Plug.Conn.resp(500, "Internal error")
      end)

      assert {:error, %Tinkex.Error{}} = NewFeature.new_function(arg1, config: config)
    end
  end
end
```

### Test Categories

1. **Unit tests** - Single function behavior
2. **Integration tests** - Multi-module flows
3. **Error handling tests** - All error paths
4. **Concurrency tests** - Race conditions, deadlocks
5. **Parity tests** - Compare to Python SDK behavior

---

## Quality Requirements

### Mandatory Checks

Before any PR, ALL of these must pass:

```bash
# 1. Compile without warnings
mix compile --warnings-as-errors

# 2. Run all tests
mix test

# 3. Static analysis (Dialyzer)
mix dialyzer

# 4. Code style (Credo strict)
mix credo --strict

# 5. Formatting
mix format --check-formatted
```

### Code Standards

1. **Typespecs on all public functions**
2. **@moduledoc on all modules**
3. **@doc on all public functions**
4. **Handle all error cases explicitly**
5. **Use pattern matching, not conditionals**
6. **Avoid `with` chains longer than 5 clauses**
7. **Name functions with verbs** (`get_*`, `create_*`, `update_*`)

### Error Handling Pattern

```elixir
# Always use tagged tuples
{:ok, result} | {:error, %Tinkex.Error{}}

# Create errors with:
Tinkex.Error.new(type, message, opts \\ [])

# Types: :validation, :api_connection, :api_status, :api_timeout, :request_failed
```

---

## Common Implementation Patterns

### GenServer Client

```elixir
defmodule Tinkex.NewClient do
  use GenServer

  @doc """
  Start a new client.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    GenServer.start_link(__MODULE__, %{config: config})
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @doc """
  Perform operation.
  """
  @spec operation(pid(), arg :: term()) :: {:ok, result} | {:error, Tinkex.Error.t()}
  def operation(pid, arg) do
    GenServer.call(pid, {:operation, arg})
  end

  @impl true
  def handle_call({:operation, arg}, _from, state) do
    result = do_operation(arg, state.config)
    {:reply, result, state}
  end
end
```

### Async Operation with Future

```elixir
def async_operation(pid, arg) do
  GenServer.call(pid, {:async_operation, arg})
end

@impl true
def handle_call({:async_operation, arg}, _from, state) do
  case API.submit_request(arg, config: state.config) do
    {:ok, %{"request_id" => request_id}} ->
      task = Tinkex.Future.poll(request_id, config: state.config)
      {:reply, {:ok, task}, state}

    {:error, _} = error ->
      {:reply, error, state}
  end
end
```

### Type Definition

```elixir
defmodule Tinkex.Types.NewType do
  @moduledoc """
  Description of the type.
  """

  @derive Jason.Encoder
  defstruct [:field1, :field2, field3: default_value]

  @type t :: %__MODULE__{
          field1: String.t(),
          field2: integer() | nil,
          field3: boolean()
        }

  @doc """
  Create from JSON map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      field1: Map.get(map, "field1") || Map.get(map, :field1),
      field2: Map.get(map, "field2") || Map.get(map, :field2),
      field3: Map.get(map, "field3", default_value)
    }
  end
end
```

---

## README Update Requirements

When adding features, update `/home/home/p/g/North-Shore-AI/tinkex/README.md`:

1. Add to feature list if significant
2. Add usage example if user-facing
3. Update version compatibility if needed
4. Add to "What's New" section if applicable

---

## Task Template

When implementing a new feature:

```markdown
## Task: [Feature Name]

### 1. Understanding (Read First)
- [ ] Read relevant existing modules
- [ ] Understand current patterns
- [ ] Identify integration points

### 2. Design
- [ ] Define types needed
- [ ] Define function signatures
- [ ] Plan error handling
- [ ] Consider telemetry events

### 3. Tests First (TDD)
- [ ] Write happy path test
- [ ] Write error handling tests
- [ ] Write edge case tests
- [ ] Verify tests fail

### 4. Implementation
- [ ] Implement types
- [ ] Implement core logic
- [ ] Add documentation
- [ ] Verify tests pass

### 5. Quality Checks
- [ ] mix compile --warnings-as-errors
- [ ] mix test
- [ ] mix dialyzer
- [ ] mix credo --strict
- [ ] mix format

### 6. Documentation
- [ ] Update README if needed
- [ ] Add guide if significant feature
- [ ] Update CHANGELOG
```

---

## Specific Enhancement Tasks

### Task 1: Streaming Sampling

**Goal:** Add `sample_stream/4` for real-time token streaming

**Files to modify:**
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/sampling_client.ex`
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/sampling.ex`
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/streaming/sse_decoder.ex`

**New files:**
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/types/sample_stream_response.ex`

### Task 2: OpenTelemetry Integration

**Goal:** Add opt-in OpenTelemetry trace propagation

**Files to modify:**
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/headers.ex`
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/config.ex`

**New files:**
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/telemetry/otel.ex`

### Task 3: Circuit Breaker

**Goal:** Add per-endpoint circuit breaker

**Files to modify:**
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/api/retry.ex`
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/application.ex`

**New files:**
- `/home/home/p/g/North-Shore-AI/tinkex/lib/tinkex/circuit_breaker.ex`

---

## Contact Points

- **tinkex_cookbook:** `/home/home/p/g/North-Shore-AI/tinkex_cookbook` - Uses Tinkex for training recipes
- **Existing guides:** `/home/home/p/g/North-Shore-AI/tinkex/docs/guides/`
- **Examples:** `/home/home/p/g/North-Shore-AI/tinkex/examples/`

---

## Final Checklist

Before submitting any changes:

- [ ] All tests pass: `mix test`
- [ ] No warnings: `mix compile --warnings-as-errors`
- [ ] Dialyzer clean: `mix dialyzer`
- [ ] Credo strict: `mix credo --strict`
- [ ] Formatted: `mix format`
- [ ] Docs generate: `mix docs`
- [ ] README updated if needed
- [ ] CHANGELOG updated
