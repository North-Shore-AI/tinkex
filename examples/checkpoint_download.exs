defmodule Tinkex.Examples.CheckpointDownloadExample do
  @moduledoc """
  Example demonstrating checkpoint download functionality.

  Shows how to:
  - Download and extract checkpoint archive
  - Track progress during download
  """

  alias Tinkex.{
    ServiceClient,
    RestClient,
    CheckpointDownload,
    Config,
    TrainingClient,
    Error
  }

  alias Tinkex.Types.{AdamParams, Datum, LoraConfig, ModelInput, TensorData}

  def run do
    IO.puts("=== Tinkex Checkpoint Download Example ===\n")

    {:ok, _} = Application.ensure_all_started(:tinkex)

    base_url =
      System.get_env("TINKER_BASE_URL") ||
        Application.get_env(
          :tinkex,
          :base_url,
          "https://tinker.thinkingmachines.dev/services/tinker-prod"
        )

    config =
      Config.new(
        api_key: System.get_env("TINKER_API_KEY") || raise("TINKER_API_KEY required"),
        base_url: base_url
      )

    {:ok, service_pid} = ServiceClient.start_link(config: config)
    {:ok, rest_client} = ServiceClient.create_rest_client(service_pid)

    {checkpoint_path, path_source} =
      case resolve_checkpoint_path(rest_client, service_pid) do
        {:ok, path, source} ->
          {path, source}

        {:error, :no_checkpoints} ->
          raise """
          No checkpoints found for this account. Set TINKER_CHECKPOINT_PATH (e.g., tinker://run-123/weights/0001)
          or create a checkpoint via training before running the example.
          """

        {:error, :no_available_checkpoints} ->
          raise """
          Could not find a downloadable checkpoint automatically. The most recent entries returned 404/403.
          Set TINKER_CHECKPOINT_PATH to a known-good checkpoint path and rerun the example.
          """

        {:error, {:api_error, %Error{} = error}} ->
          raise """
          Failed to discover checkpoints automatically: #{Error.format(error)}.
          Set TINKER_CHECKPOINT_PATH manually or rerun later.
          """

        {:error, {:api_error, other}} ->
          raise """
          Failed to discover checkpoints automatically: #{inspect(other)}.
          Set TINKER_CHECKPOINT_PATH manually or rerun later.
          """

        {:error, {:archive_unavailable, source, %Error{} = error}} ->
          raise """
          The checkpoint source (#{inspect(source)}) is not downloadable: #{Error.format(error)}.
          Set TINKER_CHECKPOINT_PATH to a known-good checkpoint and rerun.
          """

        {:error, {:archive_unavailable, source, other}} ->
          raise """
          The checkpoint source (#{inspect(source)}) is not downloadable: #{inspect(other)}.
          Set TINKER_CHECKPOINT_PATH to a known-good checkpoint and rerun.
          """
      end

    if path_source == :auto do
      IO.puts(
        "TINKER_CHECKPOINT_PATH not provided; downloading first available checkpoint:\n  #{checkpoint_path}\n"
      )
    end

    output_dir =
      System.get_env("TINKER_OUTPUT_DIR") ||
        Path.join(System.tmp_dir!(), "tinkex_checkpoints")

    IO.puts("Downloading checkpoint: #{checkpoint_path}")
    IO.puts("Output directory: #{output_dir}\n")

    # Progress callback
    progress_fn = fn downloaded, total ->
      percent = if total > 0, do: Float.round(downloaded / total * 100, 1), else: 0
      IO.write("\rProgress: #{percent}% (#{format_size(downloaded)} / #{format_size(total)})")
    end

    force? = System.get_env("FORCE") == "true"

    case CheckpointDownload.download(rest_client, checkpoint_path,
           output_dir: output_dir,
           force: force?,
           progress: progress_fn
         ) do
      {:ok, result} ->
        IO.puts("\n\nDownload complete!")
        IO.puts("Extracted to: #{result.destination}")

        if File.exists?(result.destination) do
          files = File.ls!(result.destination)
          IO.puts("\nExtracted files (#{length(files)}):")

          Enum.each(files, fn file ->
            path = Path.join(result.destination, file)
            stat = File.stat!(path)
            IO.puts("  • #{file} (#{format_size(stat.size)})")
          end)
        end

      {:error, {:exists, path}} ->
        IO.puts("\nError: Directory already exists: #{path}")
        IO.puts("Use FORCE=true to overwrite")

      {:error, %Tinkex.Error{status: 404} = error} ->
        IO.write("""

        Error: #{Tinkex.Error.format(error)}
        The checkpoint might no longer exist, or the service returned 404 for the latest entry.
        Try setting TINKER_CHECKPOINT_PATH explicitly to a known-good value or set FORCE=true if the
        directory already exists.
        """)

      {:error, error} ->
        IO.puts("\nError: #{inspect(error)}")
    end

    GenServer.stop(service_pid)
    IO.puts("\n=== Example Complete ===")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} GB"

  defp resolve_checkpoint_path(rest_client, service_pid) do
    env_path = System.get_env("TINKER_CHECKPOINT_PATH")

    cond do
      env_path ->
        ensure_downloadable(rest_client, env_path, :env)

      true ->
        case find_downloadable_checkpoint(rest_client) do
          {:ok, path} ->
            {:ok, path, :auto}

          {:error, :no_available_checkpoints} ->
            create_checkpoint_via_training(service_pid, rest_client)

          {:error, other} ->
            {:error, other}
        end
    end
  end

  defp ensure_downloadable(rest_client, path, source) do
    log("Validating archive availability for #{path} (source: #{source})")

    case wait_for_archive_url(rest_client, path) do
      {:ok, _} -> {:ok, path, source}
      {:error, %Error{} = error} -> {:error, {:archive_unavailable, source, error}}
      {:error, other} -> {:error, {:api_error, other}}
    end
  end

  defp find_downloadable_checkpoint(rest_client, offset \\ 0) do
    case RestClient.list_user_checkpoints(rest_client, limit: 10, offset: offset) do
      {:ok, %Tinkex.Types.CheckpointsListResponse{checkpoints: []}} ->
        if offset == 0, do: {:error, :no_checkpoints}, else: {:error, :no_available_checkpoints}

      {:ok, %Tinkex.Types.CheckpointsListResponse{checkpoints: checkpoints}} ->
        result =
          Enum.reduce_while(checkpoints, {:error, :no_available_checkpoints}, fn ckpt, _acc ->
            case wait_for_archive_url(rest_client, ckpt.tinker_path, 3, 2_000) do
              {:ok, _} ->
                {:halt, {:ok, ckpt.tinker_path}}

              {:error, %Error{status: status}} when status in [400, 403, 404] ->
                {:cont, {:error, :no_available_checkpoints}}

              {:error, other} ->
                {:halt, {:error, {:api_error, other}}}
            end
          end)

        case result do
          {:ok, path} ->
            {:ok, path}

          {:error, :no_available_checkpoints} ->
            find_downloadable_checkpoint(rest_client, offset + length(checkpoints))

          {:error, other} ->
            {:error, other}
        end

      {:error, error} ->
        {:error, {:api_error, error}}
    end
  end

  defp create_checkpoint_via_training(service_pid, rest_client) do
    base_model = System.get_env("TINKER_BASE_MODEL") || "meta-llama/Llama-3.1-8B"

    IO.puts("""
    No downloadable checkpoint found; creating one with a short training loop on #{base_model}...
    This may take ~10-20 seconds.
    """)

    with {:ok, training_pid} <-
           ServiceClient.create_lora_training_client(service_pid, base_model,
             lora_config: %LoraConfig{rank: 8}
           ) do
      log("Created training client for #{base_model}")

      try do
        with {:ok, datum} <- build_toy_datum(training_pid, base_model),
             :ok <- run_training_steps(training_pid, datum),
             {:ok, path} <- save_sampler_checkpoint(training_pid),
             {:ok, _} <- wait_for_archive_url(rest_client, path, 6, 2_000) do
          {:ok, path, :generated}
        else
          {:error, %Error{} = error} ->
            {:error, {:api_error, error}}

          {:error, other} ->
            {:error, {:api_error, other}}
        end
      after
        if Process.alive?(training_pid), do: GenServer.stop(training_pid)
      end
    end
  end

  defp build_toy_datum(training_pid, base_model) do
    with {:ok, model_input} <-
           ModelInput.from_text("checkpoint download smoke test",
             model_name: base_model,
             training_client: training_pid
           ) do
      tokens = first_chunk_tokens(model_input)
      weights = List.duplicate(1.0, length(tokens))

      datum =
        Datum.new(%{
          model_input: model_input,
          loss_fn_inputs: %{
            target_tokens: to_tensor(tokens, :int64),
            weights: to_tensor(weights, :float32)
          }
        })

      {:ok, datum}
    end
  end

  defp run_training_steps(training_pid, datum) do
    with {:ok, fb_task} <- TrainingClient.forward_backward(training_pid, [datum], :cross_entropy),
         {:ok, _fb_result} <- await_task(fb_task),
         {:ok, optim_task} <- TrainingClient.optim_step(training_pid, %AdamParams{}) do
      case await_task(optim_task) do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end
    end
  end

  defp save_sampler_checkpoint(training_pid) do
    with {:ok, save_task} <-
           TrainingClient.save_weights_for_sampler(training_pid, "checkpoint-download-example"),
         {:ok, response} <- await_task(save_task) do
      cond do
        is_map(response) and Map.has_key?(response, "path") ->
          {:ok, response["path"]}

        is_map(response) and Map.has_key?(response, :path) ->
          {:ok, response.path}

        true ->
          {:error,
           Error.new(:request_failed, "Unexpected save_weights_for_sampler response",
             data: response
           )}
      end
    end
  end

  defp wait_for_archive_url(rest_client, path, attempts \\ 3, delay_ms \\ 1_000)

  defp wait_for_archive_url(_rest_client, _path, 0, _delay_ms),
    do: {:error, Error.new(:api_status, "Archive URL unavailable after retries", status: 404)}

  defp wait_for_archive_url(rest_client, path, attempts, delay_ms) do
    log("Archive URL attempt #{attempts} for #{path}")

    case RestClient.get_checkpoint_archive_url(rest_client, path) do
      {:ok, url} ->
        log("Archive URL resolved for #{path}")
        {:ok, url}

      {:error, %Error{status: status}} when status in [400, 403, 404] ->
        log("Archive URL not ready (status #{status}); retrying after #{delay_ms}ms")
        Process.sleep(delay_ms)
        wait_for_archive_url(rest_client, path, attempts - 1, delay_ms)

      {:error, other} ->
        log("Archive URL error for #{path}: #{inspect(other)}")
        {:error, other}
    end
  end

  defp log(message) do
    case System.get_env("TINKEX_DEBUG") do
      flag when flag in ["1", "true", "TRUE", "yes", "YES"] ->
        IO.puts("[debug] #{message}")

      _ ->
        :ok
    end
  end

  defp first_chunk_tokens(%Tinkex.Types.ModelInput{chunks: [chunk | _]}) do
    Map.get(chunk, :tokens) || Map.get(chunk, "tokens") || []
  end

  defp first_chunk_tokens(_), do: []

  defp to_tensor(tokens, dtype) when is_list(tokens) do
    %TensorData{data: tokens, dtype: dtype, shape: [length(tokens)]}
  end

  defp to_tensor(_, dtype), do: %TensorData{data: [], dtype: dtype, shape: [0]}

  defp await_task(task) do
    try do
      Task.await(task, 60_000)
    catch
      :exit, reason -> {:error, reason}
    end
  end
end

Tinkex.Examples.CheckpointDownloadExample.run()
