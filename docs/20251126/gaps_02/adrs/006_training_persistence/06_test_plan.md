# Training Persistence Test Plan

**Date:** 2025-11-26
**Status:** Complete Test Specification
**Coverage Target:** 100% of new functionality

## Test Strategy

### Test Levels

1. **Unit Tests** - Individual functions in isolation
2. **Integration Tests** - Full workflows (save → load → verify)
3. **Wire Protocol Tests** - JSON encoding/decoding
4. **Cross-Language Tests** - Python ↔ Elixir compatibility
5. **Error Handling Tests** - Failure scenarios

---

## Phase 1: LoadWeightsRequest Type Tests

### File: `test/tinkex/types/load_weights_request_test.exs`

```elixir
defmodule Tinkex.Types.LoadWeightsRequestTest do
  use ExUnit.Case
  alias Tinkex.Types.LoadWeightsRequest

  describe "struct creation" do
    test "creates with required fields" do
      request = %LoadWeightsRequest{
        model_id: "test-model",
        path: "tinker://test/weights/001"
      }

      assert request.model_id == "test-model"
      assert request.path == "tinker://test/weights/001"
      assert request.optimizer == false  # default
      assert request.type == "load_weights"
    end

    test "creates with optimizer: true" do
      request = %LoadWeightsRequest{
        model_id: "test-model",
        path: "tinker://test/weights/001",
        optimizer: true
      }

      assert request.optimizer == true
    end

    test "creates with seq_id" do
      request = %LoadWeightsRequest{
        model_id: "test-model",
        path: "tinker://test/weights/001",
        seq_id: 42
      }

      assert request.seq_id == 42
    end
  end

  describe "JSON encoding" do
    test "encodes optimizer field correctly (false)" do
      request = %LoadWeightsRequest{
        model_id: "test-run",
        path: "tinker://test-run/weights/001",
        optimizer: false
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["optimizer"] == false
      assert decoded["model_id"] == "test-run"
      assert decoded["path"] == "tinker://test-run/weights/001"
      assert decoded["type"] == "load_weights"
      refute Map.has_key?(decoded, "load_optimizer_state")  # OLD FIELD GONE
    end

    test "encodes optimizer field correctly (true)" do
      request = %LoadWeightsRequest{
        model_id: "test-run",
        path: "tinker://test-run/weights/001",
        optimizer: true,
        seq_id: 5
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded["optimizer"] == true
      assert decoded["seq_id"] == 5
      refute Map.has_key?(decoded, "load_optimizer_state")
    end
  end

  describe "wire protocol compatibility" do
    test "matches Python wire format (without optimizer)" do
      request = %LoadWeightsRequest{
        model_id: "run-123",
        path: "tinker://run-123/weights/checkpoint-001",
        seq_id: 1,
        optimizer: false
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      # Exact Python format
      assert decoded == %{
               "model_id" => "run-123",
               "path" => "tinker://run-123/weights/checkpoint-001",
               "seq_id" => 1,
               "optimizer" => false,
               "type" => "load_weights"
             }
    end

    test "matches Python wire format (with optimizer)" do
      request = %LoadWeightsRequest{
        model_id: "run-123",
        path: "tinker://run-123/weights/checkpoint-001",
        seq_id: 1,
        optimizer: true
      }

      json = Jason.encode!(request)
      decoded = Jason.decode!(json)

      assert decoded == %{
               "model_id" => "run-123",
               "path" => "tinker://run-123/weights/checkpoint-001",
               "seq_id" => 1,
               "optimizer" => true,
               "type" => "load_weights"
             }
    end
  end
end
```

**Coverage:** 100% of LoadWeightsRequest type

---

## Phase 2: TrainingClient.save_state Tests

### File: `test/tinkex/training_client_save_state_test.exs`

```elixir
defmodule Tinkex.TrainingClientSaveStateTest do
  use ExUnit.Case
  alias Tinkex.Types.SaveWeightsResponse

  setup do
    # Mock config, session, etc.
    :ok
  end

  describe "save_state/3" do
    test "returns Task that yields SaveWeightsResponse" do
      # Setup mock weights API
      # Call save_state
      # Verify Task returns correct response
    end

    test "sends correct request to weights API" do
      # Verify SaveWeightsRequest created correctly
      # Verify model_id, path, seq_id set
    end

    test "increments request counter" do
      # Verify sequential request IDs
    end

    test "handles API errors" do
      # Mock API error
      # Verify error propagated
    end
  end

  describe "wire format" do
    test "sends correct JSON to server" do
      # Mock HTTP client
      # Capture request body
      # Verify JSON structure
    end
  end
end
```

