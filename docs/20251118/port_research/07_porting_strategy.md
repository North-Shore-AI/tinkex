# Porting Strategy and Implementation Roadmap

**⚠️ UPDATED:** This document has been corrected based on critiques 100-102, 200-202, 300-302, 400+. See response documents for details.

**Key Corrections (Round 1 - Critiques 100-102):**
- **Validation**: Changed from Ecto to pure functions (lighter dependencies)
- **Finch pools**: Updated to show separate pool configuration
- **Tokenizer strategy**: Changed from "user responsibility" to built-in tokenization support

**Key Corrections (Round 2 - Critiques 200-202):**
- **Dependencies**: Removed Bumblebee and EXLA (bloat) - using tokenizers-only for lean integration
- **SamplingClient architecture**: Changed to ETS-based for lock-free concurrent reads
- **RateLimiter**: Added atomics-based shared backoff state module
- **Telemetry pool**: Added dedicated pool to prevent telemetry from starving other operations

**Key Corrections (Round 3 - Critiques 300-302):**
- **Custom loss deferred**: Explicitly moved custom loss functions to v2.0 (requires EXLA, out of v1 scope)
- **Timeline adjusted**: v1.0 scope reduced, realistic 8-week estimate with defined scope cuts
- **ETS table creation**: Global tables in Application.start/2 documented
- **Error handling**: Task.start bodies wrapped in try/rescue throughout

**Key Corrections (Round 4 - Critique 400+):**
- **JSON encoding**: Removed global nil-stripping - Python SDK accepts `null` for Optional fields
- **Error categories**: All references updated from `USER_ERROR/TRANSIENT/FATAL` to `Unknown/Server/User`
- **429 handling**: Wired retry_after_ms from errors to RateLimiter instead of hard-coded values
- **Config threading**: Centralized config struct, removed Application.get_env from API layer
- **PoolKey module**: Single source of truth for URL normalization and pool key generation
- **Task.start safety**: All async GenServer.reply patterns now have mandatory try/rescue wrappers
- **API consistency**: All public client methods return Task.t({:ok, ...} | {:error, ...})

## Technology Stack Recommendations

### Core Dependencies ⚠️ UPDATED

```elixir
# mix.exs
defp deps do
  [
    # HTTP/2 client
    {:finch, "~> 0.16"},

    # JSON encoding/decoding
    {:jason, "~> 1.4"},

    # Numerical computing (tensor operations)
    {:nx, "~> 0.6"},

    # Tokenization (HuggingFace models) ⚠️ UPDATED - tokenizers-only
    {:tokenizers, "~> 0.4"},     # Rust-based tokenizers via NIF (lean, no Bumblebee/EXLA bloat)

    # Telemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_poller, "~> 1.0"},

    # CLI
    {:optimus, "~> 0.3"},  # or {:ex_cli, "~> 0.6"}

    # Development
    {:dialyxir, "~> 1.4", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.30", only: :dev, runtime: false},

    # Testing
    {:mox, "~> 1.0", only: :test},
    {:bypass, "~> 2.1", only: :test},  # Mock HTTP server
  ]
end
```

**Notes:**
- **Ecto** has been REMOVED from core deps and moved to optional. Using pure functions for validation keeps the SDK lighter.
- **Bumblebee and EXLA** have been REMOVED (Round 2 correction). These add 100+ MB of dependencies for features not needed by the SDK. Using `tokenizers` directly provides lean HuggingFace tokenizer access without the overhead.

### Optional Libraries

```elixir
# Enhanced struct definitions
{:typed_struct, "~> 0.3"},

# Schema validation (if needed for complex cases) ⚠️ MOVED FROM CORE
{:ecto, "~> 3.10"},

# Advanced validation
{:vex, "~> 0.9"},

# Better CLI output
{:table_rex, "~> 3.1"},

# Progress bars (for CLI)
{:progress_bar, "~> 3.0"}
```

## Project Structure

