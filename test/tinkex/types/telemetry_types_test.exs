defmodule Tinkex.Types.TelemetryTypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.Telemetry.{
    EventType,
    GenericEvent,
    SessionEndEvent,
    SessionStartEvent,
    Severity,
    TelemetryBatch,
    TelemetryEvent,
    TelemetrySendRequest,
    UnhandledExceptionEvent
  }

  describe "EventType" do
    test "parses valid event types" do
      assert EventType.parse("SESSION_START") == :session_start
      assert EventType.parse("SESSION_END") == :session_end
      assert EventType.parse("UNHANDLED_EXCEPTION") == :unhandled_exception
      assert EventType.parse("GENERIC_EVENT") == :generic_event
    end

    test "returns nil for invalid event types" do
      assert EventType.parse("INVALID") == nil
      assert EventType.parse("") == nil
      assert EventType.parse(nil) == nil
    end

    test "converts atoms to wire format" do
      assert EventType.to_string(:session_start) == "SESSION_START"
      assert EventType.to_string(:session_end) == "SESSION_END"
      assert EventType.to_string(:unhandled_exception) == "UNHANDLED_EXCEPTION"
      assert EventType.to_string(:generic_event) == "GENERIC_EVENT"
    end

    test "roundtrip parse -> to_string" do
      for type <- EventType.values() do
        assert type == type |> EventType.to_string() |> EventType.parse()
      end
    end
  end

  describe "Severity" do
    test "parses valid severity strings" do
      assert Severity.parse("DEBUG") == :debug
      assert Severity.parse("INFO") == :info
      assert Severity.parse("WARNING") == :warning
      assert Severity.parse("ERROR") == :error
      assert Severity.parse("CRITICAL") == :critical
    end

    test "parses atoms directly" do
      assert Severity.parse(:debug) == :debug
      assert Severity.parse(:info) == :info
      assert Severity.parse(:warning) == :warning
    end

    test "returns nil for invalid severity" do
      assert Severity.parse("INVALID") == nil
      assert Severity.parse(nil) == nil
    end

    test "converts to wire format" do
      assert Severity.to_string(:debug) == "DEBUG"
      assert Severity.to_string(:info) == "INFO"
      assert Severity.to_string(:warning) == "WARNING"
      assert Severity.to_string(:error) == "ERROR"
      assert Severity.to_string(:critical) == "CRITICAL"
    end

    test "roundtrip parse -> to_string" do
      for sev <- Severity.values() do
        assert sev == sev |> Severity.to_string() |> Severity.parse()
      end
    end
  end

  describe "GenericEvent" do
    test "creates event with new/1" do
      event =
        GenericEvent.new(
          event_id: "abc123",
          event_session_index: 1,
          timestamp: "2025-11-27T00:00:00Z",
          event_name: "test_event",
          event_data: %{"key" => "value"}
        )

      assert event.event == :generic_event
      assert event.event_id == "abc123"
      assert event.event_session_index == 1
      assert event.severity == :info
      assert event.event_name == "test_event"
      assert event.event_data == %{"key" => "value"}
    end

    test "to_map produces wire format" do
      event =
        GenericEvent.new(
          event_id: "abc123",
          event_session_index: 1,
          timestamp: "2025-11-27T00:00:00Z",
          event_name: "test_event",
          severity: :warning
        )

      map = GenericEvent.to_map(event)

      assert map["event"] == "GENERIC_EVENT"
      assert map["event_id"] == "abc123"
      assert map["severity"] == "WARNING"
      assert map["event_name"] == "test_event"
    end

    test "from_map parses wire format" do
      map = %{
        "event" => "GENERIC_EVENT",
        "event_id" => "abc123",
        "event_session_index" => 1,
        "severity" => "ERROR",
        "timestamp" => "2025-11-27T00:00:00Z",
        "event_name" => "test",
        "event_data" => %{"foo" => "bar"}
      }

      event = GenericEvent.from_map(map)

      assert event.event == :generic_event
      assert event.event_id == "abc123"
      assert event.severity == :error
      assert event.event_data == %{"foo" => "bar"}
    end

    test "roundtrip to_map -> from_map" do
      original =
        GenericEvent.new(
          event_id: "test-123",
          event_session_index: 5,
          timestamp: "2025-11-27T12:00:00Z",
          event_name: "roundtrip_test",
          severity: :critical,
          event_data: %{"nested" => %{"data" => true}}
        )

      reconstructed = original |> GenericEvent.to_map() |> GenericEvent.from_map()

      assert reconstructed.event_id == original.event_id
      assert reconstructed.event_session_index == original.event_session_index
      assert reconstructed.severity == original.severity
      assert reconstructed.event_name == original.event_name
      assert reconstructed.event_data == original.event_data
    end
  end

  describe "SessionStartEvent" do
    test "creates event" do
      event =
        SessionStartEvent.new(
          event_id: "start-1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        )

      assert event.event == :session_start
      assert event.event_id == "start-1"
    end

    test "to_map produces wire format" do
      event =
        SessionStartEvent.new(
          event_id: "start-1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        )

      map = SessionStartEvent.to_map(event)

      assert map["event"] == "SESSION_START"
      assert map["severity"] == "INFO"
    end

    test "roundtrip to_map -> from_map" do
      original =
        SessionStartEvent.new(
          event_id: "start-xyz",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        )

      reconstructed = original |> SessionStartEvent.to_map() |> SessionStartEvent.from_map()

      assert reconstructed.event_id == original.event_id
      assert reconstructed.event == :session_start
    end
  end

  describe "SessionEndEvent" do
    test "creates event with duration" do
      event =
        SessionEndEvent.new(
          event_id: "end-1",
          event_session_index: 10,
          timestamp: "2025-11-27T01:00:00Z",
          duration: "1:00:00.000000"
        )

      assert event.event == :session_end
      assert event.duration == "1:00:00.000000"
    end

    test "to_map includes duration when present" do
      event =
        SessionEndEvent.new(
          event_id: "end-1",
          event_session_index: 10,
          timestamp: "2025-11-27T01:00:00Z",
          duration: "0:30:00"
        )

      map = SessionEndEvent.to_map(event)

      assert map["event"] == "SESSION_END"
      assert map["duration"] == "0:30:00"
    end

    test "to_map omits duration when nil" do
      event =
        SessionEndEvent.new(
          event_id: "end-1",
          event_session_index: 10,
          timestamp: "2025-11-27T01:00:00Z"
        )

      map = SessionEndEvent.to_map(event)

      refute Map.has_key?(map, "duration")
    end
  end

  describe "UnhandledExceptionEvent" do
    test "creates event with exception details" do
      event =
        UnhandledExceptionEvent.new(
          event_id: "exc-1",
          event_session_index: 5,
          timestamp: "2025-11-27T00:00:00Z",
          error_type: "RuntimeError",
          error_message: "Something went wrong",
          traceback: "** (RuntimeError) Something went wrong\n    file.ex:10"
        )

      assert event.event == :unhandled_exception
      assert event.severity == :error
      assert event.error_type == "RuntimeError"
      assert event.error_message == "Something went wrong"
    end

    test "to_map produces wire format with traceback" do
      event =
        UnhandledExceptionEvent.new(
          event_id: "exc-1",
          event_session_index: 5,
          timestamp: "2025-11-27T00:00:00Z",
          error_type: "RuntimeError",
          error_message: "test error",
          traceback: "stack trace here"
        )

      map = UnhandledExceptionEvent.to_map(event)

      assert map["event"] == "UNHANDLED_EXCEPTION"
      assert map["error_type"] == "RuntimeError"
      assert map["traceback"] == "stack trace here"
    end

    test "roundtrip preserves all fields" do
      original =
        UnhandledExceptionEvent.new(
          event_id: "exc-abc",
          event_session_index: 3,
          timestamp: "2025-11-27T12:00:00Z",
          error_type: "ArgumentError",
          error_message: "invalid argument",
          severity: :critical,
          traceback: "traceback"
        )

      reconstructed =
        original |> UnhandledExceptionEvent.to_map() |> UnhandledExceptionEvent.from_map()

      assert reconstructed.error_type == original.error_type
      assert reconstructed.error_message == original.error_message
      assert reconstructed.severity == original.severity
    end
  end

  describe "TelemetryEvent union" do
    test "to_map dispatches correctly" do
      generic =
        GenericEvent.new(
          event_id: "g1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z",
          event_name: "test"
        )

      start =
        SessionStartEvent.new(
          event_id: "s1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        )

      assert TelemetryEvent.to_map(generic)["event"] == "GENERIC_EVENT"
      assert TelemetryEvent.to_map(start)["event"] == "SESSION_START"
    end

    test "from_map parses event type correctly" do
      generic_map = %{
        "event" => "GENERIC_EVENT",
        "event_id" => "g1",
        "event_session_index" => 0,
        "timestamp" => "2025-11-27T00:00:00Z",
        "event_name" => "test",
        "severity" => "INFO"
      }

      event = TelemetryEvent.from_map(generic_map)
      assert %GenericEvent{} = event

      start_map = %{
        "event" => "SESSION_START",
        "event_id" => "s1",
        "event_session_index" => 0,
        "timestamp" => "2025-11-27T00:00:00Z",
        "severity" => "INFO"
      }

      event = TelemetryEvent.from_map(start_map)
      assert %SessionStartEvent{} = event
    end

    test "event_type returns correct type" do
      generic =
        GenericEvent.new(
          event_id: "g1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z",
          event_name: "test"
        )

      start =
        SessionStartEvent.new(
          event_id: "s1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        )

      assert TelemetryEvent.event_type(generic) == :generic_event
      assert TelemetryEvent.event_type(start) == :session_start
    end
  end

  describe "TelemetryBatch" do
    test "creates batch from events" do
      events = [
        SessionStartEvent.new(
          event_id: "s1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        ),
        GenericEvent.new(
          event_id: "g1",
          event_session_index: 1,
          timestamp: "2025-11-27T00:00:01Z",
          event_name: "test"
        )
      ]

      batch = TelemetryBatch.new(events)

      assert TelemetryBatch.size(batch) == 2
    end

    test "to_list converts events to maps" do
      events = [
        SessionStartEvent.new(
          event_id: "s1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        )
      ]

      batch = TelemetryBatch.new(events)
      list = TelemetryBatch.to_list(batch)

      assert length(list) == 1
      assert hd(list)["event"] == "SESSION_START"
    end

    test "from_list parses event maps" do
      maps = [
        %{
          "event" => "SESSION_START",
          "event_id" => "s1",
          "event_session_index" => 0,
          "timestamp" => "2025-11-27T00:00:00Z",
          "severity" => "INFO"
        },
        %{
          "event" => "GENERIC_EVENT",
          "event_id" => "g1",
          "event_session_index" => 1,
          "timestamp" => "2025-11-27T00:00:01Z",
          "event_name" => "test",
          "severity" => "INFO"
        }
      ]

      batch = TelemetryBatch.from_list(maps)

      assert TelemetryBatch.size(batch) == 2
      assert %SessionStartEvent{} = hd(batch.events)
    end
  end

  describe "TelemetrySendRequest" do
    test "creates request with metadata and events" do
      events = [
        SessionStartEvent.new(
          event_id: "s1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z"
        )
      ]

      request =
        TelemetrySendRequest.new(
          session_id: "session-123",
          platform: "unix/linux",
          sdk_version: "0.1.0",
          events: events
        )

      assert request.session_id == "session-123"
      assert request.platform == "unix/linux"
    end

    test "to_map produces wire format" do
      events = [
        GenericEvent.new(
          event_id: "g1",
          event_session_index: 0,
          timestamp: "2025-11-27T00:00:00Z",
          event_name: "test"
        )
      ]

      request =
        TelemetrySendRequest.new(
          session_id: "sess-xyz",
          platform: "win32",
          sdk_version: "1.0.0",
          events: events
        )

      map = TelemetrySendRequest.to_map(request)

      assert map["session_id"] == "sess-xyz"
      assert map["platform"] == "win32"
      assert map["sdk_version"] == "1.0.0"
      assert length(map["events"]) == 1
      assert hd(map["events"])["event"] == "GENERIC_EVENT"
    end

    test "accepts TelemetryBatch for events" do
      batch =
        TelemetryBatch.new([
          SessionStartEvent.new(
            event_id: "s1",
            event_session_index: 0,
            timestamp: "2025-11-27T00:00:00Z"
          )
        ])

      request =
        TelemetrySendRequest.new(
          session_id: "sess-abc",
          platform: "darwin",
          sdk_version: "2.0.0",
          events: batch
        )

      map = TelemetrySendRequest.to_map(request)

      assert length(map["events"]) == 1
    end

    test "from_map parses wire format" do
      map = %{
        "session_id" => "sess-123",
        "platform" => "unix/linux",
        "sdk_version" => "1.0.0",
        "events" => [
          %{
            "event" => "SESSION_START",
            "event_id" => "s1",
            "event_session_index" => 0,
            "timestamp" => "2025-11-27T00:00:00Z",
            "severity" => "INFO"
          }
        ]
      }

      request = TelemetrySendRequest.from_map(map)

      assert request.session_id == "sess-123"
      assert length(request.events) == 1
    end
  end
end
