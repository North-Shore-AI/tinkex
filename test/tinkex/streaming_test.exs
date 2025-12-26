defmodule Tinkex.StreamingTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.API

  setup :setup_http_client

  test "decodes SSE stream events with metadata", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, fn conn ->
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)

      {:ok, conn} = Plug.Conn.chunk(conn, "data: {\"event\":\"one\",\"value\":1}\n\n")
      {:ok, conn} = Plug.Conn.chunk(conn, "event: custom\ndata: {\"value\":2}\n\n")
      {:ok, conn} = Plug.Conn.chunk(conn, ": keep-alive\n\n")

      conn
    end)

    assert {:ok, stream_resp} = API.stream_get("/api/v1/events", config: config)
    assert stream_resp.status == 200
    assert stream_resp.method == :get
    assert stream_resp.headers["content-type"] =~ "event-stream"

    events = Enum.to_list(stream_resp.stream)
    assert [%{"event" => "one", "value" => 1}, %{"value" => 2}] = events
  end
end
