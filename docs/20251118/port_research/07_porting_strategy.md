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
- **Error categories**: Parser now normalizes casing + adds explicit verification step (repo snapshot only shows StrEnum members)
- **429 handling**: Wired retry_after_ms from errors to RateLimiter instead of hard-coded values
- **Config threading**: Centralized config struct, removed Application.get_env from API layer
- **PoolKey module**: Single source of truth for URL normalization and pool key generation
- **Task.start safety**: All async GenServer.reply patterns now have mandatory try/rescue wrappers
- **API consistency**: All public client methods return Task.t({:ok, ...} | {:error, ...})

**Key Corrections (Round 5 - Final):**
- **TrainingClient**: Documented blocking behavior as conscious tradeoff; robust Task wrappers with try/rescue
- **HTTP & retries**: Integrated x-should-retry header, unified retry policy, proper 429 handling
- **JSON encoding**: Clarified that nil → null is correct (matches Python), removed global nil-stripping
- **Config threading**: Implemented Tinkex.Config struct for true multi-tenancy
- **ETS cleanup**: Added SamplingRegistry with process monitoring for automatic cleanup
- **Streaming**: Marked as non-production sketch with explicit warnings (v2.0 target)
- **Tokenizer scope**: Documented raw tokenization only, no chat templates in v1.0
- **Concrete next steps**: Added prioritized action items for immediate implementation

**Key Corrections (Round 7 - Concrete Bugs Fixed):**
- **Type field names**: Fixed ImageChunk (`data` not `image_data`), ImageAssetPointerChunk (`location` not `asset_id`)
- **Optional semantics**: Fixed SampleRequest.prompt_logprobs to `Optional[bool] = None` (NOT `bool = False`)
- **RateLimiter scope**: Documented `{base_url, api_key}` scoping with normalized URLs; prevents staging/prod cross-contamination
- **HTTP date parsing**: Removed incorrect implementation - only numeric Retry-After delays supported in v1.0
- **Multi-tenancy pools**: Documented single base_url limitation with Finch pool architecture
- **SamplingClient retries**: Documented intentional divergence (no auto-retry; users wrap if needed)
- **GenServer.reply safety**: Added ArgumentError rescue when caller dies before reply
- **Type verification checklist**: Added comprehensive pre-implementation verification steps

**Key Corrections (Round 8 - Integration & Concurrency Bugs Fixed):**
- **SamplingClient config injection**: Fixed to inject `entry.config` from ETS into API layer opts (prevents Keyword.fetch! crash at runtime)
- **RateLimiter race condition**: Changed to `:ets.insert_new/2` pattern to prevent split-brain limiters when multiple processes initialize same key concurrently
- **TrainingClient submission error handling**: Added `reduce_while` with graceful error replies to prevent GenServer crash on transient HTTP/validation failures
- **Tokenizer ETS key consistency**: Changed caching to use resolved tokenizer ID (not raw model_name) to prevent duplicate downloads for same HF tokenizer
- **Tokenizer NIF safety verification**: Added Pre-Implementation Checklist item to verify tokenizers NIF resources are safe to store in ETS and share across processes