```
tinkex/
├── lib/
│   ├── tinkex.ex                      # Main module, public API
│   ├── tinkex/
│   │   ├── application.ex             # OTP application
│   │   ├── supervisor.ex              # Top-level supervisor
│   │   │
│   │   ├── service_client.ex          # ServiceClient GenServer
│   │   ├── training_client.ex         # TrainingClient GenServer
│   │   ├── sampling_client.ex         # SamplingClient GenServer
│   │   ├── rest_client.ex             # RestClient module
│   │   │
│   │   ├── api/                       # Low-level HTTP API
│   │   │   ├── api.ex                 # Base API module
│   │   │   ├── training.ex            # Training endpoints
│   │   │   ├── sampling.ex            # Sampling endpoints
│   │   │   ├── service.ex             # Service endpoints
│   │   │   ├── models.ex              # Model management
│   │   │   ├── weights.ex             # Weight operations
│   │   │   └── futures.ex             # Future retrieval
│   │   │
│   │   ├── types/                     # Type definitions
│   │   │   ├── types.ex               # Main types module
│   │   │   ├── requests/              # Request types
│   │   │   │   ├── forward_backward_request.ex
│   │   │   │   ├── sample_request.ex
│   │   │   │   └── ...
│   │   │   ├── responses/             # Response types
│   │   │   │   ├── forward_backward_output.ex
│   │   │   │   ├── sample_response.ex
│   │   │   │   └── ...
│   │   │   └── data/                  # Data structures
│   │   │       ├── model_input.ex
│   │   │       ├── datum.ex
│   │   │       ├── tensor_data.ex
│   │   │       └── ...
│   │   │
│   │   ├── future.ex                  # Future/Task utilities
│   │   ├── error.ex                   # Error types
│   │   ├── retry.ex                   # Retry logic
│   │   ├── session_manager.ex         # Session lifecycle GenServer
│   │   │
│   │   ├── telemetry/                 # Telemetry
│   │   │   ├── telemetry.ex           # Setup
│   │   │   ├── metrics.ex             # Metrics definitions
│   │   │   └── reporter.ex            # Server reporter
│   │   │
│   │   └── cli/                       # CLI
│   │       ├── cli.ex                 # Main CLI module
│   │       ├── commands/              # CLI commands
│   │       │   ├── checkpoint.ex
│   │       │   ├── run.ex
│   │       │   └── version.ex
│   │       └── output.ex              # Output formatting
│   │
├── test/
│   ├── tinkex_test.exs
│   ├── tinkex/
│   │   ├── service_client_test.exs
│   │   ├── training_client_test.exs
│   │   ├── sampling_client_test.exs
│   │   ├── api_test.exs
│   │   └── ...
│   └── support/
│       ├── mock_server.ex             # Mock Tinker API server
│       └── fixtures.ex                # Test fixtures
│
├── docs/                              # Documentation
│   └── guides/
│       ├── getting_started.md
│       ├── training.md
│       ├── sampling.md
│       └── advanced.md
│
├── mix.exs
├── README.md
└── LICENSE
```

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Goal**: Basic infrastructure and type system

#### Tasks:
1. ✅ Project setup
   - [x] Initialize mix project
   - [x] Add dependencies
   - [x] Setup CI/CD (GitHub Actions)
   - [x] Configure Dialyzer

2. ✅ Type definitions (30-40 types)
   - [x] Core data structures (`ModelInput`, `Datum`, `TensorData`)
   - [x] Request types (`ForwardBackwardRequest`, `SampleRequest`, etc.)
   - [x] Response types (`ForwardBackwardOutput`, `SampleResponse`, etc.)
   - [x] Enum types (`LossFnType`, `StopReason`, etc.)

3. ✅ HTTP layer
   - [x] Finch integration
   - [x] Base API module with retry logic
   - [x] Error types and handling
   - [x] JSON encoding/decoding

4. ✅ Testing infrastructure
   - [x] Mock HTTP server (Bypass)
   - [x] Test fixtures
   - [x] Basic integration tests

**Deliverables:**
- All type modules with tests
- Working HTTP client with retry
- 70%+ test coverage

### Phase 2: Client Implementation (Week 3-4)

**Goal**: Implement core client GenServers

#### Tasks:
1. ✅ SessionManager
   - [x] Session creation
   - [x] Heartbeat mechanism
   - [x] Session cleanup

