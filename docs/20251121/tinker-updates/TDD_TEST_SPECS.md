# TDD Test Specifications for Tinkex Updates

## Testing Strategy

### Approach
1. **Red** - Write failing test first
2. **Green** - Implement minimal code to pass
3. **Refactor** - Clean up while tests pass

### Tools
- **Bypass** - HTTP mocking
- **Supertester** - Test utilities
- **ExUnit** - Test framework

### Test Organization
```
test/
├── tinkex/
│   ├── rest_client_test.exs        # RestClient unit tests
│   ├── api/
│   │   └── rest_test.exs           # API.Rest tests
│   ├── types/
│   │   ├── checkpoint_test.exs
│   │   └── session_response_test.exs
│   └── checkpoint_download_test.exs
├── integration/
│   ├── sessions_test.exs
│   └── checkpoints_test.exs
└── support/
    └── http_case.ex                 # Existing test case
```

---

## Stage 1: Foundation Tests

### 1.1 Type Tests

```elixir
# test/tinkex/types/session_response_test.exs
defmodule Tinkex.Types.SessionResponseTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{GetSessionResponse, ListSessionsResponse}

  describe "GetSessionResponse" do
    test "creates struct with training_run_ids and sampler_ids" do
      response = %GetSessionResponse{
        training_run_ids: ["model-1", "model-2"],
        sampler_ids: ["sampler-1"]
      }

      assert response.training_run_ids == ["model-1", "model-2"]
      assert response.sampler_ids == ["sampler-1"]
    end

    test "from_map/1 converts map to struct" do
      map = %{
        "training_run_ids" => ["model-1"],
        "sampler_ids" => ["sampler-1", "sampler-2"]
      }

      response = GetSessionResponse.from_map(map)

      assert response.training_run_ids == ["model-1"]
      assert response.sampler_ids == ["sampler-1", "sampler-2"]
    end
  end

  describe "ListSessionsResponse" do
    test "creates struct with sessions list" do
      response = %ListSessionsResponse{
        sessions: ["session-1", "session-2", "session-3"]
      }

      assert length(response.sessions) == 3
    end
  end
end
```

```elixir
# test/tinkex/types/checkpoint_test.exs
defmodule Tinkex.Types.CheckpointTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{Checkpoint, CheckpointsListResponse, CheckpointArchiveUrlResponse}

  describe "Checkpoint" do
    test "creates struct with all fields" do
      checkpoint = %Checkpoint{
        checkpoint_id: "ckpt-123",
        checkpoint_type: "weights",
        tinker_path: "tinker://run-1/weights/0001",
        size_bytes: 1_000_000,
        public: false,
        time: "2025-11-20T10:00:00Z"
      }

      assert checkpoint.checkpoint_id == "ckpt-123"
      assert checkpoint.size_bytes == 1_000_000
    end

    test "size_bytes can be nil" do
      checkpoint = %Checkpoint{
        checkpoint_id: "ckpt-123",
        checkpoint_type: "weights",
        tinker_path: "tinker://run-1/weights/0001",
        size_bytes: nil,
        public: true,
        time: "2025-11-20T10:00:00Z"
      }

      assert checkpoint.size_bytes == nil
    end
  end

  describe "CheckpointsListResponse" do
    test "creates struct with checkpoints and cursor" do
      response = %CheckpointsListResponse{
        checkpoints: [
          %Checkpoint{checkpoint_id: "ckpt-1", checkpoint_type: "weights",
            tinker_path: "tinker://run-1/weights/0001", public: false, time: "2025-11-20T10:00:00Z"}
        ],
        cursor: %{"total_count" => 100, "offset" => 0}
      }

      assert length(response.checkpoints) == 1
      assert response.cursor.total_count == 100
    end
  end

  describe "CheckpointArchiveUrlResponse" do
    test "creates struct with url" do
      response = %CheckpointArchiveUrlResponse{
        url: "https://storage.example.com/checkpoint.tar"
      }

      assert response.url =~ "storage.example.com"
    end
  end
end
```

### 1.2 RestClient Tests

