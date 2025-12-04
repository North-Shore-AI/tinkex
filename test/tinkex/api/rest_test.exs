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
    test "uses default pagination of 100/0", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        assert conn.query_params == %{"limit" => "100", "offset" => "0"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": [], "cursor": null}))
      end)

      {:ok, _} = Rest.list_user_checkpoints(config)
    end

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
          |> Plug.Conn.put_resp_header("expires", "Wed, 03 Dec 2025 10:00:00 GMT")
          |> Plug.Conn.resp(302, "")
        end
      )

      {:ok, data} = Rest.get_checkpoint_archive_url(config, "tinker://run-1/weights/0001")

      assert data["url"] == "https://example.com/dl"
      assert data["expires"] == "Wed, 03 Dec 2025 10:00:00 GMT"
    end

    test "requests archive URL by IDs", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-2/checkpoints/ckpt-2/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://example.com/ckpt2")
          |> Plug.Conn.resp(302, "")
        end
      )

      {:ok, data} = Rest.get_checkpoint_archive_url(config, "run-2", "ckpt-2")

      assert data["url"] == "https://example.com/ckpt2"
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

    test "deletes checkpoint by ids", %{bypass: bypass, config: config} do
      Bypass.expect_once(
        bypass,
        "DELETE",
        "/api/v1/training_runs/run-2/checkpoints/ckpt-2",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, ~s({}))
        end
      )

      {:ok, _} = Rest.delete_checkpoint(config, "run-2", "ckpt-2")
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

  describe "get_sampler/2" do
    test "sends GET request with URL-encoded sampler_id", %{bypass: bypass, config: config} do
      # The sampler_id contains colons which get URL-encoded
      Bypass.expect_once(bypass, "GET", "/api/v1/samplers/session-id%3Asample%3A0", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"sampler_id": "session-id:sample:0", "base_model": "Qwen/Qwen2.5-7B", "model_path": "tinker://run/weights/001"})
        )
      end)

      {:ok, resp} = Rest.get_sampler(config, "session-id:sample:0")

      assert %Tinkex.Types.GetSamplerResponse{} = resp
      assert resp.sampler_id == "session-id:sample:0"
      assert resp.base_model == "Qwen/Qwen2.5-7B"
      assert resp.model_path == "tinker://run/weights/001"
    end

    test "handles response without model_path", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/samplers/test-sampler", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sampler_id": "test-sampler", "base_model": "test-model"}))
      end)

      {:ok, resp} = Rest.get_sampler(config, "test-sampler")

      assert resp.model_path == nil
    end

    test "returns error on failure", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/samplers/unknown", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Sampler not found"}))
      end)

      {:error, error} = Rest.get_sampler(config, "unknown")

      assert error.status == 404
    end
  end

  describe "get_weights_info_by_tinker_path/2" do
    test "sends POST request with tinker_path in body", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/weights_info", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        assert payload["tinker_path"] == "tinker://run-id/weights/checkpoint-001"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"base_model": "Qwen/Qwen2.5-7B", "is_lora": true, "lora_rank": 32})
        )
      end)

      {:ok, resp} =
        Rest.get_weights_info_by_tinker_path(config, "tinker://run-id/weights/checkpoint-001")

      assert %Tinkex.Types.WeightsInfoResponse{} = resp
      assert resp.base_model == "Qwen/Qwen2.5-7B"
      assert resp.is_lora == true
      assert resp.lora_rank == 32
    end

    test "handles response without lora_rank", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/weights_info", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"base_model": "test-model", "is_lora": false}))
      end)

      {:ok, resp} = Rest.get_weights_info_by_tinker_path(config, "tinker://run/weights/001")

      assert resp.is_lora == false
      assert resp.lora_rank == nil
    end

    test "returns error on failure", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "POST", "/api/v1/weights_info", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Weights not found"}))
      end)

      {:error, error} = Rest.get_weights_info_by_tinker_path(config, "tinker://bad/path/here")

      assert error.status == 404
    end
  end

  describe "get_training_run/2" do
    test "sends GET request to training_runs endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-abc", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"training_run_id": "run-abc", "base_model": "Qwen/Qwen2.5-7B", "model_owner": "owner", "is_lora": true, "lora_rank": 8, "corrupted": false, "last_request_time": "2025-11-26T00:00:00Z"})
        )
      end)

      {:ok, data} = Rest.get_training_run(config, "run-abc")

      assert %Tinkex.Types.TrainingRun{} = data
      assert data.training_run_id == "run-abc"
      assert data.base_model == "Qwen/Qwen2.5-7B"
      assert data.model_owner == "owner"
    end

    test "returns error on failure", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/unknown", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Training run not found"}))
      end)

      {:error, error} = Rest.get_training_run(config, "unknown")

      assert error.status == 404
    end
  end

  describe "get_training_run_by_tinker_path/2" do
    test "extracts run_id from tinker path and fetches training run", %{
      bypass: bypass,
      config: config
    } do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-xyz", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"training_run_id": "run-xyz", "base_model": "m", "model_owner": "owner", "is_lora": false, "corrupted": false, "last_request_time": "2025-11-26T00:00:00Z"})
        )
      end)

      {:ok, data} =
        Rest.get_training_run_by_tinker_path(config, "tinker://run-xyz/weights/checkpoint-001")

      assert %Tinkex.Types.TrainingRun{training_run_id: "run-xyz"} = data
    end

    test "returns error for invalid tinker path", %{config: config} do
      {:error, error} = Rest.get_training_run_by_tinker_path(config, "invalid-path")

      assert error.type == :validation
      assert error.category == :user
    end
  end

  describe "list_training_runs/3" do
    test "sends GET with pagination params", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs", fn conn ->
        assert conn.query_params == %{"limit" => "10", "offset" => "5"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"training_runs": [{"training_run_id": "run-1", "base_model": "m", "model_owner": "owner", "is_lora": false, "corrupted": false, "last_request_time": "2025-11-26T00:00:00Z"}, {"training_run_id": "run-2", "base_model": "m2", "model_owner": "owner", "is_lora": true, "lora_rank": 4, "corrupted": false, "last_request_time": "2025-11-26T00:00:00Z"}]})
        )
      end)

      {:ok, data} = Rest.list_training_runs(config, 10, 5)

      assert %Tinkex.Types.TrainingRunsResponse{} = data
      assert length(data.training_runs) == 2
    end

    test "uses default pagination", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs", fn conn ->
        assert conn.query_params == %{"limit" => "20", "offset" => "0"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          ~s({"training_runs": [], "cursor": {"offset": 0, "limit": 20, "total_count": 0}})
        )
      end)

      {:ok, _} = Rest.list_training_runs(config)
    end
  end
end
