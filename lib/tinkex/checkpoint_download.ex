defmodule Tinkex.CheckpointDownload do
  @moduledoc """
  Download and extract checkpoint archives.

  Provides functionality to download checkpoints from Tinker storage
  and extract them to a local directory.

  ## Examples

      {:ok, service_pid} = Tinkex.ServiceClient.start_link(config: config)
      {:ok, rest_client} = Tinkex.ServiceClient.create_rest_client(service_pid)

      {:ok, result} = Tinkex.CheckpointDownload.download(
        rest_client,
        "tinker://run-123/weights/0001",
        output_dir: "./models",
        force: true
      )

      IO.puts("Downloaded to: \#{result.destination}")
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

      # Check if target exists
      with :ok <- check_target(target_path, force),
           {:ok, url_response} <-
             RestClient.get_checkpoint_archive_url(rest_client, checkpoint_path),
           {:ok, archive_path} <- download_archive(url_response.url, progress_fn),
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

  defp download_archive(url, progress_fn) do
    # Create temp file for archive
    tmp_path = Path.join(System.tmp_dir!(), "tinkex_checkpoint_#{:rand.uniform(1_000_000)}.tar")

    case do_download(url, tmp_path, progress_fn) do
      :ok -> {:ok, tmp_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_download(url, dest_path, progress_fn) do
    # Use :httpc for downloading
    :inets.start()
    :ssl.start()

    headers = []
    http_options = [timeout: 60_000, connect_timeout: 10_000]
    options = [body_format: :binary]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_options, options) do
      {:ok, {{_, 200, _}, resp_headers, body}} ->
        # Get content length from headers
        content_length =
          resp_headers
          |> Enum.find(fn {k, _} -> String.downcase(to_string(k)) == "content-length" end)
          |> case do
            {_, len} -> String.to_integer(to_string(len))
            nil -> byte_size(body)
          end

        # Report progress if callback provided
        if progress_fn do
          progress_fn.(byte_size(body), content_length)
        end

        # Write to file
        File.write!(dest_path, body)
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:download_failed, status}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

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
