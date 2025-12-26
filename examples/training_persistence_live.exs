defmodule Tinkex.Examples.TrainingPersistenceLive do
  @moduledoc """
  Live checkpoint save/load demo.
  """

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_base_model "meta-llama/Llama-3.1-8B"
  @await_timeout :infinity

  alias Tinkex.Error
  alias Tinkex.Types.{LoraConfig, LoadWeightsResponse, SaveWeightsResponse}

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_base_model)
    checkpoint_name = "demo-checkpoint-#{System.system_time(:second)}"

    IO.puts("Base URL: #{base_url}")
    IO.puts("Base model: #{base_model}")
    IO.puts("Checkpoint name: #{checkpoint_name}")

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, training} <-
           Tinkex.ServiceClient.create_lora_training_client(service, base_model,
             lora_config: %LoraConfig{rank: 8}
           ),
         {:ok, save_task} <- Tinkex.TrainingClient.save_state(training, checkpoint_name),
         {:ok, %SaveWeightsResponse{path: path}} <- await(save_task, "save_state"),
         :ok <- IO.puts("Saved checkpoint to #{path}"),
         {:ok, load_task} <- Tinkex.TrainingClient.load_state_with_optimizer(training, path),
         {:ok, %LoadWeightsResponse{}} <- await(load_task, "load_state_with_optimizer"),
         :ok <- IO.puts("Reloaded checkpoint with optimizer state"),
         {:ok, restored} <-
           Tinkex.ServiceClient.create_training_client_from_state(
             service,
             path,
             load_optimizer: true
           ) do
      IO.puts("Created a fresh training client from checkpoint: #{inspect(restored)}")
      shutdown([restored, training, service])
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Error: #{Error.format(error)}")
        if error.data, do: IO.puts(:stderr, inspect(error.data))
        System.halt(1)

      {:error, other} ->
        IO.puts(:stderr, "Error: #{inspect(other)}")
        System.halt(1)

      other ->
        IO.puts(:stderr, "Unexpected response: #{inspect(other)}")
        System.halt(1)
    end
  end

  defp await(task, label) do
    try do
      case Task.await(task, @await_timeout) do
        {:ok, value} -> {:ok, value}
        {:error, %Error{} = error} -> {:error, error}
        other -> {:error, {:unexpected_reply, label, other}}
      end
    catch
      :exit, reason ->
        {:error, {:task_exit, label, reason}}
    end
  end

  defp fetch_env!(var) do
    case System.get_env(var) do
      nil -> raise "Set #{var} to run this example"
      value -> value
    end
  end

  defp shutdown(pids) do
    Enum.each(pids, fn pid ->
      if is_pid(pid), do: Process.exit(pid, :normal)
    end)

    :ok
  end
end

Tinkex.Examples.TrainingPersistenceLive.run()
