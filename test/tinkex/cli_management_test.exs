defmodule Tinkex.CLIManagementTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureIO

  alias Tinkex.CLI

  defmodule RestStub do
    @checkpoints [
      %{
        "checkpoint_id" => "ckpt-run-a-1",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-a/weights/0001",
        "public" => true,
        "size_bytes" => 1_024,
        "time" => "2025-11-26T00:00:00Z"
      },
      %{
        "checkpoint_id" => "ckpt-run-a-2",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-a/weights/0002",
        "public" => false,
        "size_bytes" => 2_048,
        "time" => "2025-11-26T00:01:00Z"
      },
      %{
        "checkpoint_id" => "ckpt-run-b-1",
        "checkpoint_type" => "sampler_weights",
        "tinker_path" => "tinker://run-b/sampler_weights/0001",
        "public" => false,
        "size_bytes" => 512,
        "time" => "2025-11-26T00:02:00Z"
      }
    ]

    @runs [
      %{
        "training_run_id" => "run-a",
        "base_model" => "meta-llama/Llama",
        "model_owner" => "owner-a",
        "is_lora" => true,
        "lora_rank" => 4,
        "corrupted" => false,
        "last_request_time" => "2025-11-26T00:00:00Z",
        "last_checkpoint" => Enum.at(@checkpoints, 0),
        "last_sampler_checkpoint" => Enum.at(@checkpoints, 1),
        "user_metadata" => %{"stage" => "prod"}
      },
      %{
        "training_run_id" => "run-b",
        "base_model" => "meta-llama/Llama",
        "model_owner" => "owner-b",
        "is_lora" => true,
        "lora_rank" => 8,
        "corrupted" => true,
        "last_request_time" => "2025-11-26T00:05:00Z",
        "last_checkpoint" => Enum.at(@checkpoints, 1),
        "last_sampler_checkpoint" => Enum.at(@checkpoints, 2),
        "user_metadata" => %{"stage" => "dev"}
      },
      %{
        "training_run_id" => "run-c",
        "base_model" => "meta-llama/Llama",
        "model_owner" => "owner-c",
        "is_lora" => false,
        "corrupted" => false,
        "last_request_time" => "2025-11-26T00:10:00Z",
        "last_checkpoint" => nil,
        "last_sampler_checkpoint" => nil,
        "user_metadata" => nil
      }
    ]

    def list_user_checkpoints(_config, limit, offset) do
      send(self(), {:list_user, limit, offset})

      slice =
        @checkpoints
        |> Enum.drop(offset)
        |> Enum.take(limit)

      {:ok,
       %{
         "checkpoints" => slice,
         "cursor" => %{
           "total_count" => length(@checkpoints),
           "offset" => offset,
           "limit" => limit
         }
       }}
    end

    def list_checkpoints(_config, run_id) do
      send(self(), {:list_run, run_id})

      {:ok,
       %{
         "checkpoints" =>
           Enum.filter(@checkpoints, fn ckpt ->
             String.starts_with?(ckpt["tinker_path"], "tinker://#{run_id}/")
           end)
       }}
    end

    def get_weights_info_by_tinker_path(_config, path) do
      send(self(), {:weights_info, path})

      {:ok,
       %{
         "base_model" => "meta-llama/Llama-3.1-8B",
         "is_lora" => true,
         "lora_rank" => 16
       }}
    end

    def publish_checkpoint(_config, path) do
      send(self(), {:publish, path})
      {:ok, %{"status" => "published"}}
    end

    def unpublish_checkpoint(_config, path) do
      send(self(), {:unpublish, path})
      {:ok, %{"status" => "unpublished"}}
    end

    def delete_checkpoint(_config, path) do
      send(self(), {:delete, path})

      case Process.get({:delete, path}) do
        :fail -> {:error, Tinkex.Error.new(:api_status, "failed delete", status: 500)}
        _ -> {:ok, %{}}
      end
    end

    def list_training_runs(_config, limit, offset) do
      send(self(), {:runs, limit, offset})

      slice =
        @runs
        |> Enum.drop(offset)
        |> Enum.take(limit)

      {:ok,
       %{
         "training_runs" => slice,
         "cursor" => %{
           "total_count" => length(@runs),
           "offset" => offset,
           "limit" => limit
         }
       }}
    end

    def get_training_run(_config, run_id) do
      send(self(), {:run_info, run_id})

      {:ok, Enum.find(@runs, fn run -> run["training_run_id"] == run_id end)}
    end
  end

  setup do
    Application.put_env(:tinkex, :cli_management_deps, %{
      rest_api_module: RestStub,
      config_module: Tinkex.Config,
      json_module: Jason,
      checkpoint_page_size: 2,
      run_page_size: 2
    })

    on_exit(fn -> Application.delete_env(:tinkex, :cli_management_deps) end)
  end

  test "checkpoint list paginates with progress, limit=0, and json format" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:ok, %{command: :checkpoint, action: :list, count: 3, total: 3}} =
                     CLI.run([
                       "checkpoint",
                       "list",
                       "--limit",
                       "0",
                       "--api-key",
                       "k",
                       "--format",
                       "json"
                     ])
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, stdout}
    assert stderr =~ "Fetching checkpoints"
    assert stderr =~ "3/3"

    data = Jason.decode!(stdout)
    assert data["total"] == 3
    assert data["shown"] == 3
    assert length(data["checkpoints"]) == 3
    assert_received {:list_user, 2, 0}
    assert_received {:list_user, 1, 2}
  end

  test "checkpoint list supports run filter and json output" do
    stdout =
      capture_io(fn ->
        assert {:ok, %{command: :checkpoint, action: :list, count: 2, run_id: "run-a"}} =
                 CLI.run([
                   "checkpoint",
                   "list",
                   "--run-id",
                   "run-a",
                   "--api-key",
                   "k",
                   "--format",
                   "json"
                 ])
      end)

    data = Jason.decode!(stdout)
    assert data["run_id"] == "run-a"
    assert length(data["checkpoints"]) == 2

    assert Enum.all?(
             data["checkpoints"],
             &String.starts_with?(&1["tinker_path"], "tinker://run-a/")
           )

    assert_received {:list_run, "run-a"}
    refute_received {:list_user, _, _}
  end

  test "checkpoint info returns metadata merged with weights info" do
    stdout =
      capture_io(fn ->
        assert {:ok, %{command: :checkpoint, action: :info}} =
                 CLI.run([
                   "checkpoint",
                   "info",
                   "tinker://run-a/weights/0001",
                   "--api-key",
                   "k",
                   "--format",
                   "json"
                 ])
      end)

    data = Jason.decode!(stdout)

    assert data["checkpoint_id"] == "ckpt-run-a-1"
    assert data["checkpoint_type"] == "weights"
    assert data["training_run_id"] == "run-a"
    assert data["size_bytes"] == 1024
    assert data["public"] == true
    assert data["time"] == "2025-11-26T00:00:00Z"
    assert data["base_model"] == "meta-llama/Llama-3.1-8B"
    assert data["is_lora"] == true
    assert data["lora_rank"] == 16

    assert_received {:weights_info, "tinker://run-a/weights/0001"}
  end

  test "checkpoint publish and unpublish dispatch to API" do
    capture_io(fn ->
      assert {:ok, %{command: :checkpoint, action: :publish}} =
               CLI.run(["checkpoint", "publish", "tinker://run-1/weights/0001", "--api-key", "k"])
    end)

    assert_received {:publish, "tinker://run-1/weights/0001"}

    capture_io(fn ->
      assert {:ok, %{command: :checkpoint, action: :unpublish}} =
               CLI.run([
                 "checkpoint",
                 "unpublish",
                 "tinker://run-1/weights/0001",
                 "--api-key",
                 "k"
               ])
    end)

    assert_received {:unpublish, "tinker://run-1/weights/0001"}
  end

  test "checkpoint delete supports multiple paths with a single confirmation" do
    output =
      capture_io("y\n", fn ->
        assert {:ok, %{command: :checkpoint, action: :delete, deleted: 2, failed: 0}} =
                 CLI.run([
                   "checkpoint",
                   "delete",
                   "tinker://run-1/weights/0001",
                   "tinker://run-2/weights/0002",
                   "--api-key",
                   "k"
                 ])
      end)

    assert output =~ "Preparing to delete 2 checkpoints"
    assert output =~ "Deleting 1/2: tinker://run-1/weights/0001"
    assert output =~ "Deleting 2/2: tinker://run-2/weights/0002"

    assert_received {:delete, "tinker://run-1/weights/0001"}
    assert_received {:delete, "tinker://run-2/weights/0002"}
  end

  test "checkpoint delete aggregates failures while continuing" do
    Process.put({:delete, "tinker://run-2/weights/0002"}, :fail)

    stderr =
      capture_io(:stderr, fn ->
        _output =
          capture_io("y\n", fn ->
            assert {:error,
                    %{
                      command: :checkpoint,
                      action: :delete,
                      deleted: 1,
                      failed: 1,
                      failures: [%{path: "tinker://run-2/weights/0002"}]
                    }} =
                     CLI.run([
                       "checkpoint",
                       "delete",
                       "tinker://run-1/weights/0001",
                       "tinker://run-2/weights/0002",
                       "--api-key",
                       "k"
                     ])
          end)
      end)

    assert stderr =~
             "Delete failed for tinker://run-2/weights/0002: [api_status (500)] failed delete"

    assert_received {:delete, "tinker://run-1/weights/0001"}
    assert_received {:delete, "tinker://run-2/weights/0002"}

    Process.delete({:delete, "tinker://run-2/weights/0002"})
  end

  test "checkpoint delete validates tinker:// paths" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:error, %Tinkex.Error{type: :validation, category: :user}} =
                 CLI.run([
                   "checkpoint",
                   "delete",
                   "/not-a-tinker-path",
                   "--api-key",
                   "k"
                 ])
      end)

    assert stderr =~ "Checkpoint path"
    refute_received {:delete, _}
  end

  test "checkpoint delete aborts when confirmation is declined" do
    output =
      capture_io("n\n", fn ->
        assert {:ok, %{action: :delete, cancelled: true, paths: ["tinker://run-1/weights/0001"]}} =
                 CLI.run([
                   "checkpoint",
                   "delete",
                   "tinker://run-1/weights/0001",
                   "--api-key",
                   "k"
                 ])
      end)

    assert output =~ "Aborted delete of 1 checkpoint"
    refute_received {:delete, _}
  end

  test "checkpoint delete --yes skips confirmation" do
    output =
      capture_io(fn ->
        assert {:ok, %{action: :delete, deleted: 1, failed: 0}} =
                 CLI.run([
                   "checkpoint",
                   "delete",
                   "tinker://run-1/weights/0001",
                   "--api-key",
                   "k",
                   "--yes"
                 ])
      end)

    refute output =~ "Proceed?"
    assert_received {:delete, "tinker://run-1/weights/0001"}
  end

  test "run list paginates with progress and emits json" do
    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            assert {:ok, %{command: :run, action: :list, count: 3, total: 3}} =
                     CLI.run([
                       "run",
                       "list",
                       "--limit",
                       "0",
                       "--api-key",
                       "k",
                       "--format",
                       "json"
                     ])
          end)

        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, stdout}
    assert stderr =~ "Fetching training runs"
    assert stderr =~ "3/3"

    data = Jason.decode!(stdout)
    assert length(data["runs"]) == 3

    first = hd(data["runs"])
    assert first["model_owner"]
    assert Map.has_key?(first, "user_metadata")
    assert first["last_checkpoint"]["checkpoint_id"] == "ckpt-run-a-1"
    assert first["last_sampler_checkpoint"]["checkpoint_id"] == "ckpt-run-a-2"

    assert_received {:runs, 2, 0}
    assert_received {:runs, 1, 2}
  end

  test "run info surfaces owner, lora rank, status, checkpoints, and metadata" do
    output =
      capture_io(fn ->
        assert {:ok, %{command: :run, action: :info, run_id: "run-b"}} =
                 CLI.run(["run", "info", "run-b", "--api-key", "k"])
      end)

    assert output =~ "run-b"
    assert output =~ "Owner: owner-b"
    assert output =~ "LoRA rank: 8"
    assert output =~ "Status: Failed"
    assert output =~ "Last training checkpoint: ckpt-run-a-2"
    assert output =~ "Metadata: stage=dev"
    assert_received {:run_info, "run-b"}
  end
end