**Key Corrections (Round 9 - Final Implementation Gaps):**
- **Metric reduction algorithm**: Implemented `Tinkex.MetricsReduction` with 6 suffix-based strategies (`:mean`, `:sum`, `:min`, `:max`, `:slack`, `:unique`) matching Python's `REDUCE_MAP` - critical for data integrity (naive averaging corrupts summed/extrema metrics)
- **Queue state backpressure**: Added `TryAgainResponse` and `QueueState` types with handling in `Future.poll/2` for graceful degradation before hard 429 rate limits (`:paused_rate_limit`, `:paused_capacity`)
- **TrainingClient responsiveness**: Documented blocking trade-off during synchronous send phase - accepted for v1.0 with optional work queue pattern for v2.0 if responsiveness becomes requirement
- **Llama-3 tokenizer verification**: Confirmed exact mapping to `"baseten/Meta-Llama-3-tokenizer"` for gating workaround matches Python SDK
- **Behavioral parity**: All fixes ensure 1:1 behavioral match with Python SDK based on source code analysis

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

  @doc "Create TensorData from Nx tensor (aggressively cast to supported backing dtypes)"
  def from_nx(%Nx.Tensor{} = tensor) do
    {normalized, dtype} = normalize_dtype(tensor)

    %__MODULE__{
      data: Nx.to_flat_list(normalized),
      dtype: dtype,
      shape: Tuple.to_list(normalized.shape)
    }
  end

  @doc "Convert to Nx tensor"
  def to_nx(%__MODULE__{} = tensor_data) do
    tensor_data.data
    |> Nx.tensor(type: tensor_dtype_to_nx(tensor_data.dtype))
    |> Nx.reshape(List.to_tuple(tensor_data.shape))
  end

  defp normalize_dtype(%Nx.Tensor{type: {:f, 32}} = tensor), do: {tensor, :float32}

  defp normalize_dtype(%Nx.Tensor{type: {:f, 64}} = tensor) do
    casted = Nx.as_type(tensor, {:f, 32})
    {casted, :float32}
  end

  defp normalize_dtype(%Nx.Tensor{type: {:s, 64}} = tensor), do: {tensor, :int64}

  defp normalize_dtype(%Nx.Tensor{type: {:s, 32}} = tensor) do
    casted = Nx.as_type(tensor, {:s, 64})
    {casted, :int64}
  end

  defp normalize_dtype(%Nx.Tensor{type: {:u, _bits}} = tensor) do
    casted = Nx.as_type(tensor, {:s, 64})
    {casted, :int64}
  end

  defp normalize_dtype(%Nx.Tensor{type: other}) do
    raise ArgumentError, "unsupported Nx dtype #{inspect(other)}"
  end

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

## Concrete Next Steps (Round 5 - Prioritized Actions)

The following changes tighten the v1.0 plan with minimal scope creep and eliminate production-breaking bugs:

### 1. TrainingClient Safety & API Consistency

**Priority:** CRITICAL - Prevents infinite hangs

**Actions:**
- ✅ Wrap all `Task.start` bodies that call `GenServer.reply/2` in `try/rescue`
- ✅ Ensure exactly ONE in-progress task at a time (currently done via synchronous sends)
- ✅ Document timeout behavior (all examples use `:infinity` or large explicit timeout)
- ✅ Decide public API shape: all methods return `Task.t({:ok, ...} | {:error, ...})`

**Implementation:**
```elixir
@impl true
def handle_call({:forward_backward, data, loss_fn, opts}, from, state) do
  # Send all chunks synchronously (ensures ordering)
  {untyped_futures, new_state} = send_all_chunks(data, loss_fn, state)

  # Poll in background with MANDATORY error handling
  Task.start(fn ->
    reply = try do
      polling_tasks = Enum.map(untyped_futures, &Tinkex.Future.poll/1)
      results = Task.await_many(polling_tasks, :infinity)
      {:ok, combine_results(results)}
    rescue
      e ->
        {:error, %Tinkex.Error{
          message: Exception.message(e),
          type: :request_failed,
          data: %{exception: e}
        }}
    end

    GenServer.reply(from, reply)  # ALWAYS called, even on crash
  end)

  {:noreply, new_state}
end
```

**Why This Matters:**
- Without `try/rescue`, task crashes leave caller hanging forever
- Critical for production stability

---

### 2. HTTP Layer & Retry Logic

**Priority:** HIGH - Ensures Python parity

**Actions:**
- ✅ Add `x-should-retry` header support in `with_retries/3`
- ✅ Wire 429 handling end-to-end (parse `Retry-After`, use in `RateLimiter.set_backoff/2`)
- ✅ Unify retry policy with telemetry `is_user_error/1` logic