2. ✅ ServiceClient
   - [x] GenServer implementation
   - [x] Create training client
   - [x] Create sampling client
   - [x] Integration tests

3. ✅ Future/polling mechanism
   - [x] `Tinkex.Future` module
   - [x] Polling with exponential backoff
   - [x] Timeout handling
   - [x] Combined futures

4. ✅ Error handling
   - [x] Custom error types
   - [x] Retry strategies
   - [x] User error detection

**Deliverables:**
- Working SessionManager
- ServiceClient with client creation
- Future polling mechanism
- 75%+ test coverage

### Phase 3: Training Operations (Week 5-6) ⚠️ UPDATED

**Goal**: Implement TrainingClient with full functionality

#### Tasks:
1. ✅ TrainingClient GenServer
   - [x] Request sequencing (sequential sends, concurrent polling)
   - [x] Data chunking
   - [x] State management

2. ✅ Training operations
   - [x] `forward/3` - forward pass
   - [x] `forward_backward/3` - forward + backward pass
   - [x] `optim_step/2` - optimizer step
   - [x] Result combining for chunked requests

3. ✅ Tokenizer integration ⚠️ UPDATED - tokenizers-only (no Bumblebee)
   - [x] Direct tokenizers NIF integration
   - [x] `Tinkex.Tokenizer` module (wrapper around tokenizers library)
   - [x] `ModelInput.from_text/2` helper using tokenizers.from_pretrained
   - [x] Support for model-specific tokenizers (Qwen, Llama, etc.)

4. ✅ Weight management
   - [x] `save_state/2` - save checkpoint
   - [x] `load_state/2` - load checkpoint
   - [x] `save_weights_for_sampler/2` - prepare for inference

5. ✅ Telemetry integration
   - [x] Training operation metrics
   - [x] Loss tracking
   - [x] Request duration

**Deliverables:**
- Fully functional TrainingClient
- All training operations working
- Tokenization support for common models
- Weight save/load tested
- 80%+ test coverage

### Phase 4: Sampling Operations (Week 7) ⚠️ UPDATED

**Goal**: Implement SamplingClient with ETS-based architecture

#### Tasks:
1. ✅ SamplingClient GenServer ⚠️ UPDATED - ETS-based
   - [x] ETS table for lock-free config reads
   - [x] Sampling session management
   - [x] Request handling (direct ETS reads, no GenServer calls)
   - [x] RateLimiter module with atomics-based shared backoff

2. ✅ Sampling operations
   - [x] `sample/4` - text generation (reads ETS directly)
   - [x] `compute_logprobs/1` - get prompt logprobs
   - [x] Shared rate limit backoff across concurrent requests

3. ✅ Testing
   - [x] Mock sampling responses
   - [x] Concurrent sampling tests
   - [x] Error handling tests

**Deliverables:**
- Working SamplingClient
- Sampling operations tested
- 80%+ test coverage

### Phase 5: CLI and Documentation (Week 8)

**Goal**: CLI tools and comprehensive docs

#### Tasks:
1. ✅ CLI implementation
   - [x] Command structure
   - [x] `checkpoint` command
   - [x] `run` command
   - [x] `version` command

2. ✅ Documentation
   - [x] Module documentation (ExDoc)
   - [x] Getting started guide
   - [x] Training guide
   - [x] Sampling guide
   - [x] API reference

3. ✅ Examples
   - [x] Basic training example
   - [x] Sampling example
   - [x] End-to-end workflow

**Deliverables:**
- Working CLI
- Complete documentation
- Example scripts
- Published to hex.pm (optional)

## Key Design Decisions

### 1. Supervision Strategy ⚠️ UPDATED

