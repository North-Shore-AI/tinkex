# Phase 2C: Endpoints and Testing - Agent Prompt

> **Target:** Build all API endpoint modules and complete test suite.
> **Timebox:** Week 2 - Day 3
> **Location:** `S:\tinkex` (pure Elixir library)
> **Prerequisites:** Phase 2A (Foundation) and Phase 2B (HTTP Client) must be complete
> **Next:** Phase 3 (Futures and Polling)

---

## 1. Project Context

This document covers:
1. All API.* endpoint modules (Training, Sampling, Futures, Session, Service, Weights, Telemetry)
2. Typed response helpers pattern
3. Complete test suite with test helpers

### 1.1 Pool Configuration Reference

Refer to **Phase 2A, Section 2.1 (Pool Types and Sizes)** for pool definitions.

### 1.2 Typed Helpers Note

In Phase 2, only `Tinkex.API.Session.create_typed/2` provides a typed helper that converts JSON to a struct. Other endpoints return raw maps. Additional typed helpers will be added in Phase 4 as needed.

---

## 2. Implementation Plan

### 2.1 Implementation Order

```
1. Tinkex.API.Training     # Training endpoints
2. Tinkex.API.Sampling     # Sampling endpoints
3. Tinkex.API.Futures      # Future polling
4. Tinkex.API.Session      # Session management
5. Tinkex.API.Service      # Service operations
6. Tinkex.API.Weights      # Weight operations
7. Tinkex.API.Telemetry    # Telemetry reporting
```

### 2.2 File Structure

```
lib/tinkex/api/
├── api.ex            # Tinkex.API (from Phase 2B)
├── training.ex       # Tinkex.API.Training
├── sampling.ex       # Tinkex.API.Sampling
├── futures.ex        # Tinkex.API.Futures
├── session.ex        # Tinkex.API.Session
├── service.ex        # Tinkex.API.Service
├── weights.ex        # Tinkex.API.Weights
└── telemetry.ex      # Tinkex.API.Telemetry

test/
├── support/
│   └── http_case.ex  # Tinkex.HTTPCase test helper
└── tinkex/api/
    ├── api_test.exs
    ├── training_test.exs
    ├── sampling_test.exs
    └── ...
```

---

## 3. Detailed Module Specifications

### 3.1 Tinkex.API.Training

```elixir
defmodule Tinkex.API.Training do
  @moduledoc """
  Training API endpoints.

  Uses :training pool (sequential, long-running operations).
  Pool size: 5 connections.
  """

  @doc """
  Forward-backward pass for gradient computation.

  ## Examples

      Tinkex.API.Training.forward_backward(
        %{model_id: "...", inputs: [...]},
        config: config
      )
  """
  @spec forward_backward(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward_backward(request, opts) do
    Tinkex.API.post(
      "/api/v1/forward_backward",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Optimizer step to update model parameters.
  """
  @spec optim_step(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def optim_step(request, opts) do
    Tinkex.API.post(
      "/api/v1/optim_step",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Forward pass only (inference).
  """
  @spec forward(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def forward(request, opts) do
    Tinkex.API.post(
      "/api/v1/forward",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end
end
```

### 3.2 Tinkex.API.Sampling

```elixir
defmodule Tinkex.API.Sampling do
  @moduledoc """
  Sampling API endpoints.

  Uses :sampling pool (high concurrency).
  Pool size: 100 connections.
  """

  @doc """
  Async sample request.

  Uses :sampling pool (high concurrency).
  Sets max_retries: 0 - Phase 4's SamplingClient will implement client-side
  rate limiting and retry logic via RateLimiter. The HTTP layer doesn't retry
  so that the higher-level client can make intelligent retry decisions based
  on rate limit state.

  Note: Named `sample_async` for consistency with Elixir naming conventions
  (adjective_noun or verb_object patterns). The API endpoint remains /api/v1/asample.

  ## Examples

      Tinkex.API.Sampling.sample_async(
        %{session_id: "...", prompts: [...]},
        config: config
      )
  """
  @spec sample_async(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def sample_async(request, opts) do
    opts =
      opts
      |> Keyword.put(:pool_type, :sampling)
      |> Keyword.put(:max_retries, 0)

    Tinkex.API.post("/api/v1/asample", request, opts)
  end
end
```