```elixir
# test/tinkex/rest_client_test.exs
defmodule Tinkex.RestClientTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.{RestClient, Config}

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
      {:ok, _response} = RestClient.list_sessions(client, limit: 50, offset: 100)
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

      assert length(response.checkpoints) == 1
      [ckpt] = response.checkpoints
      assert ckpt.checkpoint_id == "ckpt-1"
      assert ckpt.tinker_path == "tinker://run-123/weights/0001"
    end
  end

  describe "list_user_checkpoints/2" do
    test "returns paginated user checkpoints", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        assert conn.query_params["limit"] == "50"
        assert conn.query_params["offset"] == "0"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "checkpoints": [],
          "cursor": {"total_count": 150, "offset": 0}
        }))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.list_user_checkpoints(client)

      assert response.cursor.total_count == 150
    end
  end

  describe "get_checkpoint_archive_url/2" do
    test "returns download URL for checkpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints/archive_url", fn conn ->
        # URL should be encoded
        assert conn.query_params["tinker_path"] =~ "tinker://"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "url": "https://storage.example.com/checkpoints/ckpt-123.tar"
        }))
      end)

      client = RestClient.new("session-123", config)
      {:ok, response} = RestClient.get_checkpoint_archive_url(client, "tinker://run-123/weights/0001")

      assert response.url =~ "storage.example.com"
    end
  end

  describe "delete_checkpoint/2" do
    test "deletes checkpoint successfully", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "DELETE", "/api/v1/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": "deleted"}))
      end)

      client = RestClient.new("session-123", config)
      {:ok, _} = RestClient.delete_checkpoint(client, "tinker://run-123/weights/0001")
    end

    test "returns error when checkpoint not found", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "DELETE", "/api/v1/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, ~s({"error": "Checkpoint not found"}))
      end)

      client = RestClient.new("session-123", config)
      {:error, error} = RestClient.delete_checkpoint(client, "tinker://run-123/weights/9999")

      assert error.status == 404
    end
  end
end
```

### 1.3 API.Rest Tests

```elixir
# test/tinkex/api/rest_test.exs
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

      {:ok, _} = Rest.get_session(config, "session-abc")
    end
  end

  describe "list_sessions/3" do
    test "sends GET with pagination params", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/sessions", fn conn ->
        assert conn.query_params == %{"limit" => "10", "offset" => "20"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": []}))
      end)

      {:ok, _} = Rest.list_sessions(config, 10, 20)
    end
  end

  describe "list_checkpoints/2" do
    test "sends GET to training run checkpoints endpoint", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/v1/training_runs/run-xyz/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"checkpoints": []}))
      end)

      {:ok, _} = Rest.list_checkpoints(config, "run-xyz")
    end
  end

  describe "delete_checkpoint/2" do
    test "sends DELETE request", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "DELETE", "/api/v1/checkpoints", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({}))
      end)

      {:ok, _} = Rest.delete_checkpoint(config, "tinker://run-1/weights/0001")
    end
  end
end
```

---

## Stage 4: Async Client Factory Tests

```elixir
# test/tinkex/sampling_client_async_test.exs
defmodule Tinkex.SamplingClientAsyncTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.{ServiceClient, SamplingClient}

  setup :setup_http_client

  setup %{bypass: bypass, config: config} do
    # Stub session creation
    Bypass.stub(bypass, "POST", "/api/v1/create_session", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"session_id": "session-123"}))
    end)

    # Stub sampling session creation
    Bypass.stub(bypass, "POST", "/api/v1/create_sampling_session", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"sampling_session_id": "sampler-456"}))
    end)

    {:ok, service_pid} = ServiceClient.start_link(config: config)
    {:ok, service_pid: service_pid}
  end

  describe "create_async/2" do
    test "returns Task that resolves to sampling client", %{service_pid: service_pid} do
      task = SamplingClient.create_async(service_pid, model_path: "tinker://run-1/weights/0001")

      assert %Task{} = task

      {:ok, pid} = Task.await(task, 5000)
      assert is_pid(pid)
    end

    test "multiple async creates can run concurrently", %{service_pid: service_pid} do
      tasks = for i <- 1..3 do
        SamplingClient.create_async(service_pid, model_path: "tinker://run-#{i}/weights/0001")
      end

      results = Task.await_many(tasks, 5000)

      assert length(results) == 3
      assert Enum.all?(results, fn {:ok, pid} -> is_pid(pid) end)
    end
  end
end
```

```elixir
# test/tinkex/service_client_async_test.exs
defmodule Tinkex.ServiceClientAsyncTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.ServiceClient

  setup :setup_http_client

  # Similar setup stubs...

  describe "create_sampling_client_async/2" do
    test "returns Task that can be awaited", %{service_pid: service_pid} do
      task = ServiceClient.create_sampling_client_async(
        service_pid,
        model_path: "tinker://run-1/weights/0001"
      )

      {:ok, pid} = Task.await(task)
      assert is_pid(pid)
    end
  end
end
```

