defmodule Tinkex.API.MultipartTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.API

  setup :setup_http_client

  describe "post/3 multipart handling" do
    test "switches to multipart when files provided", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/upload", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")

        assert String.contains?(content_type, "multipart/form-data")
        assert String.contains?(body, "Content-Disposition: form-data; name=\"file\"")
        assert String.contains?(body, "file content")
        assert String.contains?(body, "description")

        Plug.Conn.resp(conn, 200, Jason.encode!(%{ok: true}))
      end)

      assert {:ok, _} =
               API.post("/upload", %{description: "desc"},
                 config: config,
                 files: %{"file" => "file content"}
               )
    end

    test "falls back to JSON when no files", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/json", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [content_type] = Plug.Conn.get_req_header(conn, "content-type")

        assert content_type == "application/json"
        assert Jason.decode!(body) == %{"hello" => "world"}

        Plug.Conn.resp(conn, 200, Jason.encode!(%{ok: true}))
      end)

      assert {:ok, _} = API.post("/json", %{hello: "world"}, config: config)
    end
  end
end
