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
      {:ok, %{}}
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
