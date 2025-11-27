defmodule Tinkex.Types.Telemetry.TelemetrySendRequest do
  @moduledoc """
  Request structure for sending telemetry to the backend.

  Mirrors Python tinker.types.telemetry_send_request.TelemetrySendRequest.
  Contains session metadata and batched events.
  """

  alias Tinkex.Types.Telemetry.{TelemetryBatch, TelemetryEvent}

  @type t :: %__MODULE__{
          session_id: String.t(),
          platform: String.t(),
          sdk_version: String.t(),
          events: [TelemetryEvent.t()] | TelemetryBatch.t()
        }

  @enforce_keys [:session_id, :platform, :sdk_version, :events]
  defstruct [:session_id, :platform, :sdk_version, :events]

  @doc """
  Create a new TelemetrySendRequest.
  """
  @spec new(keyword()) :: t()
  def new(attrs) do
    %__MODULE__{
      session_id: Keyword.fetch!(attrs, :session_id),
      platform: Keyword.fetch!(attrs, :platform),
      sdk_version: Keyword.fetch!(attrs, :sdk_version),
      events: Keyword.fetch!(attrs, :events)
    }
  end

  @doc """
  Convert struct to wire format map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = request) do
    events =
      case request.events do
        %TelemetryBatch{} = batch -> TelemetryBatch.to_list(batch)
        events when is_list(events) -> Enum.map(events, &event_to_map/1)
      end

    %{
      "session_id" => request.session_id,
      "platform" => request.platform,
      "sdk_version" => request.sdk_version,
      "events" => events
    }
  end

  @doc """
  Parse wire format map to struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    events =
      case map["events"] do
        event_maps when is_list(event_maps) ->
          TelemetryBatch.from_list(event_maps).events

        _ ->
          []
      end

    %__MODULE__{
      session_id: map["session_id"],
      platform: map["platform"],
      sdk_version: map["sdk_version"],
      events: events
    }
  end

  defp event_to_map(%{__struct__: _} = event), do: TelemetryEvent.to_map(event)
  defp event_to_map(map) when is_map(map), do: map
end
