defmodule Tinkex.CheckpointDownload do
  @moduledoc """
  Download and extract checkpoint archives with streaming support.

  Provides memory-efficient checkpoint downloads using `Finch.stream_while/5`.
  Downloads are streamed directly to disk with O(1) memory usage, making it
  safe to download large checkpoint files (100MB-GBs) without risk of OOM errors.

  ## Features

  - **Streaming downloads** - O(1) memory usage regardless of file size
  - **Progress callbacks** - Track download progress in real-time
  - **Automatic extraction** - Downloads and extracts tar archives in one operation
  - **Force overwrite** - Optional overwrite of existing checkpoint directories

  ## Examples

      # Basic download with automatic extraction
      {:ok, service_pid} = Tinkex.ServiceClient.start_link(config: config)
      {:ok, rest_client} = Tinkex.ServiceClient.create_rest_client(service_pid)

      {:ok, result} = Tinkex.CheckpointDownload.download(
        rest_client,
        "tinker://run-123/weights/0001",
        output_dir: "./models",
        force: true
      )

      IO.puts("Downloaded to: \#{result.destination}")

      # Download with progress tracking
      progress_fn = fn downloaded, total ->
        percent = if total > 0, do: Float.round(downloaded / total * 100, 1), else: 0
        IO.write("\\rProgress: \#{percent}% (\#{downloaded} / \#{total} bytes)")
      end

      {:ok, result} = Tinkex.CheckpointDownload.download(
        rest_client,
        "tinker://run-123/weights/0001",
        output_dir: "./models",
        progress: progress_fn
      )
  """

  require Logger

  alias Tinkex.RestClient

  @doc """
  Download and extract a checkpoint.

  ## Options
    * `:output_dir` - Parent directory for extraction (default: current directory)
    * `:force` - Overwrite existing directory (default: false)
    * `:progress` - Progress callback function `fn(downloaded, total) -> any`

  ## Returns
    * `{:ok, %{destination: path, checkpoint_path: path}}` on success
    * `{:error, {:exists, path}}` if target exists and force is false
    * `{:error, {:invalid_path, message}}` if checkpoint path is invalid
    * `{:error, reason}` for other failures
  """
  @spec download(RestClient.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def download(rest_client, checkpoint_path, opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, File.cwd!())
    force = Keyword.get(opts, :force, false)
    progress_fn = Keyword.get(opts, :progress)

    # Validate checkpoint path
    if String.starts_with?(checkpoint_path, "tinker://") do
      # Generate checkpoint ID from path
      checkpoint_id =
        checkpoint_path
        |> String.replace("tinker://", "")
        |> String.replace("/", "_")

      target_path = Path.join(output_dir, checkpoint_id)

      # Get HTTP pool from config
      http_pool = rest_client.config.http_pool

      # Check if target exists
      with :ok <- check_target(target_path, force),
           {:ok, url_response} <-
             RestClient.get_checkpoint_archive_url(rest_client, checkpoint_path),
           {:ok, archive_path} <- download_archive(url_response.url, http_pool, progress_fn),
           :ok <- extract_archive(archive_path, target_path) do
        # Clean up archive
        File.rm(archive_path)

        {:ok, %{destination: target_path, checkpoint_path: checkpoint_path}}
      end
    else
      {:error, {:invalid_path, "Checkpoint path must start with 'tinker://'"}}
    end
  end

  defp check_target(path, force) do
    if File.exists?(path) do
      if force do
        File.rm_rf!(path)
        :ok
      else
        {:error, {:exists, path}}
      end
    else
      :ok
    end
  end

  defp download_archive(url, http_pool, progress_fn) do
    # Create temp file for archive
    tmp_path = Path.join(System.tmp_dir!(), "tinkex_checkpoint_#{:rand.uniform(1_000_000)}.tar")

    case do_download(url, tmp_path, http_pool, progress_fn) do
      :ok -> {:ok, tmp_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_download(url, dest_path, http_pool, progress_fn) do
    # Build Finch request for streaming download.
    # Uses Finch.stream_while to stream response chunks directly to disk,
    # avoiding loading the entire file into memory. This is critical for
    # large checkpoints (100MB-GBs) that would cause OOM errors.
    request = Finch.build(:get, url, [])

    # Initialize accumulator for streaming
    initial_acc = %{
      file: nil,
      dest_path: dest_path,
      downloaded: 0,
      total: nil,
      progress_fn: progress_fn,
      status: nil
    }

    # Stream the response using stream_while for reducer-style accumulation
    result =
      Finch.stream_while(request, http_pool, initial_acc, fn
        {:status, status}, acc ->
          {:cont, %{acc | status: status}}

        {:headers, headers}, acc ->
          # Extract content-length from headers
          content_length =
            headers
            |> Enum.find(fn {k, _} -> String.downcase(k) == "content-length" end)
            |> case do
              {_, len} -> String.to_integer(len)
              nil -> nil
            end

          # Open file for writing (only if not already open)
          file =
            if acc.file == nil do
              File.open!(acc.dest_path, [:write, :binary])
            else
              acc.file
            end

          {:cont, %{acc | total: content_length, file: file}}

        {:data, chunk}, acc ->
          # Write chunk to file
          IO.binwrite(acc.file, chunk)

          downloaded = acc.downloaded + byte_size(chunk)

          # Report progress if callback provided
          if acc.progress_fn && acc.total do
            acc.progress_fn.(downloaded, acc.total)
          end

          {:cont, %{acc | downloaded: downloaded}}
      end)

    # Clean up: close file if it was opened
    # Note: Finch.stream returns the final accumulator value directly on success
    case result do
      {:ok, acc} ->
        maybe_close_file(acc)

        # Check status code
        case acc.status do
          200 -> :ok
          status when status != nil -> {:error, {:download_failed, status}}
          nil -> {:error, {:download_failed, :no_response}}
        end

      {:error, exception, acc} ->
        # Close partially written file if present in accumulator
        maybe_close_file(acc)
        {:error, {:download_failed, exception}}
    end
  end

  defp maybe_close_file(%{file: file}) when is_pid(file) do
    File.close(file)
  end

  defp maybe_close_file(_), do: :ok

  defp extract_archive(archive_path, target_path) do
    # Create target directory
    File.mkdir_p!(target_path)

    # Extract tar archive
    case :erl_tar.extract(String.to_charlist(archive_path), [
           {:cwd, String.to_charlist(target_path)}
         ]) do
      :ok ->
        :ok

      {:error, reason} ->
        # Clean up on failure
        File.rm_rf(target_path)
        {:error, {:extraction_failed, reason}}
    end
  end
end