### 3.3 Tinkex.API.Futures

```elixir
defmodule Tinkex.API.Futures do
  @moduledoc """
  Future/promise retrieval endpoints.

  Uses :futures pool (concurrent polling).
  Pool size: 50 connections.
  """

  @doc """
  Retrieve future result by request_id.

  ## Examples

      Tinkex.API.Futures.retrieve(
        %{request_id: "abc-123"},
        config: config
      )
  """
  @spec retrieve(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def retrieve(request, opts) do
    Tinkex.API.post(
      "/api/v1/future/retrieve",
      request,
      Keyword.put(opts, :pool_type, :futures)
    )
  end
end
```

### 3.4 Tinkex.API.Session

```elixir
defmodule Tinkex.API.Session do
  @moduledoc """
  Session management endpoints.

  Uses :session pool (critical, keep-alive).
  Pool size: 5 connections with infinite idle time.
  """

  @doc """
  Create a new session.

  ## Examples

      Tinkex.API.Session.create(
        %{model_id: "...", config: %{}},
        config: config
      )
  """
  @spec create(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create(request, opts) do
    Tinkex.API.post(
      "/api/v1/create_session",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end

  @doc """
  Create a new session with typed response.

  Returns a properly typed CreateSessionResponse struct.

  ## Examples

      {:ok, response} = Tinkex.API.Session.create_typed(request, config: config)
      response.session_id  # => "session-abc-123"
  """
  @spec create_typed(map(), keyword()) ::
          {:ok, Tinkex.Types.CreateSessionResponse.t()} | {:error, Tinkex.Error.t()}
  def create_typed(request, opts) do
    case create(request, opts) do
      {:ok, json} ->
        {:ok, Tinkex.Types.CreateSessionResponse.from_json(json)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Send heartbeat to keep session alive.
  """
  @spec heartbeat(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def heartbeat(request, opts) do
    Tinkex.API.post(
      "/api/v1/heartbeat",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
end
```

### 3.5 Tinkex.API.Service

```elixir
defmodule Tinkex.API.Service do
  @moduledoc """
  Service and model creation endpoints.

  Uses :session pool for model creation operations.
  """

  @doc """
  Create a new model.
  """
  @spec create_model(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create_model(request, opts) do
    Tinkex.API.post(
      "/api/v1/create_model",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end

  @doc """
  Create a sampling session.
  """
  @spec create_sampling_session(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def create_sampling_session(request, opts) do
    Tinkex.API.post(
      "/api/v1/create_sampling_session",
      request,
      Keyword.put(opts, :pool_type, :session)
    )
  end
end
```

### 3.6 Tinkex.API.Weights

```elixir
defmodule Tinkex.API.Weights do
  @moduledoc """
  Weight management endpoints.

  Uses :training pool for weight operations.
  """

  @doc """
  Save model weights.
  """
  @spec save_weights(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def save_weights(request, opts) do
    Tinkex.API.post(
      "/api/v1/save_weights",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Load model weights.
  """
  @spec load_weights(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def load_weights(request, opts) do
    Tinkex.API.post(
      "/api/v1/load_weights",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end

  @doc """
  Save weights for sampler.
  """
  @spec save_weights_for_sampler(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def save_weights_for_sampler(request, opts) do
    Tinkex.API.post(
      "/api/v1/save_weights_for_sampler",
      request,
      Keyword.put(opts, :pool_type, :training)
    )
  end
end
```

### 3.7 Tinkex.API.Telemetry

