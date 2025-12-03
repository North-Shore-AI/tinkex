defmodule Tinkex.CLIManagementTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureIO

  alias Tinkex.CLI

  defmodule RestStub do
    def list_user_checkpoints(_config, limit, offset) do
      send(self(), {:list_user, limit, offset})

      {:ok,
       %{
         "checkpoints" => [
           %{
             "checkpoint_id" => "ckpt-1",
             "checkpoint_type" => "weights",
             "tinker_path" => "tinker://run-1/weights/0001",
             "public" => false,
             "time" => "2025-11-26T00:00:00Z"
           }
         ],
         "cursor" => %{"total_count" => 1, "offset" => offset}
       }}
    end

    def get_weights_info_by_tinker_path(_config, path) do
      send(self(), {:weights_info, path})
      {:ok, %{"base_model" => "Qwen/Qwen2.5-7B", "is_lora" => true, "lora_rank" => 16}}
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

      {:ok,
       %{
         "training_runs" => [
           %{
             "training_run_id" => "run-1",
             "base_model" => "meta-llama/Llama",
             "model_owner" => "owner",
             "is_lora" => false,
             "corrupted" => false,
             "last_request_time" => "2025-11-26T00:00:00Z"
           }
         ],
         "cursor" => %{"total_count" => 1, "offset" => offset}
       }}
    end

    def get_training_run(_config, run_id) do
      send(self(), {:run_info, run_id})

      {:ok,
       %{
         "training_run_id" => run_id,
         "base_model" => "meta-llama/Llama",
         "model_owner" => "owner",
         "is_lora" => true,
         "lora_rank" => 8,
         "corrupted" => false,
         "last_request_time" => "2025-11-26T00:00:00Z"
       }}
    end
  end

  setup do
    Application.put_env(:tinkex, :cli_management_deps, %{
      rest_api_module: RestStub,
      config_module: Tinkex.Config,
      json_module: Jason
    })

    on_exit(fn -> Application.delete_env(:tinkex, :cli_management_deps) end)
  end

  test "checkpoint list prints checkpoints and returns ok" do
    output =
      capture_io(fn ->
        assert {:ok, %{command: :checkpoint, action: :list, count: 1}} =
                 CLI.run(["checkpoint", "list", "--api-key", "k", "--base-url", "http://example"])
      end)

    assert output =~ "ckpt-1"
    assert output =~ "tinker://run-1/weights/0001"
    assert_received {:list_user, 20, 0}
  end

  test "checkpoint info fetches weights info" do
    output =
      capture_io(fn ->
        assert {:ok, %{command: :checkpoint, action: :info}} =
                 CLI.run([
                   "checkpoint",
                   "info",
                   "tinker://run-1/weights/0001",
                   "--api-key",
                   "k"
                 ])
      end)

    assert output =~ "Qwen/Qwen2.5-7B"
    assert_received {:weights_info, "tinker://run-1/weights/0001"}
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
        assert {:error, %Tinkex.Error{type: :validation}} =
                 CLI.run([
                   "checkpoint",
                   "delete",
                   "/not-a-tinker-path",
                   "--api-key",
                   "k"
                 ])
      end)

    assert stderr =~ "Checkpoint paths must start with tinker://"
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

  test "run list prints entries" do
    output =
      capture_io(fn ->
        assert {:ok, %{command: :run, action: :list, count: 1}} =
                 CLI.run(["run", "list", "--api-key", "k", "--base-url", "http://example"])
      end)

    assert output =~ "run-1"
    assert_received {:runs, 20, 0}
  end

  test "run info fetches a training run" do
    output =
      capture_io(fn ->
        assert {:ok, %{command: :run, action: :info, run_id: "run-1"}} =
                 CLI.run(["run", "info", "run-1", "--api-key", "k"])
      end)

    assert output =~ "run-1"
    assert output =~ "meta-llama/Llama"
    assert_received {:run_info, "run-1"}
  end
end
