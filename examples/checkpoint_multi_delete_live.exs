defmodule Tinkex.Examples.CheckpointMultiDeleteLive do
  @moduledoc """
  Live multi-delete demo: creates two checkpoints, caches their paths, then
  deletes both in a single CLI invocation. Requires only `TINKER_API_KEY`.
  """

  @base_model "meta-llama/Llama-3.1-8B"
  @checkpoint_cache Path.join(["tmp", "checkpoints", "default.path"])

  alias Tinkex.{CLI, Config, Error, ServiceClient, TrainingClient}
  alias Tinkex.Types.{LoraConfig, SaveWeightsResponse}

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    File.mkdir_p!(Path.dirname(@checkpoint_cache))

    timestamp = System.system_time(:second)
    names = ["multi-delete-#{timestamp}-a", "multi-delete-#{timestamp}-b"]

    with {:ok, config} <- build_config(),
         await_timeout = compute_await_timeout(config),
         {:ok, service} <- ServiceClient.start_link(config: config),
         {:ok, training} <-
           ServiceClient.create_lora_training_client(service, @base_model,
             lora_config: %LoraConfig{rank: 8}
           ),
         {:ok, paths} <- save_checkpoints(training, names, await_timeout),
         :ok <- cache_default_path(paths),
         {:ok, delete_summary} <- run_multi_delete(paths),
         :ok <- shutdown([training, service]) do
      IO.puts("\nMulti-delete summary:")
      IO.inspect(delete_summary, label: "result")
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Error: #{Error.format(error)}")
        if error.data, do: IO.inspect(error.data, label: "data")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp build_config do
    {:ok, Config.new()}
  rescue
    e -> {:error, e}
  end

  defp compute_await_timeout(%Config{} = config) do
    # Saving checkpoints can exceed a single request timeout (server 408 + client retries).
    # Await long enough to cover worst-case (attempts + jitter), but keep bounded.
    worst_case = config.timeout * (config.max_retries + 1) + 30_000
    max(60_000, min(worst_case, 15 * 60_000))
  end

  defp save_checkpoints(training, names, await_timeout) do
    names
    |> Enum.map(&save_checkpoint(training, &1, await_timeout))
    |> Enum.reduce_while([], fn
      {:ok, path}, acc -> {:cont, [path | acc]}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:error, _} = error -> error
      paths -> {:ok, Enum.reverse(paths)}
    end
  end

  defp save_checkpoint(training, name, await_timeout) do
    with {:ok, task} <- TrainingClient.save_state(training, name),
         {:ok, %SaveWeightsResponse{path: path}} <-
           await(task, "save_state #{name}", await_timeout) do
      IO.puts("Saved checkpoint #{name}: #{path}")
      {:ok, path}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, other}
    end
  end

  defp run_multi_delete(paths) do
    IO.puts("\nDeleting #{length(paths)} checkpoints with one confirmation...")
    args = ["checkpoint", "delete"] ++ paths ++ ["--yes"]

    case CLI.run(args) do
      {:ok, summary} -> {:ok, summary}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cache_default_path([first | _]) do
    File.write!(@checkpoint_cache, first)
    IO.puts("Cached default checkpoint path at #{@checkpoint_cache}: #{first}")
    :ok
  end

  defp cache_default_path([]), do: :ok

  defp await(task, label, timeout_ms) do
    try do
      case Task.await(task, timeout_ms) do
        {:ok, value} -> {:ok, value}
        {:error, %Error{} = error} -> {:error, error}
        other -> {:error, {:unexpected_reply, label, other}}
      end
    catch
      :exit, reason ->
        {:error, {:task_exit, label, reason}}
    end
  end

  defp shutdown(pids) do
    Enum.each(pids, fn pid ->
      if is_pid(pid), do: Process.exit(pid, :normal)
    end)

    :ok
  end
end

Tinkex.Examples.CheckpointMultiDeleteLive.run()
