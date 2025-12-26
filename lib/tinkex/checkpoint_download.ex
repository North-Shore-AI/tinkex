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

  alias Tinkex.PoolKey
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
    request = Finch.build(:get, url, [])
    pool_name = PoolKey.resolve_pool_name(http_pool, url, :futures)
    initial_acc = build_initial_download_acc(dest_path, progress_fn)

    case Finch.stream_while(request, pool_name, initial_acc, &handle_stream_event/2) do
      {:ok, acc} ->
        finalize_download(acc)

      {:error, exception, acc} ->
        maybe_close_file(acc)
        {:error, {:download_failed, exception}}
    end
  end

  defp build_initial_download_acc(dest_path, progress_fn) do
    %{
      file: nil,
      dest_path: dest_path,
      downloaded: 0,
      total: nil,
      progress_fn: progress_fn,
      status: nil
    }
  end

  defp handle_stream_event({:status, status}, acc) do
    {:cont, %{acc | status: status}}
  end

  defp handle_stream_event({:headers, headers}, acc) do
    content_length = extract_content_length(headers)
    file = ensure_file_open(acc)
    {:cont, %{acc | total: content_length, file: file}}
  end

  defp handle_stream_event({:data, chunk}, acc) do
    IO.binwrite(acc.file, chunk)
    downloaded = acc.downloaded + byte_size(chunk)
    report_progress(acc.progress_fn, downloaded, acc.total)
    {:cont, %{acc | downloaded: downloaded}}
  end

  defp extract_content_length(headers) do
    headers
    |> Enum.find(fn {k, _} -> String.downcase(k) == "content-length" end)
    |> case do
      {_, len} -> String.to_integer(len)
      nil -> nil
    end
  end

  defp ensure_file_open(%{file: nil, dest_path: dest_path}) do
    File.open!(dest_path, [:write, :binary])
  end

  defp ensure_file_open(%{file: file}), do: file

  defp report_progress(nil, _downloaded, _total), do: :ok
  defp report_progress(_progress_fn, _downloaded, nil), do: :ok
  defp report_progress(progress_fn, downloaded, total), do: progress_fn.(downloaded, total)

  defp finalize_download(acc) do
    maybe_close_file(acc)

    case acc.status do
      200 -> :ok
      status when status != nil -> {:error, {:download_failed, status}}
      nil -> {:error, {:download_failed, :no_response}}
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
