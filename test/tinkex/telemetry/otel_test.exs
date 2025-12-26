defmodule Tinkex.Telemetry.OtelTest do
  @moduledoc """
  Tests for OpenTelemetry trace propagation.
  """
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Otel

  describe "enabled?/1" do
    test "returns false when otel_propagate is not set" do
      config = %{otel_propagate: nil}
      refute Otel.enabled?(config)
    end

    test "returns false when otel_propagate is false" do
      config = %{otel_propagate: false}
      refute Otel.enabled?(config)
    end

    test "returns true when otel_propagate is true" do
      config = %{otel_propagate: true}
      assert Otel.enabled?(config)
    end

    test "returns false for empty map" do
      refute Otel.enabled?(%{})
    end
  end

  describe "inject_headers/2" do
    test "returns empty list when disabled" do
      config = %{otel_propagate: false}
      assert Otel.inject_headers([], config) == []
    end

    test "returns existing headers when disabled" do
      config = %{otel_propagate: false}
      headers = [{"x-custom", "value"}]
      assert Otel.inject_headers(headers, config) == headers
    end

    test "returns headers unchanged when otel not loaded" do
      # OpenTelemetry is optional, so if not loaded, headers should be unchanged
      config = %{otel_propagate: true}
      headers = [{"x-custom", "value"}]
      result = Otel.inject_headers(headers, config)
      # Should at minimum contain our original headers
      assert {"x-custom", "value"} in result
    end
  end

  describe "extract_context/1" do
    test "returns :ok when disabled" do
      config = %{otel_propagate: false}
      assert :ok == Otel.extract_context([], config)
    end

    test "returns :ok with headers when disabled" do
      config = %{otel_propagate: false}
      headers = [{"traceparent", "00-abc-def-01"}]
      assert :ok == Otel.extract_context(headers, config)
    end
  end

  describe "traceparent_header/0" do
    test "returns the standard W3C traceparent header name" do
      assert Otel.traceparent_header() == "traceparent"
    end
  end

  describe "tracestate_header/0" do
    test "returns the standard W3C tracestate header name" do
      assert Otel.tracestate_header() == "tracestate"
    end
  end
end