**Implementation:**
```elixir
defp with_retries(fun, max_retries, attempt \\ 0) do
  case fun.() do
    {:ok, %Finch.Response{headers: headers} = response} = success ->
      # NEW: Honor x-should-retry header
      case List.keyfind(headers, "x-should-retry", 0) do
        {_, "true"} when attempt < max_retries ->
          delay = retry_delay(attempt)
          Process.sleep(delay)
          with_retries(fun, max_retries, attempt + 1)
        _ ->
          success
      end

    # NEW: 429 with server-provided backoff
    {:error, %{status: 429, retry_after_ms: backoff_ms}} = error ->
      if attempt < max_retries do
        Process.sleep(backoff_ms)
        with_retries(fun, max_retries, attempt + 1)
      else
        error
      end

    # 5xx, 408
    {:error, %{status: status}} = error when status >= 500 or status == 408 ->
      if attempt < max_retries do
        delay = retry_delay(attempt)
        Process.sleep(delay)
        with_retries(fun, max_retries, attempt + 1)
      else
        error
      end

    error -> error
  end
end
```

**Why This Matters:**
- Python SDK has rich retry logic; Elixir must match
- 429 handling without server backoff causes rate limit thrashing

---

### 3. JSON Encoding & NotGiven Semantics

**Priority:** MEDIUM - Prevents 422 errors (but only if they occur)

**Actions:**
- ✅ Remove global `nil`-stripping from JSON encoder
- ✅ Let Jason encode `nil → "null"` naturally (matches Python)
- ✅ If specific fields require omission, use per-field approach:
  ```elixir
  Tinkex.JSON.encode!(request, omit_if_nil: [:optional_field])
  ```

**Why This Matters:**
- Python SDK sends `null` for Optional fields; Elixir must match
- Global nil-stripping changes semantics ("not set" vs "explicitly null")
- Only implement field-level omission if API actually rejects `null`

---

### 4. Config Threading for Multi-Tenancy

**Priority:** MEDIUM - Enables production use cases

**Actions:**
- ✅ Implement `Tinkex.Config` struct:
  ```elixir
  defmodule Tinkex.Config do
    defstruct [:base_url, :api_key, :http_pool, :timeout, :max_retries, :user_metadata]

    def new(opts \\ []) do
      %__MODULE__{
        base_url: opts[:base_url] || Application.get_env(:tinkex, :base_url, "https://api.thinkingmachines.ai"),
        api_key: opts[:api_key] || Application.get_env(:tinkex, :api_key) || System.get_env("TINKER_API_KEY"),
        http_pool: opts[:http_pool] || Tinkex.HTTP.Pool,
        timeout: opts[:timeout] || 120_000,
        max_retries: opts[:max_retries] || 3,
        user_metadata: opts[:user_metadata]
      }
    end
  end
  ```

- ✅ Thread config through all HTTP calls (NOT `Application.get_env` at call time)
- ✅ Update `ServiceClient.start_link/1` to accept `:config` option

**Why This Matters:**
- Two clients with different API keys can't coexist with global config
- Testing with mock servers alongside production requires per-client config

---

### 5. ETS Cleanup with Process Monitoring

**Priority:** LOW - Prevents stale entries (graceful termination usually works)

**Actions:**
- ✅ Add `Tinkex.SamplingRegistry` GenServer:
  ```elixir
  defmodule Tinkex.SamplingRegistry do
    use GenServer

    def register(client_pid, config) do
      GenServer.call(__MODULE__, {:register, client_pid, config})
    end

    @impl true
    def init(:ok) do
      {:ok, %{monitors: %{}}}
    end

    @impl true
    def handle_call({:register, pid, config}, _from, state) do
      ref = Process.monitor(pid)
      :ets.insert(:tinkex_sampling_clients, {{:config, pid}, config})
      {:reply, :ok, %{state | monitors: Map.put(state.monitors, ref, pid)}}
    end

    @impl true
    def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
      :ets.delete(:tinkex_sampling_clients, {:config, pid})
      {:noreply, %{state | monitors: Map.delete(state.monitors, ref)}}
    end
  end
  ```

- ✅ Update `SamplingClient.init/1` to call `Tinkex.SamplingRegistry.register/2`

**Why This Matters:**
- Brutal kills (`Process.exit(pid, :kill)`) skip `terminate/2`
- Registry ensures ETS never accumulates stale entries

---

## Implementation Timeline

With these changes, the v1.0 scope remains **8 weeks** (minimal creep):