---

## Phase 3: TrainingClient.load_state Tests

### File: `test/tinkex/training_client_load_state_test.exs`

```elixir
defmodule Tinkex.TrainingClientLoadStateTest do
  use ExUnit.Case
  alias Tinkex.Types.LoadWeightsResponse

  describe "load_state/3" do
    test "returns Task that yields LoadWeightsResponse" do
      # Setup mocks
      # Call load_state
      # Verify response
    end

    test "sends request with optimizer: false" do
      # Mock HTTP client to capture request
      # Verify optimizer field is false
    end

    test "increments request counter" do
      # Verify sequential IDs
    end

    test "handles API errors" do
      # Mock error
      # Verify propagation
    end
  end

  describe "wire format" do
    test "sends correct JSON with optimizer: false" do
      # Capture request
      # Verify {"optimizer": false}
    end
  end
end
```

---

## Phase 4: TrainingClient.load_state_with_optimizer Tests

### File: `test/tinkex/training_client_load_optimizer_test.exs`

```elixir
defmodule Tinkex.TrainingClientLoadOptimizerTest do
  use ExUnit.Case

  describe "load_state_with_optimizer/3" do
    test "returns Task that yields LoadWeightsResponse" do
      # Setup mocks
      # Call load_state_with_optimizer
      # Verify response
    end

    test "sends request with optimizer: true" do
      # Mock HTTP client
      # Verify optimizer field is true
    end

    test "reuses same GenServer handler as load_state" do
      # Verify handler called with optimizer: true
    end
  end

  describe "wire format" do
    test "sends correct JSON with optimizer: true" do
      # Capture request
      # Verify {"optimizer": true}
    end
  end
end
```

---

## Phase 5: ServiceClient.create_training_client_from_state Tests

### File: `test/tinkex/service_client_from_state_test.exs`

```elixir
defmodule Tinkex.ServiceClientFromStateTest do
  use ExUnit.Case

  describe "create_training_client_from_state/3" do
    test "queries weights metadata" do
      # Mock REST API
      # Verify get_weights_info called
    end

    test "creates client with same architecture" do
      # Mock metadata: base_model, lora_rank
      # Verify create_lora_training_client called with same params
    end

    test "loads weights without optimizer by default" do
      # Verify load_state called (not load_state_with_optimizer)
    end

    test "loads weights with optimizer when requested" do
      # Pass load_optimizer: true
      # Verify load_state_with_optimizer called
    end

    test "returns training client on success" do
      # Full workflow
      # Verify client returned
    end

    test "handles metadata query errors" do
      # Mock REST error
      # Verify error propagated
    end

    test "handles client creation errors" do
      # Mock creation error
      # Verify error propagated
    end

    test "handles load errors" do
      # Mock load error
      # Verify client killed
      # Verify error propagated
    end
  end
end
```

---

## Integration Tests

### File: `test/integration/checkpoint_workflow_test.exs`

```elixir
defmodule Tinkex.Integration.CheckpointWorkflowTest do
  use ExUnit.Case

  @moduletag :integration

  describe "checkpoint save and load" do
    test "save → load → verify weights match" do
      # 1. Create training client
      # 2. Train for N steps
      # 3. Save checkpoint
      # 4. Load checkpoint
      # 5. Verify weights identical
    end

    test "save → load_with_optimizer → verify optimizer state" do
      # 1. Create training client
      # 2. Train for N steps
      # 3. Save checkpoint
      # 4. Load with optimizer
      # 5. Continue training
      # 6. Verify smooth convergence
    end

    test "save → create_from_state → verify" do
      # 1. Create training client
      # 2. Save checkpoint
      # 3. Create new client from checkpoint
      # 4. Verify weights match
    end
  end

  describe "cross-session training" do
    test "train → save → stop → restart → load → train" do
      # Simulate multi-session training
    end
  end
end
```

---

## Wire Protocol Compatibility Tests

### File: `test/wire_protocol/python_compatibility_test.exs`

```elixir
defmodule Tinkex.WireProtocol.PythonCompatibilityTest do
  use ExUnit.Case

  describe "LoadWeightsRequest compatibility" do
    test "Elixir request matches Python format exactly" do
      elixir_request = %Tinkex.Types.LoadWeightsRequest{
        model_id: "test",
        path: "tinker://test/weights/001",
        seq_id: 1,
        optimizer: true
      }

      elixir_json = Jason.encode!(elixir_request)

      # Python expected format
      python_json = """
      {"model_id":"test","path":"tinker://test/weights/001","seq_id":1,"optimizer":true,"type":"load_weights"}
      """
      |> String.trim()

      assert elixir_json == python_json
    end
  end

  describe "SaveWeightsRequest compatibility" do
    test "Elixir request matches Python format" do
      # Similar test for save requests
    end
  end
end
```

