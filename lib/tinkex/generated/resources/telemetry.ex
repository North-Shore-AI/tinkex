defmodule Tinkex.Generated.Telemetry do
  @moduledoc """
  Telemetry resource endpoints.

  This module provides functions for interacting with telemetry resources.
  """

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc "Create a resource module instance with the given client."
  @spec with_client(Tinkex.Generated.Client.t()) :: t()
  def with_client(%{context: context}) do
    %__MODULE__{context: context}
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.events()
  """
  @spec events(t(), keyword()) :: {:ok, term()} | {:error, Pristine.Error.t()}
  def events(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(Tinkex.Generated.Client.manifest(), "events", payload, context, opts)
  end

  @doc """
  ## Returns
    * `{:ok, Pristine.Core.StreamResponse.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.events_stream()
  """
  @spec events_stream(t(), keyword()) ::
          {:ok, Pristine.Core.StreamResponse.t()} | {:error, Pristine.Error.t()}
  def events_stream(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute_stream(
      Tinkex.Generated.Client.manifest(),
      "events",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `events` - Required parameter.
    * `platform` - Required parameter.
    * `sdk_version` - Required parameter.
    * `session_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.telemetry(events, platform, sdk_version, session_id, [])
  """
  @spec telemetry(t(), term(), term(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.TelemetryResponse.t()} | {:error, Pristine.Error.t()}
  def telemetry(
        %__MODULE__{context: context},
        events,
        platform,
        sdk_version,
        session_id,
        opts \\ []
      ) do
    payload =
      %{
        "events" => events,
        "platform" => platform,
        "sdk_version" => sdk_version,
        "session_id" => session_id
      }

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "telemetry",
      payload,
      context,
      opts
    )
  end
end