```elixir
defmodule Tinkex.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    base_url = Application.get_env(:tinkex, :base_url,
      "https://tinker.thinkingmachines.dev/services/tinker-prod")

    children = [
      # HTTP pool with SEPARATE pools per operation type
      {Finch, name: Tinkex.HTTP.Pool, pools: pool_config(base_url)},

      # Session manager
      Tinkex.SessionManager,

      # Telemetry reporter
      Tinkex.Telemetry.Reporter,

      # Dynamic supervisor for clients
      {DynamicSupervisor,
       name: Tinkex.ClientSupervisor,
       strategy: :one_for_one,
       max_restarts: 3,
       max_seconds: 5}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp pool_config(base_url) do
    # ⚠️ UPDATED: Added telemetry pool (Round 2)
    %{
      default: [protocol: :http2, size: 10, max_idle_time: 60_000],
      {base_url, :training} => [size: 5, count: 1, max_idle_time: 60_000],
      {base_url, :sampling} => [size: 100, max_idle_time: 30_000],
      {base_url, :session} => [size: 5, max_idle_time: :infinity],
      {base_url, :futures} => [size: 50, max_idle_time: 60_000],
      {base_url, :telemetry} => [size: 5, max_idle_time: 60_000]  # Prevent telemetry from starving other ops
    }
  end
end
```

### 2. Client API Style

**Return Tasks, not Results:**

```elixir
# Good: Return Task
def forward_backward(client, data, loss_fn, opts \\ []) do
  Task.async(fn ->
    GenServer.call(client, {:forward_backward, data, loss_fn, opts}, :infinity)
  end)
end

# Caller decides sync or async
task = TrainingClient.forward_backward(client, data, :cross_entropy)
result = Task.await(task)  # Sync
# or handle async with receive/Task.await_many
```

**Benefits:**
- Consistent API
- Caller controls blocking behavior
- Natural concurrency
- Composable with Task.await_many

### 3. Configuration

```elixir
# config/config.exs
config :tinkex,
  base_url: "https://tinker.thinkingmachines.dev/services/tinker-prod",
  timeout: 120_000,
  max_retries: 2,
  telemetry_enabled: true

# config/runtime.exs
import Config

config :tinkex,
  api_key: System.get_env("TINKER_API_KEY"),
  cloudflare_client_id: System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID"),
  cloudflare_client_secret: System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET")
```

### 4. Nx Integration ⚠️ CORRECTED

For tensor operations:

```elixir
defmodule Tinkex.Types.TensorData do
  @moduledoc "Numerical tensor data"

  defstruct [:data, :dtype, :shape]

  # ONLY 2 types supported by backend (not 4!)
  @type dtype :: :int64 | :float32
  @type t :: %__MODULE__{
    data: list(number()),
    dtype: dtype(),
    shape: list(non_neg_integer())
  }

  @doc "Create TensorData from Nx tensor"
  def from_nx(%Nx.Tensor{} = tensor) do
    %__MODULE__{
      data: Nx.to_flat_list(tensor),
      dtype: nx_dtype_to_tensor_dtype(tensor.type),
      shape: Tuple.to_list(tensor.shape)
    }
  end

  @doc "Convert to Nx tensor"
  def to_nx(%__MODULE__{} = tensor_data) do
    tensor_data.data
    |> Nx.tensor(type: tensor_dtype_to_nx(tensor_data.dtype))
    |> Nx.reshape(List.to_tuple(tensor_data.shape))
  end

  # Only map supported types (int64, float32)
  defp nx_dtype_to_tensor_dtype({:f, 32}), do: :float32
  defp nx_dtype_to_tensor_dtype({:f, 64}), do: :float32  # Downcast to float32
  defp nx_dtype_to_tensor_dtype({:s, 32}), do: :int64    # Upcast to int64
  defp nx_dtype_to_tensor_dtype({:s, 64}), do: :int64

  defp tensor_dtype_to_nx(:float32), do: {:f, 32}
  defp tensor_dtype_to_nx(:int64), do: {:s, 64}
end
```

## Testing Strategy

### Unit Tests

```elixir
defmodule Tinkex.Types.ModelInputTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{ModelInput, EncodedTextChunk}

  describe "from_ints/1" do
    test "creates ModelInput from token list" do
      tokens = [1, 2, 3, 4, 5]
      model_input = ModelInput.from_ints(tokens)

      assert %ModelInput{chunks: [%EncodedTextChunk{tokens: ^tokens}]} = model_input
    end
  end

  describe "length/1" do
    test "returns total token count" do
      model_input = ModelInput.from_ints([1, 2, 3])
      assert ModelInput.length(model_input) == 3
    end
  end
end
```