---

## Stage 5: Checkpoint Download Tests

```elixir
# test/tinkex/checkpoint_download_test.exs
defmodule Tinkex.CheckpointDownloadTest do
  use Tinkex.HTTPCase, async: false

  alias Tinkex.{CheckpointDownload, RestClient}

  setup :setup_http_client

  setup %{bypass: bypass, config: config} do
    # Create temp directory for downloads
    tmp_dir = System.tmp_dir!() |> Path.join("tinkex_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    client = RestClient.new("session-123", config)
    {:ok, client: client, tmp_dir: tmp_dir, bypass: bypass}
  end

  describe "download/3" do
    test "downloads and extracts checkpoint", %{bypass: bypass, client: client, tmp_dir: tmp_dir} do
      # Create a test tar file
      tar_content = create_test_tar()

      # Stub get_checkpoint_archive_url
      Bypass.expect_once(bypass, "GET", "/api/v1/checkpoints/archive_url", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"url": "#{endpoint_url(bypass)}/download/ckpt.tar"}))
      end)

      # Stub actual download
      Bypass.expect_once(bypass, "GET", "/download/ckpt.tar", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.put_resp_header("content-length", "#{byte_size(tar_content)}")
        |> Plug.Conn.resp(200, tar_content)
      end)

      {:ok, result} = CheckpointDownload.download(
        client,
        "tinker://run-123/weights/0001",
        output_dir: tmp_dir
      )

      assert result.destination =~ "run-123_weights_0001"
      assert File.exists?(result.destination)
    end

    test "returns error when target exists and force=false", %{client: client, tmp_dir: tmp_dir} do
      # Create existing directory
      existing_dir = Path.join(tmp_dir, "run-123_weights_0001")
      File.mkdir_p!(existing_dir)

      {:error, {:exists, path}} = CheckpointDownload.download(
        client,
        "tinker://run-123/weights/0001",
        output_dir: tmp_dir
      )

      assert path == existing_dir
    end

    test "overwrites when force=true", %{bypass: bypass, client: client, tmp_dir: tmp_dir} do
      tar_content = create_test_tar()

      # Create existing directory with a file
      existing_dir = Path.join(tmp_dir, "run-123_weights_0001")
      File.mkdir_p!(existing_dir)
      File.write!(Path.join(existing_dir, "old_file.txt"), "old content")

      # Stubs...
      Bypass.stub(bypass, "GET", "/api/v1/checkpoints/archive_url", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"url": "#{endpoint_url(bypass)}/download/ckpt.tar"}))
      end)

      Bypass.stub(bypass, "GET", "/download/ckpt.tar", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.resp(200, tar_content)
      end)

      {:ok, result} = CheckpointDownload.download(
        client,
        "tinker://run-123/weights/0001",
        output_dir: tmp_dir,
        force: true
      )

      # Old file should be gone
      refute File.exists?(Path.join(result.destination, "old_file.txt"))
    end

    test "reports progress via callback", %{bypass: bypass, client: client, tmp_dir: tmp_dir} do
      tar_content = create_test_tar()
      test_pid = self()

      Bypass.stub(bypass, "GET", "/api/v1/checkpoints/archive_url", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"url": "#{endpoint_url(bypass)}/download/ckpt.tar"}))
      end)

      Bypass.stub(bypass, "GET", "/download/ckpt.tar", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.put_resp_header("content-length", "#{byte_size(tar_content)}")
        |> Plug.Conn.resp(200, tar_content)
      end)

      progress_fn = fn downloaded, total ->
        send(test_pid, {:progress, downloaded, total})
      end

      {:ok, _} = CheckpointDownload.download(
        client,
        "tinker://run-123/weights/0001",
        output_dir: tmp_dir,
        progress: progress_fn
      )

      assert_receive {:progress, _, _}, 1000
    end
  end

  # Helper to create a test tar archive
  defp create_test_tar do
    # Create a simple tar with one file
    tmp_file = System.tmp_dir!() |> Path.join("test_file.txt")
    File.write!(tmp_file, "test content")

    tar_path = System.tmp_dir!() |> Path.join("test.tar")
    :erl_tar.create(tar_path, [{String.to_charlist(tmp_file), 'test_file.txt'}])

    content = File.read!(tar_path)
    File.rm!(tmp_file)
    File.rm!(tar_path)
    content
  end
end
```

