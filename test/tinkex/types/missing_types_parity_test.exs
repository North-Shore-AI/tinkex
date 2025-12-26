defmodule Tinkex.Types.MissingTypesParityTest do
  @moduledoc """
  Tests for Python SDK parity in missing types.

  Tests the newly added types that mirror Python SDK types.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Types.{
    FutureRetrieveRequest,
    RequestFailedResponse,
    SessionHeartbeatRequest,
    SessionHeartbeatResponse,
    TelemetryResponse
  }

  describe "FutureRetrieveRequest (Python parity)" do
    test "creates with request_id" do
      req = FutureRetrieveRequest.new("req-123")
      assert req.request_id == "req-123"
    end

    test "to_json produces expected format" do
      req = FutureRetrieveRequest.new("req-456")
      json = FutureRetrieveRequest.to_json(req)

      assert json == %{"request_id" => "req-456"}
    end

    test "from_json parses string keys" do
      req = FutureRetrieveRequest.from_json(%{"request_id" => "req-789"})
      assert req.request_id == "req-789"
    end

    test "from_json parses atom keys" do
      req = FutureRetrieveRequest.from_json(%{request_id: "req-abc"})
      assert req.request_id == "req-abc"
    end
  end

  describe "SessionHeartbeatRequest (Python parity)" do
    test "creates with session_id" do
      req = SessionHeartbeatRequest.new("sess-123")
      assert req.session_id == "sess-123"
      assert req.type == "session_heartbeat"
    end

    test "to_json produces expected format" do
      req = SessionHeartbeatRequest.new("sess-456")
      json = SessionHeartbeatRequest.to_json(req)

      assert json == %{"session_id" => "sess-456", "type" => "session_heartbeat"}
    end

    test "from_json parses string keys" do
      req = SessionHeartbeatRequest.from_json(%{"session_id" => "sess-789"})
      assert req.session_id == "sess-789"
      assert req.type == "session_heartbeat"
    end
  end

  describe "SessionHeartbeatResponse (Python parity)" do
    test "creates with default type" do
      resp = SessionHeartbeatResponse.new()
      assert resp.type == "session_heartbeat"
    end

    test "from_json parses correctly" do
      resp = SessionHeartbeatResponse.from_json(%{"type" => "session_heartbeat"})
      assert resp.type == "session_heartbeat"
    end
  end

  describe "TelemetryResponse (Python parity)" do
    test "creates with accepted status" do
      resp = TelemetryResponse.new()
      assert resp.status == "accepted"
    end

    test "from_json parses string keys" do
      resp = TelemetryResponse.from_json(%{"status" => "accepted"})
      assert resp.status == "accepted"
    end

    test "from_json parses atom keys" do
      resp = TelemetryResponse.from_json(%{status: "accepted"})
      assert resp.status == "accepted"
    end
  end

  describe "RequestFailedResponse (Python parity)" do
    test "creates with error and category" do
      resp = RequestFailedResponse.new("Something went wrong", :server)
      assert resp.error == "Something went wrong"
      assert resp.category == :server
    end

    test "from_json parses with string keys" do
      resp =
        RequestFailedResponse.from_json(%{
          "error" => "Failed to process",
          "category" => "user"
        })

      assert resp.error == "Failed to process"
      assert resp.category == :user
    end

    test "from_json parses with atom keys" do
      resp =
        RequestFailedResponse.from_json(%{
          error: "Server error",
          category: "server"
        })

      assert resp.error == "Server error"
      assert resp.category == :server
    end
  end

  describe "TypeAliases type definitions" do
    test "model_input_chunk type is defined" do
      # Type alias exists for ModelInputChunk
      # The type is: EncodedTextChunk | ImageAssetPointerChunk | ImageChunk
      # We verify the modules exist and have the expected structure
      assert %Tinkex.Types.EncodedTextChunk{tokens: [1, 2, 3]}

      assert %Tinkex.Types.ImageChunk{
        data: "test",
        format: :png,
        expected_tokens: nil
      }

      assert %Tinkex.Types.ImageAssetPointerChunk{
        location: "asset://test",
        format: :png,
        expected_tokens: nil
      }
    end

    test "loss_fn_inputs type represents map of string to TensorData" do
      # Type alias exists for LossFnInputs: %{String.t() => TensorData.t()}
      # Verify TensorData struct exists
      tensor = %Tinkex.Types.TensorData{
        dtype: :float32,
        shape: [2, 3],
        data: <<1.0::float-32-little, 2.0::float-32-little>>
      }

      # A loss_fn_inputs map would look like this
      inputs = %{"loss" => tensor}
      assert is_map(inputs)
      assert Map.has_key?(inputs, "loss")
    end
  end
end
