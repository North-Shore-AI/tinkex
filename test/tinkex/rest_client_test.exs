defmodule Tinkex.RestClientTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.RestClient

  alias Tinkex.Types.{
    Checkpoint,
    CheckpointArchiveUrlResponse,
    CheckpointsListResponse,
    GetSamplerResponse,
    GetSessionResponse,
    ListSessionsResponse,
    TrainingRun,
    WeightsInfoResponse
  }

  setup :setup_http_client

  describe "new/2" do
    test "creates RestClient struct", %{config: config} do
      client = RestClient.new("session-123", config)

      assert client.session_id == "session-123"
      assert client.config == config
    end
  end

  describe "get_session/2" do
    test "returns session with training runs and samplers", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions/session-123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "training_run_ids": ["model-1", "model-2"],
          "sampler_ids": ["sampler-1"]
        }))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.get_session(client, "session-123")

      assert %GetSessionResponse{} = response
      assert response.training_run_ids == ["model-1", "model-2"]
      assert response.sampler_ids == ["sampler-1"]
    end

    test "returns error on 404", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions/bad-session", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Session not found"}))
      end)

      client = RestClient.new("session-123", config)
      {:error, error} = RestClient.get_session(client, "bad-session")

      assert error.status == 404
    end

    test "returns error on network failure", %{bypass: bypass, config: config} do
      Bypass.down(bypass)

      client = RestClient.new("session-123", config)
      {:error, _reason} = RestClient.get_session(client, "session-123")
    end

    test "accepts access_scope option", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions/session-access", fn conn ->
        assert conn.query_params["access_scope"] == "accessible"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"training_run_ids": [], "sampler_ids": []}))
      end)

      client = RestClient.new("session-123", config)

      assert {:ok, %GetSessionResponse{}} =
               RestClient.get_session(client, "session-access", access_scope: "accessible")
    end

    test "rejects invalid access_scope option", %{config: config} do
      client = RestClient.new("session-123", config)

      assert {:error, %Tinkex.Error{type: :validation, category: :user}} =
               RestClient.get_session(client, "session-123", access_scope: "invalid")
    end
  end

  describe "list_sessions/2" do
    test "returns list of sessions with default pagination", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        assert conn.query_params["limit"] == "20"
        assert conn.query_params["offset"] == "0"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "sessions": ["session-1", "session-2", "session-3"]
        }))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_sessions(client)

      assert %ListSessionsResponse{} = response
      assert length(response.sessions) == 3
    end

    test "supports custom limit and offset", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        assert conn.query_params["limit"] == "50"
        assert conn.query_params["offset"] == "100"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": []}))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_sessions(client, limit: 50, offset: 100)

      assert response.sessions == []
    end

    test "returns empty list when no sessions", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": []}))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_sessions(client)

      assert response.sessions == []
    end

    test "passes access_scope option", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        assert conn.query_params["access_scope"] == "accessible"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": []}))
      end)

      client = RestClient.new("session-123", config)

      assert {:ok, %ListSessionsResponse{}} =
               RestClient.list_sessions(client, access_scope: "accessible")
    end
  end

  describe "list_checkpoints/2" do
    test "returns checkpoints for a run", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-123/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "checkpoints": [
            {
              "checkpoint_id": "ckpt-1",
              "checkpoint_type": "weights",
              "tinker_path": "tinker://run-123/weights/0001",
              "size_bytes": 1000000,
              "public": false,
              "time": "2025-11-20T10:00:00Z"
            }
          ]
        }))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_checkpoints(client, "run-123")

      assert %CheckpointsListResponse{} = response
      assert length(response.checkpoints) == 1
      [ckpt] = response.checkpoints
      assert %Checkpoint{} = ckpt
      assert ckpt.checkpoint_id == "ckpt-1"
      assert ckpt.tinker_path == "tinker://run-123/weights/0001"
    end

    test "returns empty list when no checkpoints", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-empty/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": []}))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_checkpoints(client, "run-empty")

      assert response.checkpoints == []
    end

    test "returns error when run not found", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/bad-run/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Run not found"}))
      end)

      client = RestClient.new("session-123", config)
      {:error, error} = RestClient.list_checkpoints(client, "bad-run")

      assert error.status == 404
    end
  end

  describe "get_sampler/2" do
    test "returns sampler info", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/samplers/session-id%3Asample%3A0", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"sampler_id": "session-id:sample:0", "base_model": "Qwen/Qwen2.5-7B", "model_path": "tinker://run/weights/001"})
        )
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.get_sampler(client, "session-id:sample:0")

      assert %GetSamplerResponse{} = response
      assert response.base_model == "Qwen/Qwen2.5-7B"
      assert response.model_path == "tinker://run/weights/001"
    end

    test "returns error on failure", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/samplers/unknown", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Sampler not found"}))
      end)

      client = RestClient.new("session-123", config)
      {:error, error} = RestClient.get_sampler(client, "unknown")

      assert error.status == 404
    end
  end

  describe "get_weights_info_by_tinker_path/2" do
    test "returns checkpoint metadata", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/weights_info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body)["tinker_path"] == "tinker://run-id/weights/0001"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"base_model": "Qwen/Qwen2.5-7B", "is_lora": true, "lora_rank": 8})
        )
      end)

      client = RestClient.new("session-123", config)

      {:ok, response} =
        RestClient.get_weights_info_by_tinker_path(client, "tinker://run-id/weights/0001")

      assert %WeightsInfoResponse{} = response
      assert response.is_lora
      assert response.lora_rank == 8
    end

    test "parses weights train flags", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/weights_info", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"base_model":"Qwen/Qwen2.5-7B","is_lora":true,"lora_rank":8,"train_unembed":false,"train_mlp":true,"train_attn":false})
        )
      end)

      client = RestClient.new("session-123", config)

      {:ok, response} =
        RestClient.get_weights_info_by_tinker_path(client, "tinker://run-id/weights/0001")

      assert response.train_unembed == false
      assert response.train_mlp == true
      assert response.train_attn == false
    end

    test "returns error on failure", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/weights_info", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Weights not found"}))
      end)

      client = RestClient.new("session-123", config)

      {:error, error} =
        RestClient.get_weights_info_by_tinker_path(client, "tinker://missing/weights/0001")

      assert error.status == 404
    end
  end

  describe "list_user_checkpoints/2" do
    test "returns paginated user checkpoints", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        assert conn.query_params["limit"] == "100"
        assert conn.query_params["offset"] == "0"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "checkpoints": [
            {
              "checkpoint_id": "ckpt-user-1",
              "checkpoint_type": "weights",
              "tinker_path": "tinker://run-1/weights/0001",
              "size_bytes": 5000000,
              "public": true,
              "time": "2025-11-20T12:00:00Z"
            }
          ],
          "cursor": {"total_count": 150, "offset": 0}
        }))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_user_checkpoints(client)

      assert length(response.checkpoints) == 1
      assert response.cursor.total_count == 150
    end

    test "supports custom pagination", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        assert conn.query_params["limit"] == "100"
        assert conn.query_params["offset"] == "50"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": [], "cursor": null}))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_user_checkpoints(client, limit: 100, offset: 50)

      assert response.checkpoints == []
    end
  end

  describe "get_checkpoint_archive_url/2" do
    test "returns download URL for checkpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header(
            "location",
            "https://storage.example.com/checkpoints/ckpt-123.tar"
          )
          |> Plug.Conn.put_resp_header("expires", "2025-12-03T10:00:00Z")
          |> Plug.Conn.resp(302, "")
        end
      )

      client = RestClient.new("session-123", config)

      {:ok, response} =
        RestClient.get_checkpoint_archive_url(client, "tinker://run-123/weights/0001")

      assert %CheckpointArchiveUrlResponse{} = response
      assert response.url == "https://storage.example.com/checkpoints/ckpt-123.tar"
      assert %DateTime{} = response.expires
      assert DateTime.to_iso8601(response.expires) == "2025-12-03T10:00:00Z"
    end

    test "fetches archive URL by ids", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-ids/checkpoints/ckpt-7/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://storage.example.com/ckpt-7.tar")
          |> Plug.Conn.put_resp_header("expires", "Wed, 03 Dec 2025 10:00:00 GMT")
          |> Plug.Conn.resp(302, "")
        end
      )

      client = RestClient.new("session-ids", config)

      {:ok, response} = RestClient.get_checkpoint_archive_url(client, "run-ids", "ckpt-7")

      assert response.url == "https://storage.example.com/ckpt-7.tar"
      assert response.expires == "Wed, 03 Dec 2025 10:00:00 GMT"
    end

    test "returns error when checkpoint not found", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/missing/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(404, ~s({"error": "Checkpoint not found"}))
        end
      )

      client = RestClient.new("session-123", config)

      {:error, error} =
        RestClient.get_checkpoint_archive_url(client, "tinker://run-123/weights/missing")

      assert error.status == 404
    end

    test "retries 503 archive-generation responses", %{bypass: bypass, config: config} do
      counter = start_supervised!({Agent, fn -> 0 end})
      test_pid = self()

      Bypass.expect(
        bypass,
        "GET",
        "/api/v1/training_runs/run-503/checkpoints/weights/0001/archive",
        fn conn ->
          attempt = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

          case attempt do
            1 ->
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.resp(503, ~s({"error":"Archive still being generated"}))

            _ ->
              conn
              |> Plug.Conn.put_resp_header("location", "https://example.com/retry-ready")
              |> Plug.Conn.resp(302, "")
          end
        end
      )

      client = RestClient.new("session-123", config)
      sleep_fun = fn ms -> send(test_pid, {:slept, ms}) end

      assert {:ok, %CheckpointArchiveUrlResponse{url: "https://example.com/retry-ready"}} =
               RestClient.get_checkpoint_archive_url(
                 client,
                 "tinker://run-503/weights/0001",
                 retry_delay_ms: 0,
                 sleep_fun: sleep_fun
               )

      assert_received {:slept, 0}
      assert Agent.get(counter, & &1) == 2
    end

    test "returns validation error for malformed tinker path", %{config: config} do
      client = RestClient.new("session-123", config)

      {:error, error} =
        RestClient.get_checkpoint_archive_url(client, "tinker://run-123/bad/path")

      assert error.type == :validation
      assert error.category == :user
    end
  end

  describe "get_checkpoint_archive_url_by_tinker_path/2" do
    test "delegates to archive URL helper", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header(
            "location",
            "https://storage.example.com/checkpoints/ckpt-123.tar"
          )
          |> Plug.Conn.resp(302, "")
        end
      )

      client = RestClient.new("session-123", config)

      {:ok, response} =
        RestClient.get_checkpoint_archive_url_by_tinker_path(
          client,
          "tinker://run-123/weights/0001"
        )

      assert %CheckpointArchiveUrlResponse{} = response
      assert response.url == "https://storage.example.com/checkpoints/ckpt-123.tar"
    end
  end

  describe "delete_checkpoint/2" do
    test "deletes checkpoint successfully", %{bypass: bypass, config: config} do
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
      {:ok, _} = RestClient.delete_checkpoint(client, "tinker://run-123/weights/0001")
    end

    test "deletes checkpoint by ids", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-abc/checkpoints/ckpt-9",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"status": "deleted"}))
        end
      )

      client = RestClient.new("session-abc", config)
      assert {:ok, _} = RestClient.delete_checkpoint(client, "run-abc", "ckpt-9")
    end

    test "returns error when checkpoint not found", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-123/checkpoints/weights/9999",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(404, ~s({"error": "Checkpoint not found"}))
        end
      )

      client = RestClient.new("session-123", config)
      {:error, error} = RestClient.delete_checkpoint(client, "tinker://run-123/weights/9999")

      assert error.status == 404
    end

    test "returns error on permission denied", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/other-user/checkpoints/weights/0001",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(403, ~s({"error": "Permission denied"}))
        end
      )

      client = RestClient.new("session-123", config)
      {:error, error} = RestClient.delete_checkpoint(client, "tinker://other-user/weights/0001")

      assert error.status == 403
    end
  end

  describe "delete_checkpoint_by_tinker_path/2" do
    test "aliases delete_checkpoint", %{bypass: bypass, config: config} do
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

      {:ok, _} =
        RestClient.delete_checkpoint_by_tinker_path(client, "tinker://run-123/weights/0001")
    end
  end

  describe "publish/unpublish aliases" do
    test "publish_checkpoint_from_tinker_path/2 posts to publish endpoint", %{
      bypass: bypass,
      config: config
    } do
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

      {:ok, _} =
        RestClient.publish_checkpoint_from_tinker_path(client, "tinker://run-123/weights/0001")
    end

    test "unpublish_checkpoint_from_tinker_path/2 deletes publish endpoint", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/publish",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({"status": "unpublished"}))
        end
      )

      client = RestClient.new("session-123", config)

      {:ok, _} =
        RestClient.unpublish_checkpoint_from_tinker_path(
          client,
          "tinker://run-123/weights/0001"
        )
    end
  end

  describe "get_training_run_by_tinker_path/2" do
    test "extracts run_id and fetches training run", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-xyz", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"training_run_id": "run-xyz", "base_model": "m", "model_owner": "owner", "is_lora": false, "corrupted": false, "last_request_time": "2025-11-26T00:00:00Z"})
        )
      end)

      client = RestClient.new("session-123", config)

      {:ok, %TrainingRun{training_run_id: "run-xyz"}} =
        RestClient.get_training_run_by_tinker_path(client, "tinker://run-xyz/weights/0001")
    end
  end

  describe "get_training_run/3" do
    test "passes access_scope option", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-access", fn conn ->
        assert conn.query_params["access_scope"] == "accessible"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"training_run_id":"run-access","base_model":"base","model_owner":"owner","is_lora":false,"corrupted":false,"last_request_time":"2025-11-26T00:00:00Z"})
        )
      end)

      client = RestClient.new("session-123", config)

      assert {:ok, %TrainingRun{training_run_id: "run-access"}} =
               RestClient.get_training_run(client, "run-access", access_scope: "accessible")
    end
  end

  describe "list_training_runs/2" do
    test "passes access_scope option", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs", fn conn ->
        assert conn.query_params["access_scope"] == "accessible"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"training_runs": [], "cursor": null}))
      end)

      client = RestClient.new("session-123", config)
      assert {:ok, _response} = RestClient.list_training_runs(client, access_scope: "accessible")
    end
  end

  describe "set_checkpoint_ttl_from_tinker_path/3" do
    test "updates checkpoint ttl", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "PUT",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/ttl",
        fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body) == %{"ttl_seconds" => 3600}

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({}))
        end
      )

      client = RestClient.new("session-123", config)

      assert {:ok, %{}} =
               RestClient.set_checkpoint_ttl_from_tinker_path(
                 client,
                 "tinker://run-123/weights/0001",
                 3600
               )
    end

    test "rejects non-positive ttl values", %{config: config} do
      client = RestClient.new("session-123", config)

      assert {:error, %Tinkex.Error{type: :validation, category: :user}} =
               RestClient.set_checkpoint_ttl_from_tinker_path(
                 client,
                 "tinker://run-123/weights/0001",
                 0
               )
    end
  end
end