**Important**: This module implements fire-and-forget behavior using Task.start.

**Note**: Telemetry tasks spawned by `Task.start` are not supervised. Failures are logged and ignored. This is intentional - telemetry should never block or fail critical operations.

```elixir
defmodule Tinkex.API.Telemetry do
  @moduledoc """
  Telemetry reporting endpoints.

  Uses :telemetry pool to prevent telemetry from starving critical operations.
  Pool size: 5 connections.

  ## Task Supervision

  Tasks spawned by `send/2` are not supervised. Failures are logged
  and ignored. This is intentional - telemetry should never block or
  fail critical operations.
  """

  require Logger

  @doc """
  Send telemetry asynchronously (fire and forget).

  Spawns a Task to send telemetry without blocking the caller.
  Returns :ok immediately; failures are logged but not propagated.

  ## Examples

      # This returns immediately
      :ok = Tinkex.API.Telemetry.send(
        %{event: "model_trained", metrics: %{}},
        config: config
      )
  """
  @spec send(map(), keyword()) :: :ok
  def send(request, opts) do
    Task.start(fn ->
      try do
        opts =
          opts
          |> Keyword.put(:pool_type, :telemetry)
          |> Keyword.put(:max_retries, 1)

        result = Tinkex.API.post("/api/v1/telemetry", request, opts)

        case result do
          {:ok, _} -> :ok
          {:error, error} ->
            Logger.warning("Telemetry send failed: #{inspect(error)}")
        end
      rescue
        e ->
          Logger.error("Telemetry task crashed: #{Exception.format(:error, e, __STACKTRACE__)}")
      end
    end)

    :ok
  end

  @doc """
  Send telemetry synchronously (for testing).

  Blocks until the telemetry request completes. Use this in tests
  to verify telemetry behavior.
  """
  @spec send_sync(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def send_sync(request, opts) do
    opts =
      opts
      |> Keyword.put(:pool_type, :telemetry)
      |> Keyword.put(:max_retries, 1)

    Tinkex.API.post("/api/v1/telemetry", request, opts)
  end
end
```

---

## 4. Test Suite

### 4.1 Test Helper Module

Create a test helper to reduce boilerplate:

```elixir
# test/support/http_case.ex
defmodule Tinkex.HTTPCase do
  @moduledoc """
  Test helpers for HTTP-related tests.

  Provides common setup and helper functions for Bypass-based testing.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Tinkex.HTTPCase
    end
  end

  @doc """
  Set up Bypass and config for HTTP tests.

  ## Example

      setup :setup_http_client

      test "my test", %{bypass: bypass, config: config} do
        # ...
      end
  """
  @spec setup_http_client(map()) :: map()
  def setup_http_client(_context) do
    bypass = Bypass.open()
    config = Tinkex.Config.new(
      api_key: "test-key",
      base_url: endpoint_url(bypass)
    )

    %{bypass: bypass, config: config}
  end

  @doc """
  Get endpoint URL from Bypass.
  """
  def endpoint_url(bypass) do
    "http://localhost:#{bypass.port}"
  end

  @doc """
  Stub a successful response.
  """
  def stub_success(bypass, body \\ %{}, status \\ 200) do
    Bypass.expect_once(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  @doc """
  Stub an error response.
  """
  def stub_error(bypass, status, body \\ %{}) do
    Bypass.expect_once(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  @doc """
  Stub a response with custom headers.
  """
  def stub_with_headers(bypass, status, body, headers) do
    Bypass.expect_once(bypass, fn conn ->
      conn = Enum.reduce(headers, conn, fn {k, v}, acc ->
        Plug.Conn.put_resp_header(acc, k, v)
      end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  @doc """
  Stub multiple responses in sequence.

  Returns the counter agent pid. Clean up is registered automatically
  via on_exit.
  """
  def stub_sequence(bypass, responses) do
    # Use unique name to avoid conflicts in concurrent tests
    {:ok, counter} = Agent.start_link(fn -> 0 end, name: :"counter_#{:erlang.unique_integer([:positive])}")

    # Register cleanup for the counter agent with proper error handling
    ExUnit.Callbacks.on_exit(fn ->
      try do
        Agent.stop(counter, :normal, 100)
      catch
        :exit, _ -> :ok  # Agent already stopped or crashed
      end
    end)

    Bypass.expect(bypass, fn conn ->
      index = Agent.get_and_update(counter, &{&1, &1 + 1})
      {status, body, headers} = Enum.at(responses, index, {200, %{}, []})

      conn = Enum.reduce(headers, conn, fn {k, v}, acc ->
        Plug.Conn.put_resp_header(acc, k, v)
      end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)

    counter
  end

  @doc """
  Attach telemetry handler for testing.

  Returns the handler_id. Cleanup is registered automatically via on_exit.
  """
  def attach_telemetry(events) do
    handler_id = "test-handler-#{:erlang.unique_integer()}"
    parent = self()

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _config ->
        send(parent, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    ExUnit.Callbacks.on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    handler_id
  end
end
```

