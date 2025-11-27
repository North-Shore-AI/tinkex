defmodule Tinkex.CLICheckpointTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureIO

  alias Tinkex.CLI
  alias Tinkex.Types.LoraConfig

  defmodule ServiceStub do
    def start_link(opts) do
      send(self(), {:service_started, opts})
      {:ok, {:service_stub, opts}}
    end

    def create_lora_training_client(service, base_model, opts \\ []) do
      send(self(), {:training_client_created, service, base_model, opts})
      {:ok, {:training_stub, service, base_model, opts}}
    end
  end

  defmodule TrainingStub do
    def save_weights_for_sampler(training, name, opts \\ []) do
      send(self(), {:save_weights_called, training, name, opts})

      task =
        Task.async(fn ->
          {:ok,
           %{"model_id" => "model-xyz", "path" => "/remote/snapshot.bin", "status" => "saved"}}
        end)

      {:ok, task}
    end
  end

  defmodule ErrorTrainingStub do
    def save_weights_for_sampler(_training, _name, _opts \\ []) do
      task =
        Task.async(fn ->
          {:error,
           %Tinkex.Error{
             message: "quota exceeded",
             category: :user,
             type: :validation,
             status: 400
           }}
        end)

      {:ok, task}
    end
  end

  setup do
    :ok
  end

  test "saves checkpoint and writes metadata" do
    Application.put_env(:tinkex, :cli_checkpoint_deps, %{
      service_client_module: ServiceStub,
      training_client_module: TrainingStub,
      now_fun: fn -> ~U[2025-01-01 00:00:00Z] end
    })

    on_exit(fn -> Application.delete_env(:tinkex, :cli_checkpoint_deps) end)

    output_path =
      Path.join(
        System.tmp_dir!(),
        "tinkex_cli_checkpoint_#{System.unique_integer([:positive])}.json"
      )

    args = [
      "checkpoint",
      "--base-model",
      "Qwen/Qwen2.5-7B",
      "--rank",
      "8",
      "--output",
      output_path,
      "--api-key",
      "test-key",
      "--base-url",
      "http://localhost",
      "--timeout",
      "1000"
    ]

    output =
      capture_io(fn ->
        assert {:ok, %{command: :checkpoint, metadata: metadata}} = CLI.run(args)
        assert metadata["model_id"] == "model-xyz"
        assert metadata["weights_path"] == "/remote/snapshot.bin"
      end)

    assert File.exists?(output_path)

    {:ok, file_metadata} = File.read!(output_path) |> Jason.decode()

    assert %{
             "base_model" => "Qwen/Qwen2.5-7B",
             "model_id" => "model-xyz",
             "weights_path" => "/remote/snapshot.bin",
             "saved_at" => "2025-01-01T00:00:00Z"
           } = Map.take(file_metadata, ["base_model", "model_id", "weights_path", "saved_at"])

    assert is_map(file_metadata["response"])
    refute output =~ "Starting service client"
    refute output =~ "Creating training client"
    refute output =~ "Saving weights"

    assert_receive {:service_started, _opts}
    assert_receive {:training_client_created, {:service_stub, _}, base_model, training_opts}

    assert base_model == "Qwen/Qwen2.5-7B"

    assert %LoraConfig{rank: 8, train_mlp: true, train_attn: true, train_unembed: true} =
             training_opts[:lora_config]

    assert_receive {:save_weights_called, {:training_stub, _, _, _}, _name, save_opts}
    assert Keyword.get(save_opts, :timeout) == 1000
  end

  test "prints input guidance on user errors" do
    Application.put_env(:tinkex, :cli_checkpoint_deps, %{
      service_client_module: ServiceStub,
      training_client_module: ErrorTrainingStub,
      now_fun: fn -> ~U[2025-01-01 00:00:00Z] end
    })

    on_exit(fn -> Application.delete_env(:tinkex, :cli_checkpoint_deps) end)

    output_path =
      Path.join(
        System.tmp_dir!(),
        "tinkex_cli_checkpoint_err_#{System.unique_integer([:positive])}.json"
      )

    stderr =
      capture_io(:stderr, fn ->
        assert {:error, %Tinkex.Error{category: :user}} =
                 CLI.run([
                   "checkpoint",
                   "--base-model",
                   "Qwen/Qwen2.5-7B",
                   "--output",
                   output_path,
                   "--api-key",
                   "test-key"
                 ])
      end)

    assert stderr =~ "Please check your inputs"
    refute File.exists?(output_path)
  end
end
