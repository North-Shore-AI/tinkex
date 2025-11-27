defmodule Tinkex.Types.Telemetry.TelemetryBatch do
  @moduledoc """
  Batch of telemetry events for transmission.

  Mirrors Python tinker.types.telemetry_batch.TelemetryBatch.
  Groups multiple events for efficient transmission.
  """

  alias Tinkex.Types.Telemetry.TelemetryEvent

  @type t :: %__MODULE__{
          events: [TelemetryEvent.t()],
          metadata: map()
        }

  defstruct events: [], metadata: %{}

  @doc """
  Create a new TelemetryBatch.
  """
  @spec new([TelemetryEvent.t()], map()) :: t()
  def new(events, metadata \\ %{}) when is_list(events) do
    %__MODULE__{events: events, metadata: metadata}
  end

  @doc """
  Convert batch to wire format (list of event maps).
  """
  @spec to_list(t()) :: [map()]
  def to_list(%__MODULE__{events: events}) do
    Enum.map(events, &TelemetryEvent.to_map/1)
  end

  @doc """
  Parse wire format list to batch.
  """
  @spec from_list([map()], map()) :: t()
  def from_list(event_maps, metadata \\ %{}) when is_list(event_maps) do
    events =
      event_maps
      |> Enum.map(&TelemetryEvent.from_map/1)
      |> Enum.reject(&is_nil/1)

    %__MODULE__{events: events, metadata: metadata}
  end

  @doc """
  Get the number of events in the batch.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{events: events}), do: length(events)
end
