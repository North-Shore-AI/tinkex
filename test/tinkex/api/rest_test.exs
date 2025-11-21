defmodule Tinkex.API.RestTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.API.Rest

  setup :setup_http_client

  describe "get_session/2" do
    test "sends GET request to correct endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions/session-abc", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"training_run_ids": [], "sampler_ids": []}))
      end)

      {:ok, data} = Rest.get_session(config, "session-abc")

      assert data["training_run_ids"] == []
      assert data["sampler_ids"] == []
    end

    test "returns error on failure", %{bypass: bypass, config: config} do
      Bypass.stub(bypass, "GET", "/api/v1/sessions/bad", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, ~s({"error": "Internal error"}))
      end)

      {:error, error} = Rest.get_session(config, "bad")

      assert error.status == 500
    end
  end

  describe "list_sessions/3" do
    test "sends GET with pagination params", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        assert conn.query_params == %{"limit" => "10", "offset" => "20"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": ["s1", "s2"]}))
      end)

      {:ok, data} = Rest.list_sessions(config, 10, 20)

      assert data["sessions"] == ["s1", "s2"]
    end

    test "uses default pagination", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        assert conn.query_params == %{"limit" => "20", "offset" => "0"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": []}))
      end)

      {:ok, _} = Rest.list_sessions(config)
    end
  end

  describe "list_checkpoints/2" do
    test "sends GET to training run checkpoints endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-xyz/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": []}))
      end)

      {:ok, data} = Rest.list_checkpoints(config, "run-xyz")

      assert data["checkpoints"] == []
    end
  end

  describe "list_user_checkpoints/3" do
    test "sends GET with pagination", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        assert conn.query_params == %{"limit" => "100", "offset" => "50"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": [], "cursor": null}))
      end)

      {:ok, data} = Rest.list_user_checkpoints(config, 100, 50)

      assert data["checkpoints"] == []
    end
  end

  describe "get_checkpoint_archive_url/2" do
    test "requests archive URL via training_runs endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-1/checkpoints/weights/0001/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://example.com/dl")
          |> Plug.Conn.resp(302, "")
        end
      )

      {:ok, data} = Rest.get_checkpoint_archive_url(config, "tinker://run-1/weights/0001")

      assert data["url"] == "https://example.com/dl"
    end
  end

  describe "delete_checkpoint/2" do
    test "sends DELETE request to training_runs endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-1/checkpoints/weights/0001",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({}))
        end
      )

      {:ok, _} = Rest.delete_checkpoint(config, "tinker://run-1/weights/0001")
    end

    test "returns error on failure", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-1/checkpoints/weights/9999",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(404, ~s({"error": "Not found"}))
        end
      )

      {:error, error} = Rest.delete_checkpoint(config, "tinker://run-1/weights/9999")

      assert error.status == 404
    end
  end
end
