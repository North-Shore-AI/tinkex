defmodule Tinkex.RestClientAsyncTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.RestClient

  alias Tinkex.Types.{
    GetSessionResponse,
    ListSessionsResponse,
    CheckpointsListResponse,
    CheckpointArchiveUrlResponse,
    TrainingRun
  }

  setup :setup_http_client

  describe "async variants return Task.t()" do
    test "get_session_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions/session-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "training_run_ids": ["model-1"],
          "sampler_ids": []
        }))
      end)

      client = RestClient.new("session-123", config)
      task = RestClient.get_session_async(client, "session-123")

      assert %Task{} = task
      {:ok, response} = Task.await(task)
      assert %GetSessionResponse{} = response
      assert response.training_run_ids == ["model-1"]
    end

    test "list_sessions_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": ["s1", "s2"]}))
      end)

      client = RestClient.new("session-123", config)
      task = RestClient.list_sessions_async(client)

      {:ok, response} = Task.await(task)
      assert %ListSessionsResponse{} = response
      assert length(response.sessions) == 2
    end

    test "list_sessions_async/2 passes options", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        assert conn.query_params["limit"] == "100"
        assert conn.query_params["offset"] == "50"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": []}))
      end)

      client = RestClient.new("session-123", config)
      task = RestClient.list_sessions_async(client, limit: 100, offset: 50)

      {:ok, response} = Task.await(task)
      assert response.sessions == []
    end

    test "list_checkpoints_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-123/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": []}))
      end)

      client = RestClient.new("session-123", config)
      task = RestClient.list_checkpoints_async(client, "run-123")

      {:ok, response} = Task.await(task)
      assert %CheckpointsListResponse{} = response
    end

    test "list_user_checkpoints_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": [], "cursor": null}))
      end)

      client = RestClient.new("session-123", config)
      task = RestClient.list_user_checkpoints_async(client)

      {:ok, response} = Task.await(task)
      assert %CheckpointsListResponse{} = response
    end

    test "get_training_run_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-xyz", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"training_run_id": "run-xyz", "base_model": "m", "model_owner": "o", "is_lora": false, "corrupted": false, "last_request_time": "2025-11-26T00:00:00Z"})
        )
      end)

      client = RestClient.new("session-123", config)
      task = RestClient.get_training_run_async(client, "run-xyz")

      {:ok, response} = Task.await(task)
      assert %TrainingRun{training_run_id: "run-xyz"} = response
    end

    test "delete_checkpoint_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"status": "deleted"}))
        end
      )

      client = RestClient.new("session-123", config)
      task = RestClient.delete_checkpoint_async(client, "tinker://run-123/weights/0001")

      {:ok, _response} = Task.await(task)
    end

    test "publish_checkpoint_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "POST",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/publish",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"status": "published"}))
        end
      )

      client = RestClient.new("session-123", config)
      task = RestClient.publish_checkpoint_async(client, "tinker://run-123/weights/0001")

      {:ok, _response} = Task.await(task)
    end

    test "get_checkpoint_archive_url_async/2 returns task", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://storage.example.com/ckpt.tar")
          |> Plug.Conn.resp(302, "")
        end
      )

      client = RestClient.new("session-123", config)
      task = RestClient.get_checkpoint_archive_url_async(client, "tinker://run-123/weights/0001")

      {:ok, response} = Task.await(task)
      assert %CheckpointArchiveUrlResponse{} = response
      assert response.url == "https://storage.example.com/ckpt.tar"
    end
  end

  describe "async error handling" do
    test "errors propagate through tasks", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions/bad-id", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Not found"}))
      end)

      client = RestClient.new("session-123", config)
      task = RestClient.get_session_async(client, "bad-id")

      {:error, error} = Task.await(task)
      assert error.status == 404
    end

    test "network errors propagate through tasks", %{bypass: bypass, config: config} do
      Bypass.down(bypass)

      client = RestClient.new("session-123", config)
      task = RestClient.list_sessions_async(client)

      {:error, _reason} = Task.await(task)
    end
  end

  describe "parallel async requests" do
    test "multiple tasks can run in parallel", %{bypass: bypass, config: config} do
      # Expect both endpoints to be called
      Bypass.expect(bypass, "GET", "/api/v1/sessions", fn conn ->
        # Small delay to verify parallelism
        Process.sleep(50)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": ["s1"]}))
      end)

      Bypass.expect(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        Process.sleep(50)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": [], "cursor": null}))
      end)

      client = RestClient.new("session-123", config)

      # Launch tasks in parallel
      start_time = System.monotonic_time(:millisecond)

      tasks = [
        RestClient.list_sessions_async(client),
        RestClient.list_user_checkpoints_async(client)
      ]

      results = Task.await_many(tasks, 5000)
      elapsed = System.monotonic_time(:millisecond) - start_time

      # Both should succeed
      assert [{:ok, %ListSessionsResponse{}}, {:ok, %CheckpointsListResponse{}}] = results

      # Should take ~50ms (parallel) not ~100ms (serial)
      # Allow some slack for CI environments
      assert elapsed < 150
    end
  end

  describe "async alias functions" do
    test "delete_checkpoint_by_tinker_path_async/2 delegates correctly", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"status": "deleted"}))
        end
      )

      client = RestClient.new("session-123", config)

      task =
        RestClient.delete_checkpoint_by_tinker_path_async(client, "tinker://run-123/weights/0001")

      {:ok, _} = Task.await(task)
    end

    test "publish_checkpoint_from_tinker_path_async/2 delegates correctly", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(
        bypass,
        "POST",
        "/api/v1/training_runs/run-xyz/checkpoints/weights/0002/publish",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"status": "published"}))
        end
      )

      client = RestClient.new("session-123", config)

      task =
        RestClient.publish_checkpoint_from_tinker_path_async(
          client,
          "tinker://run-xyz/weights/0002"
        )

      {:ok, _} = Task.await(task)
    end

    test "get_checkpoint_archive_url_by_tinker_path_async/2 delegates correctly", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-abc/checkpoints/weights/0003/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://dl.example.com/file.tar")
          |> Plug.Conn.resp(302, "")
        end
      )

      client = RestClient.new("session-123", config)

      task =
        RestClient.get_checkpoint_archive_url_by_tinker_path_async(
          client,
          "tinker://run-abc/weights/0003"
        )

      {:ok, response} = Task.await(task)
      assert response.url == "https://dl.example.com/file.tar"
    end
  end
end