| Week | Phase | Tasks |
|------|-------|-------|
| 1-2  | Foundation | Types, Config struct, HTTP layer with x-should-retry |
| 3-4  | Clients | TrainingClient (with try/rescue), SamplingClient (with Registry) |
| 5-6  | Operations | Forward/backward, optim_step, sampling, retry logic |
| 7    | CLI & Polish | CLI tools, error handling, telemetry |
| 8    | Testing & Docs | Integration tests, examples, final documentation |

---

## v1.0 Scope (Final)

### ✅ In Scope
- Core training/sampling operations
- Built-in loss functions (cross_entropy, importance_sampling, ppo)
- Tokenization with caching (raw text → tokens, NO chat templates)
- Weight management
- Basic CLI
- 80% test coverage
- JSON-based image types (ImageChunk, ImageAssetPointerChunk)
- Multi-tenancy via Tinkex.Config
- Process monitoring for ETS cleanup

### ❌ Deferred to v2.0
- Custom loss functions (requires EXLA)
- Streaming responses (requires buffer management)
- Chat template application (requires Jinja2 renderer)
- Multipart file uploads (beyond JSON-based images)
- Pagination helpers (manual loops sufficient for v1.0)
- 100% Python parity in edge cases

---

## Risk Mitigation

**Top Risks Eliminated by Round 5:**
1. ✅ **Infinite hangs** - Task.start try/rescue mandatory
2. ✅ **Race conditions** - Synchronous sends in TrainingClient documented
3. ✅ **JSON 422 errors** - Clarified nil → null is correct
4. ✅ **ETS singleton crash** - Fixed in Round 3 (global table, per-client entries)
5. ✅ **Multi-tenant conflicts** - Config struct implemented

**Remaining Risks:**
- Custom loss function demand (mitigated: explicitly v2.0, most users use built-ins)
- Streaming requirement surfaces (mitigated: mark as v2.0, provide callback API)
- Performance bottlenecks (mitigated: ETS for SamplingClient, separate HTTP pools)

---

## Next Actions for Developer

1. **Immediate (Day 1)**
   - Scaffold Mix project with dependencies
   - Implement `Tinkex.Config` struct
   - Set up Finch pools with PoolKey module

2. **Week 1**
   - Implement all type definitions (01_type_system.md)
   - Build HTTP layer with x-should-retry (04_http_layer.md)
   - Create error types and retry logic (05_error_handling.md)

3. **Week 2**
   - Implement TrainingClient with Task.start safety (02_client_architecture.md)
   - Build SamplingRegistry and SamplingClient (02_client_architecture.md)
   - Add Future polling mechanism (03_async_model.md)

4. **Week 3-4**
   - Wire forward_backward, optim_step operations
   - Implement sampling with rate limiting
   - Test multi-tenancy scenarios

5. **Week 5-8**
   - CLI implementation
   - Integration tests
   - Documentation
   - Final polish

---

## Critical Type Verification (Round 7)

**⚠️ CRITICAL:** The following type mismatches were found during documentation review and MUST be verified against Python SDK source before implementation:

### 1. ImageChunk Field Names ✅ FIXED

**Correct fields (from Python SDK):**
```python
# Python: tinker/types.py
@dataclass
class ImageChunk:
    data: str         # base64-encoded image (NOT image_data!)
    format: Literal["png", "jpeg"]
    height: int
    width: int
    tokens: int
    type: Literal["image"] = "image"
```

**Elixir must match exactly:**
```elixir
defmodule Tinkex.Types.ImageChunk do
  defstruct [:data, :format, :height, :width, :tokens, :type]
  # NOT [:image_data, :image_format, :asset_id] ❌
end
```

**Verification:**
- [ ] Grep Python SDK for `class ImageChunk` definition
- [ ] Confirm field names: `data`, `format`, `height`, `width`, `tokens`, `type`
- [ ] Verify JSON encoding sends `{"data": "base64...", "format": "png", ...}`

---

### 2. ImageAssetPointerChunk Field Names ✅ FIXED

**Correct fields (from Python SDK):**
```python
@dataclass
class ImageAssetPointerChunk:
    location: str     # Asset URL or path (NOT asset_id!)
    format: Literal["png", "jpeg"]
    height: int
    width: int
    tokens: int
    type: Literal["image_asset_pointer"] = "image_asset_pointer"
```