Don't forget to add to test_helper.exs:

```elixir
# test/test_helper.exs
ExUnit.start()

# Load test support modules
Code.require_file("support/http_case.ex", __DIR__)
```

### 4.2 Complete API Test Suite

**Important**: All Bypass-based tests MUST NOT be `async: true`. Tests use request counters to verify retry behavior, not timing assertions.

```elixir
defmodule Tinkex.APITest do
  # NOT async: true - Bypass can be fussy with concurrent tests
  use ExUnit.Case
  import Tinkex.HTTPCase

  setup :setup_http_client

  describe "post/3 retry logic" do
    test "retries on 5xx errors", %{bypass: bypass, config: config} do
      counter = stub_sequence(bypass, [
        {503, %{error: "Service unavailable"}, []},
        {503, %{error: "Service unavailable"}, []},
        {200, %{result: "success"}, []}
      ])

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 3
    end

    test "retries on 408 timeout", %{bypass: bypass, config: config} do
      counter = stub_sequence(bypass, [
        {408, %{error: "Request timeout"}, []},
        {200, %{result: "success"}, []}
      ])

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    test "retries on 429 with Retry-After", %{bypass: bypass, config: config} do
      counter = stub_sequence(bypass, [
        {429, %{error: "Rate limited"}, [{"retry-after-ms", "100"}]},
        {200, %{result: "success"}, []}
      ])

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2  # Verifies retry happened
    end

    test "parses Retry-After in seconds", %{bypass: bypass, config: config} do
      counter = stub_sequence(bypass, [
        {429, %{error: "Rate limited"}, [{"retry-after", "1"}]},
        {200, %{result: "success"}, []}
      ])

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    test "honors x-should-retry: false even on 5xx", %{bypass: bypass, config: config} do
      stub_with_headers(bypass, 503, %{error: "Don't retry"},
        [{"x-should-retry", "false"}])

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 503
    end

    test "honors x-should-retry: true on 400", %{bypass: bypass, config: config} do
      counter = stub_sequence(bypass, [
        {400, %{error: "Bad request but retry"}, [{"x-should-retry", "true"}]},
        {200, %{result: "success"}, []}
      ])

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    test "does not retry 4xx errors without x-should-retry", %{bypass: bypass, config: config} do
      stub_error(bypass, 400, %{error: "Bad request"})

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 400
      assert error.category == :user
    end

    test "handles case-insensitive x-should-retry header", %{bypass: bypass, config: config} do
      stub_with_headers(bypass, 503, %{error: "Don't retry"},
        [{"X-Should-Retry", "false"}])

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.status == 503
    end

    test "handles case-insensitive Retry-After header", %{bypass: bypass, config: config} do
      counter = stub_sequence(bypass, [
        {429, %{error: "Rate limited"}, [{"RETRY-AFTER-MS", "50"}]},
        {200, %{result: "success"}, []}
      ])

      {:ok, result} = Tinkex.API.post("/test", %{}, config: config)
      assert result["result"] == "success"
      assert Agent.get(counter, & &1) == 2
    end

    test "respects max_retries", %{bypass: bypass, config: config} do
      counter = stub_sequence(bypass, [
        {503, %{error: "Error 1"}, []},
        {503, %{error: "Error 2"}, []},
        {503, %{error: "Error 3"}, []},
        {503, %{error: "Error 4"}, []},
        {200, %{result: "success"}, []}
      ])

      {:error, error} = Tinkex.API.post("/test", %{},
        config: config,
        max_retries: 1
      )

      assert error.status == 503
      # Initial request + 1 retry = 2 attempts
      assert Agent.get(counter, & &1) == 2
    end

    test "raises without config" do
      assert_raise KeyError, fn ->
        Tinkex.API.post("/test", %{}, [])
      end
    end
  end

  describe "error categorization" do
    test "parses error category from response", %{bypass: bypass, config: config} do
      stub_error(bypass, 400, %{error: "Bad input", category: "user"})

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.category == :user
    end

    test "infers :user category from 4xx status", %{bypass: bypass, config: config} do
      stub_error(bypass, 422, %{error: "Validation failed"})

      {:error, error} = Tinkex.API.post("/test", %{}, config: config)
      assert error.category == :user
    end

    test "infers :server category from 5xx status", %{bypass: bypass, config: config} do
      stub_error(bypass, 500, %{error: "Internal error"})

      {:error, error} = Tinkex.API.post("/test", %{},
        config: config,
        max_retries: 0
      )
      assert error.category == :server
    end
  end

  describe "connection errors" do
    test "handles connection refused", %{bypass: bypass, config: config} do
      Bypass.down(bypass)

      {:error, error} = Tinkex.API.post("/test", %{},
        config: config,
        max_retries: 0
      )

      assert error.type == :api_connection
    end

    test "handles connection closed mid-request", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, fn conn ->
        # Close connection before sending response
        Bypass.down(bypass)
        conn
      end)

      {:error, error} = Tinkex.API.post("/test", %{},
        config: config,
        max_retries: 0
      )

      assert error.type == :api_connection
    end
  end

  describe "telemetry events" do
    test "emits start and stop events", %{bypass: bypass, config: config} do
      attach_telemetry([
        [:tinkex, :http, :request, :start],
        [:tinkex, :http, :request, :stop]
      ])

      stub_success(bypass, %{result: "ok"})

      Tinkex.API.post("/test", %{}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], %{system_time: _}, metadata}
      assert metadata.method == :post
      assert metadata.path == "/test"

      assert_receive {:telemetry, [:tinkex, :http, :request, :stop], %{duration: duration}, metadata}
      assert duration > 0
      assert metadata.result == :ok
    end

    test "includes pool_type in metadata", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])

      stub_success(bypass, %{result: "ok"})

      Tinkex.API.post("/test", %{},
        config: config,
        pool_type: :training
      )

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _, metadata}
      assert metadata.pool_type == :training
    end

    test "different endpoints use different pool_type metadata", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])

      # Training endpoint
      Bypass.expect_once(bypass, "POST", "/api/v1/forward_backward", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result": "ok"}))
      end)

      Tinkex.API.Training.forward_backward(%{}, config: config)
      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _, %{pool_type: :training}}

      # Sampling endpoint
      Bypass.expect_once(bypass, "POST", "/api/v1/asample", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result": "ok"}))
      end)

      Tinkex.API.Sampling.sample_async(%{}, config: config)
      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _, %{pool_type: :sampling}}

      # Session endpoint
      Bypass.expect_once(bypass, "POST", "/api/v1/create_session", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"session_id": "test"}))
      end)

      Tinkex.API.Session.create(%{}, config: config)
      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _, %{pool_type: :session}}
    end
  end

  describe "concurrent requests" do
    test "handles 20 concurrent requests", %{bypass: bypass, config: config} do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      Bypass.expect(bypass, fn conn ->
        Agent.update(counter, &(&1 + 1))
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"result": "ok"}))
      end)

      tasks = for i <- 1..20 do
        Task.async(fn ->
          Tinkex.API.post("/test", %{id: i}, config: config)
        end)
      end

      results = Task.await_many(tasks, 10_000)
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Verify all 20 requests were actually made
      assert Agent.get(counter, & &1) == 20

      Agent.stop(counter)
    end
  end
end
```

