defmodule Tinkex.HTTPCase do
  @moduledoc """
  Test helpers for HTTP-related tests.

  Provides common setup and helper functions for Bypass-based testing.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Supertester.ExUnitFoundation, isolation: :full_isolation
      import Supertester.Assertions
      import Supertester.MessageHarness
      alias Supertester.ConcurrentHarness
      import Tinkex.HTTPCase
    end
  end

  @doc """
  Set up Bypass and Finch-backed config for HTTP tests.
  """
  @spec setup_http_client(map()) :: map()
  def setup_http_client(_context) do
    bypass = Bypass.open()
    finch_name = :"tinkex_test_finch_#{System.unique_integer([:positive])}"

    ExUnit.Callbacks.start_supervised!({Finch, name: finch_name})

    config =
      Tinkex.Config.new(
        api_key: "test-key",
        base_url: endpoint_url(bypass),
        http_pool: finch_name
      )

    ExUnit.Callbacks.on_exit(fn ->
      try do
        Bypass.down(bypass)
      rescue
        _ -> :ok
      end
    end)

    %{bypass: bypass, config: config, finch_name: finch_name}
  end

  @doc """
  Get endpoint URL from Bypass.
  """
  @spec endpoint_url(Bypass.t()) :: String.t()
  def endpoint_url(bypass) do
    "http://localhost:#{bypass.port}"
  end

  @doc """
  Stub a successful response.
  """
  def stub_success(bypass, body \\ %{}, status \\ 200) do
    Bypass.expect_once(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  @doc """
  Stub an error response.
  """
  def stub_error(bypass, status, body \\ %{}) do
    Bypass.expect_once(bypass, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  @doc """
  Stub a response with custom headers.
  """
  def stub_with_headers(bypass, status, body, headers) do
    Bypass.expect_once(bypass, fn conn ->
      conn =
        Enum.reduce(headers, conn, fn {k, v}, acc ->
          Plug.Conn.put_resp_header(acc, k, v)
        end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)
  end

  @doc """
  Stub multiple responses in sequence.

  Returns the counter agent pid. Clean up is registered automatically via on_exit.
  """
  def stub_sequence(bypass, responses) do
    {:ok, counter} =
      Agent.start_link(fn -> 0 end,
        name: :"tinkex_sequence_counter_#{:erlang.unique_integer([:positive])}"
      )

    ExUnit.Callbacks.on_exit(fn ->
      try do
        Agent.stop(counter, :normal, 100)
      catch
        :exit, _ -> :ok
      end
    end)

    Bypass.expect(bypass, fn conn ->
      index = Agent.get_and_update(counter, &{&1, &1 + 1})
      {status, body, headers} = Enum.at(responses, index, {200, %{}, []})

      conn =
        Enum.reduce(headers, conn, fn {k, v}, acc ->
          Plug.Conn.put_resp_header(acc, k, v)
        end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(body))
    end)

    counter
  end

  @doc """
  Attach telemetry handler for testing.

  Returns the handler_id. Cleanup is registered automatically via on_exit.
  """
  def attach_telemetry(events) do
    handler_id = "test-handler-#{:erlang.unique_integer()}"
    parent = self()

    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.handle_event/4,
      parent
    )

    ExUnit.Callbacks.on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    handler_id
  end

  def handle_event(event, measurements, metadata, parent) do
    send(parent, {:telemetry, event, measurements, metadata})
  end
end