### Integration Tests

```elixir
defmodule Tinkex.ServiceClientTest do
  use ExUnit.Case

  setup do
    bypass = Bypass.open()

    # Configure to use bypass URL
    Application.put_env(:tinkex, :base_url, "http://localhost:#{bypass.port}")

    {:ok, bypass: bypass}
  end

  test "creates training client", %{bypass: bypass} do
    # Mock session creation
    Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
      Plug.Conn.resp(conn, 200, Jason.encode!(%{
        "session_id" => "test-session",
        "info_message" => nil,
        "warning_message" => nil,
        "error_message" => nil
      }))
    end)

    # Mock model creation
    Bypass.expect_once(bypass, "POST", "/api/v1/create_model", fn conn ->
      Plug.Conn.resp(conn, 200, Jason.encode!(%{
        "model_id" => "test-model-123"
      }))
    end)

    {:ok, service} = Tinkex.ServiceClient.start_link()

    {:ok, training_client} = Tinkex.ServiceClient.create_lora_training_client(
      service,
      base_model: "test-model",
      rank: 32
    )

    assert is_pid(training_client)
  end
end
```

## Documentation Standards

### Module Documentation

```elixir
defmodule Tinkex.TrainingClient do
  @moduledoc """
  Client for ML model training operations.

  The TrainingClient manages a specific fine-tuned model instance and provides
  methods for:

  - Forward and backward passes for gradient computation
  - Optimizer steps for parameter updates
  - Saving and loading model weights
  - Creating sampling clients from trained weights

  ## Example

      # Create a training client
      {:ok, service} = Tinkex.ServiceClient.start_link()
      {:ok, training} = Tinkex.ServiceClient.create_lora_training_client(
        service,
        base_model: "Qwen/Qwen2.5-7B",
        rank: 32
      )

      # Run forward-backward pass
      datum = %Tinkex.Types.Datum{
        model_input: Tinkex.Types.ModelInput.from_ints(tokens),
        loss_fn_inputs: %{target_tokens: target_tokens}
      }

      task = Tinkex.TrainingClient.forward_backward(training, [datum], :cross_entropy)
      {:ok, result} = Task.await(task)

      # Update parameters
      task = Tinkex.TrainingClient.optim_step(training, %Tinkex.Types.AdamParams{
        learning_rate: 1.0e-4
      })
      {:ok, _response} = Task.await(task)

  ## All operations return Tasks

  All TrainingClient operations return `Task.t()` which must be awaited:

      task = TrainingClient.forward_backward(...)
      result = Task.await(task)

  This allows for flexible concurrency control at the caller's discretion.
  """
```

### Function Documentation

```elixir
@doc """
Perform forward and backward pass to compute gradients.

Processes the provided training data through the model, computes the loss
using the specified loss function, and calculates gradients via backpropagation.

Large batches are automatically chunked (max 128 examples per chunk) and
processed sequentially to stay within API limits.

## Parameters

  * `client` - The TrainingClient GenServer pid
  * `data` - List of `Tinkex.Types.Datum` training examples
  * `loss_fn` - Loss function to use (`:cross_entropy`)
  * `opts` - Optional keyword list:
    * `:loss_fn_config` - Additional loss function configuration (default: `nil`)

## Returns

Returns a `Task.t()` that resolves to:

  * `{:ok, %Tinkex.Types.ForwardBackwardOutput{}}` - Success with loss and gradients
  * `{:error, %Tinkex.Error{}}` - Failure with error details

## Examples

    datum = %Datum{
      model_input: ModelInput.from_ints([1, 2, 3]),
      loss_fn_inputs: %{target_tokens: [2, 3, 4]}
    }

    task = TrainingClient.forward_backward(client, [datum], :cross_entropy)

    case Task.await(task) do
      {:ok, output} ->
        IO.puts("Loss: \#{output.loss}")

      {:error, error} ->
        IO.puts("Error: \#{error.message}")
    end
"""
@spec forward_backward(
  t(),
  [Tinkex.Types.Datum.t()],
  atom(),
  keyword()
) :: Task.t({:ok, Tinkex.Types.ForwardBackwardOutput.t()} | {:error, Tinkex.Error.t()})
def forward_backward(client, data, loss_fn, opts \\ []) do
  # ...
end
```