**Verification:**
- [ ] Confirm field is `location`, not `asset_id` or `url`
- [ ] Verify all required fields (format, height, width, tokens, type)

---

### 3. SampleRequest.prompt_logprobs Type ✅ FIXED

**Correct type (from Python SDK):**
```python
@dataclass
class SampleRequest:
    # ...
    prompt_logprobs: Optional[bool] = None  # Tri-state: None | True | False
    # NOT: bool = False ❌
```

**Why this matters:**
- `None` (null) = "don't compute prompt logprobs"
- `False` = "explicitly disable" (semantic difference!)
- Using `bool = False` loses the distinction between "not set" and "explicitly false"

**Elixir must preserve tri-state:**
```elixir
defmodule Tinkex.Types.SampleRequest do
  defstruct [
    # ...
    prompt_logprobs: nil,  # nil | true | false
    # ...
  ]

  @type t :: %__MODULE__{
    # ...
    prompt_logprobs: boolean() | nil,
    # ...
  }
end
```

**Verification:**
- [ ] Confirm Python default is `None`, not `False`
- [ ] Test API with `{"prompt_logprobs": null}` vs `{"prompt_logprobs": false}`
- [ ] Verify behavior difference (if any)

---

---

### 4. StopReason Wire Values ⚠️ NEW

**Why:** The Python repo bundled with this plan defines `StopReason: Literal["length", "stop"]`, while earlier docs (and possibly newer server builds) mention `"max_tokens" | "stop_sequence" | "eos"`. Implementing the wrong enum will break pattern matching on streaming/sampling responses.

**Verification:**
- [ ] Call the sampling endpoint and capture raw JSON for at least one response that stops due to token limit and one due to stop condition.
- [ ] Record the exact `stop_reason` strings emitted by the API.
- [ ] Document whether `"length"`/`"stop"` are the only values or if `"max_tokens"/"stop_sequence"/"eos"` are present in newer deployments.

**Action:** Elixir atoms should match whatever the live API emits. If `"max_tokens"` et al. come back, update the docs/code before GA; if not, stick with `"length"`/`"stop"` but leave a compatibility note.

---

### 5. All Other Optional Fields

**Pattern to verify:**
For EVERY field marked `Optional[T] = None` in Python, Elixir should use `field: nil` as default (NOT a default value like `false`, `0`, `""`, etc.).

**Quick verification script:**
```bash
# In Python SDK repo
grep -r "Optional\[" tinker/types.py | grep "= None"
# Verify each one has `nil` default in Elixir, not false/0/""
```

---

## Critical Verification Steps (Round 6)

Before shipping v1.0, you MUST verify the following against actual API behavior:

### 0. StopReason Wire Format

**Status:** ⚠️ Repo snapshot emits `"length"`/`"stop"` only; live service may still use `"max_tokens" | "stop_sequence" | "eos"`.

**Verification:**
1. Send a sampling request that naturally ends due to max tokens.
2. Send another that stops via an explicit stop sequence.
3. Capture the raw JSON responses and log `sequence.stop_reason`.

**Action:** Update the Elixir enum + pattern matches to whatever values are observed. If backend still uses `"length"/"stop"`, keep the pared-down enum but document the divergence from historical strings.

### 1. RequestErrorCategory Wire Format

**Status:** ❓ Unknown - `_types.StrEnum` patch is not present in this repo snapshot, so responses could be `"Unknown"/"Server"/"User"` or lowercase.

**Verification:**
1. Trigger a RequestFailedError from the API (e.g., invalid model_id).
2. Log the raw JSON response body.
3. Inspect `response["category"]` value.
4. Record the exact casing.

**Action:** Parser already normalizes casing, but we must document the observed format (capitalized vs lowercase) in release notes/tests.

### 2. JSON null Handling for Optional Fields

**Why:** Need to confirm API accepts `{"field": null}` vs requires field omission.

**Verification:**
1. Send SampleRequest with `{"base_model": null, "sampling_session_id": "xyz"}`
2. Send same request with `{"sampling_session_id": "xyz"}` (field omitted)
3. Verify both succeed or document which fields reject null

**Action:** If API rejects `null` for specific fields, use per-field omission (NOT global nil-stripping).

### 3. Rate Limit Scope (Per `{base_url, api_key}`)