---

## Error Handling Tests

### File: `test/error_handling/checkpoint_errors_test.exs`

```elixir
defmodule Tinkex.ErrorHandling.CheckpointErrorsTest do
  use ExUnit.Case

  describe "save_state errors" do
    test "handles network timeout" do
      # Mock timeout
      # Verify error returned
    end

    test "handles server error (500)" do
      # Mock 500
      # Verify error returned
    end

    test "handles invalid response" do
      # Mock malformed JSON
      # Verify error returned
    end
  end

  describe "load_state errors" do
    test "handles nonexistent checkpoint" do
      # Mock 404
      # Verify error returned
    end

    test "handles corrupted checkpoint" do
      # Mock corrupted data
      # Verify error returned
    end

    test "handles architecture mismatch" do
      # Mock incompatible weights
      # Verify error returned
    end
  end

  describe "create_from_state errors" do
    test "handles missing metadata" do
      # Mock REST error
      # Verify error returned
    end

    test "handles load failure after creation" do
      # Mock load error
      # Verify client killed
      # Verify error returned
    end
  end
end
```

---

## Performance Tests

### File: `test/performance/checkpoint_performance_test.exs`

```elixir
defmodule Tinkex.Performance.CheckpointPerformanceTest do
  use ExUnit.Case

  @moduletag :performance

  describe "save_state performance" do
    test "saves large checkpoint in reasonable time" do
      # Save large model
      # Verify < 5 seconds
    end
  end

  describe "load_state performance" do
    test "loads large checkpoint in reasonable time" do
      # Load large model
      # Verify < 5 seconds
    end
  end

  describe "concurrent saves" do
    test "handles multiple concurrent save requests" do
      # Start multiple saves
      # Verify all succeed
      # Verify sequential execution
    end
  end
end
```

---

## Test Coverage Requirements

### Per-Phase Coverage

| Phase | Component | Target Coverage |
|-------|-----------|-----------------|
| 1 | LoadWeightsRequest type | 100% |
| 2 | save_state function | 100% |
| 3 | load_state function | 100% |
| 4 | load_state_with_optimizer | 100% |
| 5 | create_from_state | 100% |

### Overall Coverage

- **Unit Tests:** 100% of new code
- **Integration Tests:** All major workflows
- **Wire Protocol Tests:** 100% of request/response types
- **Error Handling:** All error paths
- **Performance:** Key operations benchmarked

---

## Test Execution Order

1. **Unit tests first** - Verify individual functions
2. **Wire protocol tests** - Verify JSON encoding
3. **Integration tests** - Verify workflows
4. **Error handling tests** - Verify robustness
5. **Performance tests** - Verify efficiency

---

## Continuous Integration

### Required Checks

- ✅ All unit tests pass
- ✅ All integration tests pass
- ✅ Wire protocol tests pass
- ✅ Test coverage ≥ 100% for new code
- ✅ No compiler warnings
- ✅ Dialyzer passes
- ✅ Credo passes

### Test Commands

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run only checkpoint tests
mix test test/**/checkpoint*

# Run integration tests
mix test --only integration

# Run performance tests
mix test --only performance
```

---

## Test Data

### Sample Checkpoints

Create test fixtures:

```elixir
# test/fixtures/checkpoints.ex
defmodule Tinkex.Test.Fixtures.Checkpoints do
  def valid_checkpoint_path, do: "tinker://test-run/weights/checkpoint-001"
  def valid_checkpoint_response, do: %{
    "path" => valid_checkpoint_path(),
    "type" => "save_weights"
  }

  def weights_info_response, do: %{
    "base_model" => "meta-llama/Llama-3.2-1B",
    "lora_rank" => 32,
    "is_lora" => true
  }
end
```

---

## Success Criteria

Tests pass when:

1. ✅ All unit tests pass
2. ✅ Save → load → verify round-trip works
3. ✅ Optimizer state preserved when requested
4. ✅ Wire protocol matches Python exactly
5. ✅ All error paths handled
6. ✅ 100% code coverage
7. ✅ No race conditions
8. ✅ Performance meets targets

**Total Tests:** ~50-60 tests
**Estimated Test Writing Time:** 8 hours
