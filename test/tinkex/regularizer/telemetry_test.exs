defmodule Tinkex.Regularizer.TelemetryTest do
  use ExUnit.Case, async: true
  @moduletag capture_log: true

  alias Tinkex.Regularizer.Telemetry

  describe "events/0" do
    test "returns list of regularizer telemetry events" do
      events = Telemetry.events()

      assert [:tinkex, :custom_loss, :start] in events
      assert [:tinkex, :custom_loss, :stop] in events
      assert [:tinkex, :custom_loss, :exception] in events
      assert [:tinkex, :regularizer, :compute, :start] in events
      assert [:tinkex, :regularizer, :compute, :stop] in events
      assert [:tinkex, :regularizer, :compute, :exception] in events
    end
  end

  setup do
    Process.put(:telemetry_handlers, [])

    on_exit(fn ->
      Process.get(:telemetry_handlers, [])
      |> Enum.each(&Telemetry.detach/1)
    end)

    :ok
  end

  describe "attach_logger/1" do
    test "attaches handler to all events" do
      handler_id = Telemetry.attach_logger()
      track_handler(handler_id)

      # Check handler is attached
      handlers = :telemetry.list_handlers([:tinkex, :custom_loss, :start])
      assert Enum.any?(handlers, fn %{id: id} -> id == handler_id end)

      :telemetry.detach(handler_id)
    end

    test "accepts custom handler_id" do
      handler_id = Telemetry.attach_logger(handler_id: "my-custom-id")
      track_handler(handler_id)

      assert handler_id == "my-custom-id"

      :telemetry.detach(handler_id)
    end

    test "accepts custom log level" do
      handler_id = Telemetry.attach_logger(level: :debug)
      track_handler(handler_id)

      # Handler should be attached
      handlers = :telemetry.list_handlers([:tinkex, :custom_loss, :start])
      assert Enum.any?(handlers, fn %{id: id} -> id == handler_id end)

      :telemetry.detach(handler_id)
    end
  end

  describe "detach/1" do
    test "detaches previously attached handler" do
      handler_id = Telemetry.attach_logger()
      track_handler(handler_id)

      # Verify attached
      handlers_before = :telemetry.list_handlers([:tinkex, :custom_loss, :start])
      assert Enum.any?(handlers_before, fn %{id: id} -> id == handler_id end)

      # Detach
      :ok = Telemetry.detach(handler_id)

      # Verify detached
      handlers_after = :telemetry.list_handlers([:tinkex, :custom_loss, :start])
      refute Enum.any?(handlers_after, fn %{id: id} -> id == handler_id end)
    end
  end

  describe "handle_event/4" do
    test "handles custom_loss stop event" do
      # This tests the handler implementation indirectly
      # We attach and emit an event to ensure no errors

      handler_id = Telemetry.attach_logger(level: :warning)
      track_handler(handler_id)

      # Should not raise
      :telemetry.execute(
        [:tinkex, :custom_loss, :stop],
        %{duration: 1_000_000, loss_total: 2.5, regularizer_total: 0.5},
        %{regularizer_count: 2}
      )

      :telemetry.detach(handler_id)
    end

    test "handles regularizer compute stop event" do
      handler_id = Telemetry.attach_logger(level: :warning)
      track_handler(handler_id)

      # Should not raise
      :telemetry.execute(
        [:tinkex, :regularizer, :compute, :stop],
        %{duration: 500_000, value: 10.0, contribution: 1.0, grad_norm: 5.0},
        %{regularizer_name: "l1", weight: 0.1, async: false}
      )

      :telemetry.detach(handler_id)
    end

    test "handles custom_loss exception event" do
      handler_id = Telemetry.attach_logger(level: :warning)
      track_handler(handler_id)

      # Should not raise
      :telemetry.execute(
        [:tinkex, :custom_loss, :exception],
        %{duration: 100_000},
        %{reason: %RuntimeError{message: "test error"}}
      )

      :telemetry.detach(handler_id)
    end
  end

  defp track_handler(handler_id) do
    handlers = Process.get(:telemetry_handlers, [])
    Process.put(:telemetry_handlers, [handler_id | handlers])
    handler_id
  end
end