## Challenges and Solutions

### Challenge 1: Background Event Loop

**Python:** Uses dedicated thread with asyncio event loop

**Elixir Solution:** Not needed! Processes are lightweight and concurrent by nature. Each client GenServer has its own process.

### Challenge 2: Request Sequencing

**Python:** Complex turn-taking with locks and events

**Elixir Solution:** GenServer mailbox provides natural sequencing. Send messages in order, they're processed in order.

### Challenge 3: Connection Pooling ⚠️ CORRECTED

**Python:** Manual pool management per operation type (training, sampling, session, futures)

**Elixir Solution:** Finch with MULTIPLE pools keyed by `{base_url, pool_type}` for resource isolation. This prevents sampling bursts from starving critical session heartbeats.

### Challenge 4: Dual Sync/Async API

**Python:** Separate `func()` and `func_async()` methods

**Elixir Solution:** Single API returning Tasks. Caller decides sync (`Task.await`) or async (spawn, receive, etc.)

### Challenge 5: Tokenizer Integration ⚠️ UPDATED (Round 2)

**Python:** Direct HuggingFace transformers integration

**Elixir Solution (UPDATED - tokenizers-only):**
Use **tokenizers** directly (no Bumblebee/EXLA bloat):

```elixir
# Dependencies
{:tokenizers, "~> 0.4"}, # Rust tokenizers via NIF (lean, ~5MB)

# Usage
defmodule Tinkex.Tokenizer do
  @moduledoc "Lean tokenizer wrapper using tokenizers NIF"

  def encode(text, model_name) do
    # Load tokenizer from HuggingFace Hub
    {:ok, tokenizer} = Tokenizers.Tokenizer.from_pretrained(model_name)
    {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, text)
    Tokenizers.Encoding.get_ids(encoding)
  end
end

# Public API
Tinkex.Types.ModelInput.from_text("Hello world", tokenizer: "Qwen/Qwen2.5-7B")
```

**Why tokenizers-only (no Bumblebee)?**
- **Bumblebee** adds 100+ MB of dependencies (EXLA, XLA compiler, etc.) for model inference features
- **This SDK only needs tokenization** - we don't run models locally, just send tokens to API
- **tokenizers** NIF provides direct access to HuggingFace tokenizers with ~5MB footprint
- **Production-ready**: Same Rust tokenizers used by Python transformers library

**Why this matters:** Without built-in tokenization, users must set up Python bridges, making the SDK unusable for pure Elixir projects. Direct tokenizers NIF provides a lean, production-ready solution.

## Success Criteria

### Functionality
- ✅ All core operations match Python SDK
- ✅ Training client fully functional
- ✅ Sampling client fully functional
- ✅ CLI tools working

### Quality
- ✅ 80%+ test coverage
- ✅ Dialyzer clean
- ✅ Comprehensive documentation
- ✅ Example scripts

### Performance
- ✅ Comparable latency to Python SDK
- ✅ Efficient memory usage
- ✅ Handles concurrent operations

### Maintainability
- ✅ Clear module boundaries
- ✅ Idiomatic Elixir code
- ✅ OTP patterns followed
- ✅ Easy to extend

## Conclusion

This port is **highly feasible** and will result in a **superior SDK** leveraging Elixir's strengths:

1. **Better concurrency**: Native processes vs. threading
2. **Simpler async**: Tasks vs. dual APIs
3. **Fault tolerance**: OTP supervision
4. **Observability**: Built-in telemetry
5. **Type safety**: Dialyzer + typespecs

The estimated timeline of **8 weeks** for a fully-featured v1.0 is realistic with a single developer working full-time.

## Next Steps

1. Complete Phase 1 (foundation)
2. Set up CI/CD pipeline
3. Begin Phase 2 (clients)
4. Iterate with testing and refinement
