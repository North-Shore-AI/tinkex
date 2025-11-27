defmodule Tinkex.Telemetry.Provider do
  @moduledoc false

  @doc """
  Get the telemetry reporter pid for this module.
  """
  @callback get_telemetry() :: pid() | nil

  defmacro __using__(_opts) do
    quote do
      @behaviour Tinkex.Telemetry.Provider

      @impl Tinkex.Telemetry.Provider
      def get_telemetry, do: nil

      defoverridable get_telemetry: 0
    end
  end
end