---

## Integration Tests

```elixir
# test/integration/sessions_test.exs
defmodule Tinkex.Integration.SessionsTest do
  use Tinkex.HTTPCase, async: false

  @moduletag :integration

  alias Tinkex.{ServiceClient, RestClient}

  setup :setup_http_client

  # Full integration tests with real-ish flow
  describe "session management flow" do
    test "creates service client, gets rest client, lists sessions", %{bypass: bypass, config: config} do
      # Stub all endpoints
      Bypass.stub(bypass, "POST", "/api/v1/create_session", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"session_id": "session-integration"}))
      end)

      Bypass.stub(bypass, "GET", "/api/v1/sessions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"sessions": ["session-1", "session-2"]}))
      end)

      # Execute flow
      {:ok, service_pid} = ServiceClient.start_link(config: config)
      {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

      assert %RestClient{} = rest_client

      {:ok, response} = RestClient.list_sessions(rest_client)
      assert length(response.sessions) == 2
    end
  end
end
```

```elixir
# test/integration/checkpoints_test.exs
defmodule Tinkex.Integration.CheckpointsTest do
  use Tinkex.HTTPCase, async: false

  @moduletag :integration

  alias Tinkex.{ServiceClient, RestClient}

  setup :setup_http_client

  describe "checkpoint management flow" do
    test "lists and deletes checkpoints", %{bypass: bypass, config: config} do
      # Setup stubs
      Bypass.stub(bypass, "POST", "/api/v1/create_session", fn conn ->
        conn |> Plug.Conn.resp(200, ~s({"session_id": "session-1"}))
      end)

      Bypass.stub(bypass, "GET", "/api/v1/checkpoints", fn conn ->
        conn |> Plug.Conn.resp(200, ~s({
          "checkpoints": [{
            "checkpoint_id": "ckpt-1",
            "checkpoint_type": "weights",
            "tinker_path": "tinker://run-1/weights/0001",
            "public": false,
            "time": "2025-11-20T10:00:00Z"
          }],
          "cursor": {"total_count": 1}
        }))
      end)

      Bypass.stub(bypass, "DELETE", "/api/v1/checkpoints", fn conn ->
        conn |> Plug.Conn.resp(200, ~s({}))
      end)

      # Execute flow
      {:ok, service_pid} = ServiceClient.start_link(config: config)
      {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

      {:ok, list_response} = RestClient.list_user_checkpoints(rest_client)
      assert length(list_response.checkpoints) == 1

      [checkpoint] = list_response.checkpoints
      {:ok, _} = RestClient.delete_checkpoint(rest_client, checkpoint.tinker_path)
    end
  end
end
```

---

## Test Commands

```bash
# Run all tests
mix test

# Run specific test file
mix test test/tinkex/rest_client_test.exs

# Run only unit tests (exclude integration)
mix test --exclude integration

# Run only integration tests
mix test --only integration

# Run with coverage
mix test --cover

# Run specific test by line
mix test test/tinkex/rest_client_test.exs:42
```

---

## Test Checklist

### Stage 1: Foundation
- [ ] GetSessionResponse type tests
- [ ] ListSessionsResponse type tests
- [ ] Checkpoint type tests
- [ ] CheckpointsListResponse type tests
- [ ] CheckpointArchiveUrlResponse type tests
- [ ] RestClient.new/2 tests
- [ ] API.Rest endpoint tests

### Stage 2: Sessions
- [ ] RestClient.get_session/2 tests
- [ ] RestClient.list_sessions/2 tests
- [ ] Error handling tests

### Stage 3: Checkpoints
- [ ] RestClient.list_checkpoints/2 tests
- [ ] RestClient.list_user_checkpoints/2 tests
- [ ] RestClient.get_checkpoint_archive_url/2 tests
- [ ] RestClient.delete_checkpoint/2 tests
- [ ] Pagination tests

### Stage 4: Async
- [ ] SamplingClient.create_async/2 tests
- [ ] ServiceClient.create_sampling_client_async/2 tests
- [ ] TrainingClient.create_sampling_client_async/3 tests
- [ ] Concurrent creation tests

### Stage 5: Download
- [ ] CheckpointDownload.download/3 tests
- [ ] Force overwrite tests
- [ ] Progress callback tests
- [ ] Error handling tests

### Integration
- [ ] Full session flow test
- [ ] Full checkpoint flow test
- [ ] Download flow test
