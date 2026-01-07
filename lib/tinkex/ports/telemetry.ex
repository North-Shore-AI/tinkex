defmodule Tinkex.Ports.Telemetry do
  @moduledoc """
  Port for telemetry emission.
  """

  @type event :: term()

  @callback emit(event(), map(), map()) :: :ok
  @callback measure(event(), map(), (-> result)) :: result when result: term()
  @callback emit_counter(event(), map()) :: :ok
  @callback emit_gauge(event(), number(), map()) :: :ok

  @optional_callbacks [measure: 3, emit_counter: 2, emit_gauge: 3]
end
