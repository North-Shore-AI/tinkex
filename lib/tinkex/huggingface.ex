defmodule Tinkex.HuggingFace do
  @moduledoc false

  alias Tinkex.Error

  @base_url "https://huggingface.co"

  @spec resolve_file(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def resolve_file(repo_id, revision, filename, opts \\ [])
      when is_binary(repo_id) and is_binary(revision) and is_binary(filename) and is_list(opts) do
    cache_root = Keyword.get(opts, :cache_dir, default_cache_dir())
    path = Path.join([cache_root, "hf", sanitize_repo_id(repo_id), revision, filename])

    if File.exists?(path) do
      {:ok, path}
    else
      with :ok <- File.mkdir_p(Path.dirname(path)),
           {:ok, body} <- fetch_file(repo_id, revision, filename, opts),
           :ok <- File.write(path, body) do
        {:ok, path}
      else
        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error,
           Error.new(:validation, "Failed to download #{repo_id}@#{revision}/#{filename}",
             data: %{reason: inspect(reason)}
           )}
      end
    end
  end

  @spec fetch_file(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t()}
  defp fetch_file(repo_id, revision, filename, opts) do
    url = "#{@base_url}/#{repo_id}/resolve/#{revision}/#{filename}"
    timeout_ms = Keyword.get(opts, :http_timeout_ms, 120_000)

    headers = [{~c"user-agent", ~c"tinkex"}]

    with :ok <- ensure_httpc_started() do
      http_options = [
        timeout: timeout_ms,
        connect_timeout: timeout_ms,
        autoredirect: true,
        ssl: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      ]

      options = [body_format: :binary, full_result: true]

      case :httpc.request(:get, {String.to_charlist(url), headers}, http_options, options) do
        {:ok, {{_, status, _}, _resp_headers, body}}
        when is_integer(status) and status >= 200 and status < 300 ->
          {:ok, body}

        {:ok, {{_, 404, _}, _resp_headers, _body}} ->
          {:error,
           Error.new(
             :validation,
             "File not found on HuggingFace: #{repo_id}@#{revision}/#{filename}"
           )}

        {:ok, {{_, status, _}, _resp_headers, body}} ->
          {:error,
           Error.new(
             :validation,
             "HuggingFace download failed (#{status}) for #{repo_id}@#{revision}/#{filename}",
             data: %{body: body}
           )}

        {:error, reason} ->
          {:error,
           Error.new(
             :api_connection,
             "HuggingFace request failed for #{repo_id}@#{revision}/#{filename}",
             data: %{reason: inspect(reason)}
           )}
      end
    end
  end

  defp ensure_httpc_started do
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      :ok
    else
      {:error, reason} ->
        {:error,
         Error.new(:request_failed, "Failed to start :httpc dependencies",
           data: %{reason: inspect(reason)}
         )}
    end
  end

  defp default_cache_dir do
    :filename.basedir(:user_cache, "tinkex")
  end

  defp sanitize_repo_id(repo_id) do
    repo_id
    |> String.replace("/", "__")
    |> String.replace("..", "_")
  end
end