### 4.3 Endpoint Module Tests

Example test for Training endpoints:

```elixir
defmodule Tinkex.API.TrainingTest do
  use ExUnit.Case
  import Tinkex.HTTPCase

  setup :setup_http_client

  describe "forward_backward/2" do
    test "sends request to correct endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/forward_backward", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"loss_fn_output_type": "cross_entropy", "metrics": {"loss": 0.5}}))
      end)

      {:ok, result} = Tinkex.API.Training.forward_backward(
        %{model_id: "test"},
        config: config
      )

      assert result["metrics"]["loss"] == 0.5
    end

    test "uses training pool", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])
      stub_success(bypass, %{loss_fn_output_type: "cross_entropy", metrics: %{loss: 0.5}})

      request = %{forward_backward_input: %{data: [], loss_fn: "cross_entropy"}, model_id: "model-123"}
      {:ok, _} = Tinkex.API.Training.forward_backward(request, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _, metadata}
      assert metadata.pool_type == :training
    end
  end

  describe "optim_step/2" do
    test "sends request to correct endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/optim_step", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": "updated"}))
      end)

      {:ok, result} = Tinkex.API.Training.optim_step(
        %{model_id: "test"},
        config: config
      )

      assert result["status"] == "updated"
    end
  end
end
```

### 4.4 Telemetry Module Test

