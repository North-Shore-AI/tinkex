defmodule Tinkex.Telemetry.Otel do
  @moduledoc """
  OpenTelemetry trace context propagation for Tinkex.

  This module provides opt-in support for propagating W3C Trace Context
  headers (traceparent, tracestate) through HTTP requests. When enabled,
  Tinkex requests will carry trace context from the caller, enabling
  distributed tracing across services.

  ## Configuration

  Enable OpenTelemetry propagation via config:

      config = Tinkex.Config.new(
        api_key: "tml-...",
        otel_propagate: true
      )

  Or via environment variable:

      export TINKEX_OTEL_PROPAGATE=true

  ## Requirements

  This feature requires the `opentelemetry` and `opentelemetry_api` packages
  to be installed. If they are not available, the propagation functions
  become no-ops.

  Add to your mix.exs (optional):

      {:opentelemetry_api, "~> 1.0"},
      {:opentelemetry, "~> 1.0"}

  ## W3C Trace Context

  The module follows the W3C Trace Context specification:
  - `traceparent`: Contains trace-id, parent-id, and trace-flags
  - `tracestate`: Vendor-specific trace data

  See: https://www.w3.org/TR/trace-context/
  """

  @traceparent_header "traceparent"
  @tracestate_header "tracestate"

  @doc """
  Check if OpenTelemetry propagation is enabled.
  """
  @spec enabled?(map() | struct()) :: boolean()
  def enabled?(%{otel_propagate: true}), do: true
  def enabled?(_), do: false

  @doc """
  Inject trace context headers into an outgoing request.

  If OpenTelemetry is available and propagation is enabled,
  this will add traceparent and optionally tracestate headers
  to the request headers list.

  Returns the headers unchanged if:
  - Propagation is disabled
  - OpenTelemetry is not loaded
  - No active trace context exists
  """
  @spec inject_headers([{String.t(), String.t()}], map() | struct()) :: [
          {String.t(), String.t()}
        ]
  def inject_headers(headers, config) do
    if enabled?(config) and otel_available?() do
      do_inject_headers(headers)
    else
      headers
    end
  end

  @doc """
  Extract trace context from incoming headers.

  Sets the current trace context from the provided headers.
  This is useful when processing responses that may contain
  updated trace context.

  Returns :ok. No-op if propagation is disabled or OpenTelemetry is unavailable.
  """
  @spec extract_context([{String.t(), String.t()}], map() | struct()) :: :ok
  def extract_context(_headers, config) do
    if enabled?(config) and otel_available?() do
      # In a full implementation, this would extract and set context
      # For now, this is a placeholder for the interface
      :ok
    else
      :ok
    end
  end

  @doc """
  Returns the W3C traceparent header name.
  """
  @spec traceparent_header() :: String.t()
  def traceparent_header, do: @traceparent_header

  @doc """
  Returns the W3C tracestate header name.
  """
  @spec tracestate_header() :: String.t()
  def tracestate_header, do: @tracestate_header

  @doc """
  Check if OpenTelemetry modules are available.
  """
  @spec otel_available?() :: boolean()
  def otel_available? do
    Code.ensure_loaded?(:opentelemetry) and
      Code.ensure_loaded?(:otel_propagator_text_map)
  end

  # Private functions

  defp do_inject_headers(headers) do
    if otel_available?() do
      try do
        # Use the OpenTelemetry text map propagator to inject headers
        # The propagator will add traceparent and tracestate if there's an active span
        # We use apply/3 to avoid compile-time warnings about undefined modules
        carrier = headers_to_carrier(headers)
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        injected = apply(:otel_propagator_text_map, :inject, [carrier])
        carrier_to_headers(injected, headers)
      rescue
        # If anything goes wrong, return headers unchanged
        _error -> headers
      catch
        # Handle any throws or exits
        _, _ -> headers
      end
    else
      headers
    end
  end

  defp headers_to_carrier(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
  end

  defp carrier_to_headers(carrier, original_headers) when is_map(carrier) do
    # Start with original headers
    base_headers = Map.new(original_headers, fn {k, v} -> {String.downcase(k), {k, v}} end)

    # Merge in any new headers from the carrier
    carrier
    |> Enum.reduce(base_headers, fn {k, v}, acc ->
      key = String.downcase(to_string(k))

      case Map.get(acc, key) do
        nil -> Map.put(acc, key, {key, to_string(v)})
        _ -> acc
      end
    end)
    |> Map.values()
  end

  defp carrier_to_headers(_carrier, original_headers) do
    original_headers
  end
end