**Why:** Python’s `_sample_backoff_until` sits on the shared `InternalClientHolder`, meaning all clients using the same API key against the same base URL pause together. We need to confirm the API doesn’t expect broader/global coordination.

**Verification:**
1. Create two SamplingClients with the **same** API key/base URL and a third with a different key.
2. Trigger a 429 on one of the shared-key clients.
3. Ensure the other shared-key client pauses, while the different-key client keeps sending.

**Action:** Implementation keys the RateLimiter on `{normalized_base_url, api_key}`. If real-world behavior differs, adjust before shipping.

### 4. x-should-retry Header Presence

**Why:** Plan implements x-should-retry support, but need to confirm server sends it.

**Verification:**
1. Make requests that trigger retryable errors (5xx)
2. Log response headers
3. Check if `x-should-retry: true/false` header is present

**Action:** If header is never sent, x-should-retry support is harmless but unused. If sent inconsistently, ensure fallback logic works.

### 5. Multipart vs JSON for ImageChunk

**Why:** Plan assumes JSON-based images only; need to confirm no multipart endpoints.

**Verification:**
1. Review all API endpoints that accept images
2. Check Content-Type requirements
3. Verify `ImageChunk` with base64 data works via JSON

**Action:** If multipart required, implement `Tinkex.Multipart` module (currently deferred to v2.0).

### 6. Tokenizer Chat Template Requirements

**Why:** Plan provides raw tokenization only; need to clarify user responsibilities.

**Verification:**
1. Test with instruction-tuned model (e.g., Llama-3-Instruct)
2. Try raw text vs manually-formatted chat template
3. Document which format the API expects

**Action:** Update Tinkex.Tokenizer docs to explicitly state:
- "You must pre-format chat templates" OR
- "SDK handles template application"

### 7. GenServer.reply Timeout Behavior

**Why:** Need to verify caller behavior when TrainingClient handle_call blocks long.

**Verification:**
1. Submit forward_backward with large batch (many chunks)
2. Measure time from call to reply
3. Ensure no intermediate timeouts in production

**Action:** If blocking exceeds default GenServer timeout (5s), all examples must use `:infinity` or explicit large timeout.

### 8. ETS Table Creation Race

**Why:** If client starts before Application.start/2 completes, ETS lookup fails.

**Verification:**
1. In test, start client immediately after Application.start
2. Verify no `:badarg` from missing ETS tables
3. Check Application children start order

**Action:** If race occurs, use application callback to block until tables ready.

### 9. Tokenizer NIF Safety Verification

**Why:** The `tokenizers` NIF stores opaque resources under the hood. If those resources are not safe to use from arbitrary BEAM processes, caching them in ETS would crash the VM.

**Verification plan:**

```elixir
test "tokenizer resources are safe across processes" do
  :ets.new(:tinkex_tokenizers_test, [:set, :public, :named_table])

  {:ok, tok} = Tokenizers.Tokenizer.from_pretrained("gpt2")
  :ets.insert(:tinkex_tokenizers_test, {:tokenizer, tok})

  task =
    Task.async(fn ->
      [{:tokenizer, tok2}] = :ets.lookup(:tinkex_tokenizers_test, :tokenizer)
      {:ok, enc} = Tokenizers.Tokenizer.encode(tok2, "hello")
      assert is_list(Tokenizers.Encoding.get_ids(enc))
    end)

  assert {:ok, _} = Task.await(task)
end
```

**Fallback plan if unsafe:**

1. Remove ETS caching of tokenizer structs.
2. Either:
   * Introduce a `TokenizerServer` process that owns each tokenizer and exposes encode/decode calls, **or**
   * Cache tokenizer configs only and reconstruct handles per-process (slower but safe).

Document the chosen approach so future maintainers know the trade-off.

### 10. Wire-Format Sanity Tests

Run these quick checks before coding against the live API:

```bash
# StopReason values emitted by sampling endpoint
curl -s -X POST "$TINKER_BASE_URL/api/v1/sample" \
  -H "X-Tinker-Api-Key: $TINKER_API_KEY" \
  -H "Content-Type: application/json" \
  -d @sample_request.json | jq '.sequences[].stop_reason'

# RequestErrorCategory casing
curl -s -X POST "$TINKER_BASE_URL/some/invalid/endpoint" \
  -H "X-Tinker-Api-Key: bad-key" | jq '.category'

# Retry-After variants (429 path)
curl -i "$TINKER_BASE_URL/rate_limited_endpoint" \
  -H "X-Tinker-Api-Key: $TINKER_API_KEY" | grep -i retry-after
```

Record the observed `stop_reason` values plus RequestErrorCategory casing (repo snapshot suggests `"length"/"stop"` and capitalized `"Unknown"/"Server"/"User"`, but treat whatever the API returns as truth). Note whether the service ever emits HTTP-date Retry-After headers.

---

## Pre-Implementation Checklist

Before writing code, verify your assumptions:

**Type System (Round 7 - CRITICAL):**
- [ ] ImageChunk fields: `data`, `format`, `height`, `width`, `tokens`, `type` (NOT `image_data`, `image_format`)
- [ ] ImageAssetPointerChunk: uses `location` (NOT `asset_id`)
- [ ] SampleRequest.prompt_logprobs: `Optional[bool] = None` (NOT `bool = False`)
- [ ] StopReason values: capture actual `sequence.stop_reason` responses (repo snapshot shows `"length"`/`"stop"`)
- [ ] All Optional fields: default to `nil`, not false/0/""

**API Behavior (Round 6):**
- [ ] API key format (logged from successful auth)
- [ ] RequestErrorCategory casing (log whether API returns `"Unknown"/"Server"/"User"` or lowercase)
- [ ] Rate limit scope (confirmed `{base_url, api_key}` sharing; verify mixed keys don’t interfere)
- [ ] x-should-retry header presence (logged from 5xx responses)
- [ ] Retry-After formats observed (numeric vs HTTP-date) and documented fallback behavior
- [ ] Image upload method (JSON vs multipart)
- [ ] Chat template requirements (tested with instruct model)
- [ ] GenServer call timeout needs (measured with large batch)
- [ ] ETS initialization order (tested in clean environment)

**Architectural (Round 7):**
- [ ] Multi-tenancy base_url limitation documented (single base_url per app instance)
- [ ] RateLimiter keyed per `{base_url, api_key}` (normalized URL)
- [ ] GenServer.reply handles ArgumentError when caller dies
- [ ] SamplingClient intentionally returns errors (no auto-retry) & docs are explicit

**Concurrency & Safety (Round 8):**
- [ ] SamplingClient injects config from ETS into API opts (prevents Keyword.fetch! crash)
- [ ] RateLimiter uses `:ets.insert_new/2` to prevent split-brain limiters
- [ ] TrainingClient handles send errors gracefully (doesn't crash GenServer)
- [ ] Tokenizer ETS caching uses resolved tokenizer ID (not raw model_name)
- [ ] **Tokenizer NIF resource safety verified:**
  - [ ] Confirm `tokenizers` NIF resources are safe to store in ETS
  - [ ] Verify tokenizer handles can be used from arbitrary processes (Tasks/GenServers different from creator)
  - [ ] Test: Create tokenizer in Process A, store in ETS, use from Process B - must not crash VM
  - [ ] If unsafe: Use dedicated GenServer for tokenizers OR rebuild handles per-process (no ETS cache)

---

## Next Actions for Developer (Post-Verification)

1. **Immediate (Day 1)**
   - Run verification tests against real API
   - Update plan based on actual wire format
   - Implement Tinkex.Config struct
   - Set up Finch pools with PoolKey module

2. **Week 1**
   - Implement all type definitions with verified formats
   - Build HTTP layer with confirmed retry logic
   - Create error types matching actual categories

3. **Week 2**
   - Implement TrainingClient with verified timeout behavior
   - Build SamplingRegistry and SamplingClient
   - Wire RateLimiter with confirmed `{base_url, api_key}` scope (matches Python behavior)

4. **Week 3-4**
   - Wire forward_backward, optim_step operations
   - Implement sampling with confirmed rate limiting
   - Test multi-tenancy scenarios

5. **Week 5-8**
   - CLI implementation
   - Integration tests
   - Documentation
   - Final polish