```elixir
defmodule Tinkex.API.TelemetryTest do
  use ExUnit.Case
  import Tinkex.HTTPCase

  setup :setup_http_client

  describe "send/2" do
    test "fires and forgets asynchronously", %{bypass: bypass, config: config} do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/api/v1/telemetry", fn conn ->
        send(test_pid, :telemetry_received)
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": "ok"}))
      end)

      result = Tinkex.API.Telemetry.send(%{event: "test"}, config: config)
      assert result == :ok

      # Wait for async task to complete
      assert_receive :telemetry_received, 1000
    end
  end

  describe "send_sync/2" do
    test "waits for response", %{bypass: bypass, config: config} do
      stub_success(bypass, %{status: "ok"})

      {:ok, result} = Tinkex.API.Telemetry.send_sync(
        %{event: "test"},
        config: config
      )

      assert result["status"] == "ok"
    end
  end
end
```

---

## 5. Quality Gates for Phase 2C

Phase 2C is **complete** when ALL of the following are true:

### 5.1 Implementation Checklist

- [ ] `Tinkex.API.Training` - forward_backward, optim_step, forward
- [ ] `Tinkex.API.Sampling` - sample_async (no `then/1` usage)
- [ ] `Tinkex.API.Futures` - retrieve
- [ ] `Tinkex.API.Session` - create, create_typed, heartbeat
- [ ] `Tinkex.API.Service` - create_model, create_sampling_session
- [ ] `Tinkex.API.Weights` - save_weights, load_weights, save_weights_for_sampler
- [ ] `Tinkex.API.Telemetry` - send (fire-and-forget with `inspect(error)`), send_sync
- [ ] `Tinkex.HTTPCase` - test helper module with @spec for setup_http_client

### 5.2 Testing Checklist

