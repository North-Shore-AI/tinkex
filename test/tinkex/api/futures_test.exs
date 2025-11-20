defmodule Tinkex.API.FuturesTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Futures

  setup :setup_http_client

  describe "retrieve/2" do
    test "hits future retrieval endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/future/retrieve", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status":"done"}))
      end)

      {:ok, result} = Futures.retrieve(%{request_id: "abc"}, config: config)
      assert result["status"] == "done"
    end

    test "uses futures pool", %{bypass: bypass, config: config} do
      attach_telemetry([[:tinkex, :http, :request, :start]])
      stub_success(bypass, %{status: "ok"})

      {:ok, _} = Futures.retrieve(%{request_id: "req"}, config: config)

      assert_receive {:telemetry, [:tinkex, :http, :request, :start], _,
                      %{pool_type: :futures, path: "/api/v1/future/retrieve"}}
    end
  end
end
