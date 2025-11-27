defmodule Tinkex.APIResponseTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API
  alias Tinkex.API.Response

  setup :setup_http_client

  defmodule DummyParser do
    def from_json(%{"ok" => ok}), do: %{ok: ok}
  end

  test "wraps responses with metadata and parsing", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "GET", "/api/v1/meta", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("x-test-header", "present")
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"ok": true}))
    end)

    assert {:ok, %Response{} = resp} =
             API.get("/api/v1/meta",
               config: config,
               response: :wrapped,
               telemetry_metadata: %{test: true}
             )

    assert resp.status == 200
    assert resp.method == :get
    assert resp.url =~ "/api/v1/meta"
    assert resp.data == %{"ok" => true}
    assert resp.body =~ "\"ok\""
    assert is_integer(resp.elapsed_ms)
    assert resp.retries == 0
    assert Response.header(resp, "x-test-header") == "present"

    assert {:ok, %{ok: true}} = Response.parse(resp, &DummyParser.from_json/1)
  end
end