- [ ] All retry logic tests from Phase 2B pass
- [ ] x-should-retry on 400 test passes
- [ ] Case-insensitive header tests pass
- [ ] Concurrent request tests (20 concurrent) pass
- [ ] Telemetry event tests pass
- [ ] Each endpoint module has at least endpoint verification tests
- [ ] All Bypass-based tests are NOT async: true
- [ ] No Process.sleep or :timer.sleep in tests (use observable mechanisms)
- [ ] No timing assertions (elapsed >= X)
- [ ] All tests pass: `mix test`

### 5.3 Type Safety Checklist

- [ ] All endpoint modules have `@spec` for public functions
- [ ] Typed response helpers use proper type specs
- [ ] Dialyzer passes: `mix dialyzer`

### 5.4 Integration Verification

- [ ] Can create config and make request through endpoint modules
- [ ] Different pool types are used correctly
- [ ] Retry behavior matches Python SDK
- [ ] Error categories parsed correctly
- [ ] Telemetry fire-and-forget actually doesn't block

---

## 6. Common Pitfalls to Avoid

1. **All Bypass tests MUST be async: false** - Bypass can be fussy with concurrent tests
2. **Don't forget to test x-should-retry: true on 400** - This proves header takes precedence
3. **Don't make Telemetry.send block** - Use Task.start for fire-and-forget
4. **Don't forget to require Logger in Telemetry module**
5. **Don't hardcode pool types** - Use the constants consistently
6. **Don't use `then/1`** - Use explicit pipelines instead
7. **Don't use `error.message` in Logger** - Use `inspect(error)` for proper formatting
8. **Don't forget on_exit cleanup for Agents** - stub_sequence must clean up
9. **Don't use Process.sleep or :timer.sleep in tests** - All timing must use observable mechanisms (messages, counters, Bypass.expect_once)
10. **Don't use timing assertions** - Verify behavior via state, not elapsed time

---

## 7. Execution Commands

```bash
# Run all Phase 2 tests
mix test

# Run specific test file
mix test test/tinkex/api/api_test.exs

# Run with verbose output
mix test --trace

# Check types
mix dialyzer

# Full verification
mix compile --warnings-as-errors && mix test && mix dialyzer && mix format --check-formatted
```

---

## 8. Phase 2 Complete Checklist

When all three parts are done, verify:

### Full Implementation

- [ ] `Tinkex.PoolKey` - URL normalization with validation
- [ ] `Tinkex.Config` - Multi-tenancy with @enforce_keys
- [ ] `Tinkex.Application` - Finch pools with mod: in mix.exs
- [ ] `Tinkex.API` - Corrected retry logic with telemetry
- [ ] All endpoint modules
- [ ] Test helper module

### Full Test Suite

- [ ] PoolKey tests
- [ ] Config tests
- [ ] API retry tests (all edge cases, using counters not timing)
- [ ] Telemetry event tests
- [ ] Concurrent request tests (20 concurrent)
- [ ] Endpoint tests

### Quality

- [ ] Zero compilation warnings
- [ ] Dialyzer passes
- [ ] Code formatted

---

## 9. Next Steps After Phase 2

Once Phase 2 is complete:

1. **Phase 3**: Futures and polling (`Tinkex.Future`)
2. **Phase 4**: Client implementations (TrainingClient, SamplingClient)

The HTTP layer is the foundation for all network operations. Clients in Phase 4 will use `Tinkex.API.*` functions directly, passing their config through opts.

---

## Summary

Phase 2C completes the HTTP layer with:

1. **All Endpoint Modules** - Properly configured pool types
2. **Typed Response Helpers** - Pattern for converting JSON to typed structs (Session only in Phase 2)
3. **Complete Test Suite** - Including concurrent and telemetry tests
4. **Test Helper Module** - Reduces boilerplate in tests with proper cleanup

The complete Phase 2 provides a robust, tested HTTP foundation for the Tinkex SDK.
