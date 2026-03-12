defmodule Tinkex.HuggingFace do
  @moduledoc false

  alias Tinkex.{Env, Error}
  alias Tinkex.Types.{ParsedCheckpointTinkerPath, WeightsInfoResponse}

  @base_url "https://huggingface.co"
  @json_content_type "application/json"
  @ndjson_content_type "application/x-ndjson"
  @raw_content_type "application/octet-stream"
  @lfs_content_type "application/vnd.git-lfs+json"

  @type request_result ::
          {:ok, %{status: pos_integer(), headers: [{String.t(), String.t()}], body: binary()}}
          | {:error, Error.t()}

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

  @spec resolve_token(keyword() | map()) :: {:ok, String.t()} | {:error, Error.t()}
  def resolve_token(opts \\ []) do
    opts = normalize_opts(opts)
    env = Keyword.get(opts, :env, :system)
    env_module = Keyword.get(opts, :env_module, Env)

    token =
      first_present([
        Keyword.get(opts, :hf_token),
        Keyword.get(opts, :token),
        env_module.hf_token(env),
        read_token_file(Keyword.get(opts, :token_path, env_module.hf_token_path(env)))
      ])

    case token do
      nil ->
        {:error,
         Error.new(
           :validation,
           "Hugging Face token not found",
           category: :user,
           data: %{
             checked: [
               "--hf-token",
               "HF_TOKEN",
               "HUGGING_FACE_HUB_TOKEN",
               Keyword.get(opts, :token_path, env_module.hf_token_path(env))
             ]
           }
         )}

      value ->
        {:ok, value}
    end
  end

  @spec push_checkpoint_adapter(term(), String.t(), keyword() | map()) ::
          {:ok, %{repo_id: String.t(), revision: String.t(), public: boolean()}}
          | {:error, Error.t()}
  def push_checkpoint_adapter(rest_client, checkpoint_path, opts \\ []) do
    opts = normalize_opts(opts)
    rest_client_module = Keyword.get(opts, :rest_client_module, Tinkex.RestClient)

    with {:ok, parsed} <- ParsedCheckpointTinkerPath.from_tinker_path(checkpoint_path),
         {:ok, token} <- resolve_token(opts),
         {:ok, whoami_payload} <- whoami(token, opts),
         {:ok, archive_response} <-
           rest_client_module.get_checkpoint_archive_url_by_tinker_path(
             rest_client,
             checkpoint_path
           ),
         {:ok, weights_info} <-
           get_weights_info(rest_client_module, rest_client, checkpoint_path) do
      push_downloaded_checkpoint_adapter(
        parsed,
        checkpoint_path,
        archive_response.url,
        weights_info,
        whoami_payload,
        token,
        opts
      )
    end
  rescue
    e in ArgumentError ->
      {:error, Error.new(:validation, Exception.message(e), category: :user)}
  end

  defp push_downloaded_checkpoint_adapter(
         parsed,
         checkpoint_path,
         archive_url,
         weights_info,
         whoami_payload,
         token,
         opts
       ) do
    with_temp_dir(fn tmp_dir ->
      archive_path = Path.join(tmp_dir, "checkpoint.tar")
      extract_dir = Path.join(tmp_dir, "extract")

      with :ok <- prepare_checkpoint_extract_dir(extract_dir, archive_url, archive_path, opts) do
        upload_adapter_dir(
          extract_dir,
          checkpoint_path,
          parsed,
          weights_info,
          whoami_payload,
          token,
          opts
        )
      end
    end)
  end

  defp prepare_checkpoint_extract_dir(extract_dir, archive_url, archive_path, opts) do
    with :ok <- File.mkdir_p(extract_dir),
         :ok <- download_file(archive_url, archive_path, opts) do
      safe_extract_tar(archive_path, extract_dir)
    end
  end

  @spec fetch_file(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t()}
  defp fetch_file(repo_id, revision, filename, opts) do
    url = "#{endpoint(opts)}/#{repo_id}/resolve/#{revision}/#{filename}"

    case request(:get, url, [], nil, opts) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error,
         Error.new(
           :validation,
           "File not found on HuggingFace: #{repo_id}@#{revision}/#{filename}"
         )}

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(
           :validation,
           "HuggingFace download failed (#{status}) for #{repo_id}@#{revision}/#{filename}",
           data: %{body: truncate_body(body)}
         )}

      {:error, _} = error ->
        error
    end
  end

  defp upload_adapter_dir(
         extract_dir,
         checkpoint_path,
         parsed,
         weights_info,
         whoami_payload,
         token,
         opts
       ) do
    add_model_card? = Keyword.get(opts, :add_model_card, true)
    requested_repo_id = Keyword.get(opts, :repo_id)
    requested_revision = Keyword.get(opts, :revision)
    public? = Keyword.get(opts, :public, false)

    with :ok <- validate_adapter_contents(extract_dir),
         :ok <- patch_adapter_config(extract_dir, weights_info.base_model),
         {:ok, repo_id_input, revision} <-
           derive_destination(
             parsed,
             weights_info.base_model,
             requested_repo_id,
             requested_revision
           ),
         :ok <-
           maybe_write_model_card(
             extract_dir,
             checkpoint_path,
             repo_id_input,
             weights_info,
             add_model_card?
           ),
         {:ok, full_repo_id} <- create_repo(repo_id_input, token, whoami_payload, public?, opts),
         :ok <- ensure_readme_matches(full_repo_id, checkpoint_path, revision, token, opts),
         {:ok, files} <- collect_upload_files(extract_dir, opts),
         {:ok, preupload_infos} <- preupload_files(full_repo_id, revision, files, token, opts),
         :ok <- upload_lfs_files(full_repo_id, revision, preupload_infos, token, opts),
         :ok <-
           create_commit(full_repo_id, revision, checkpoint_path, preupload_infos, token, opts) do
      {:ok, %{repo_id: full_repo_id, revision: revision, public: public?}}
    end
  end

  defp get_weights_info(rest_client_module, rest_client, checkpoint_path) do
    case rest_client_module.get_weights_info_by_tinker_path(rest_client, checkpoint_path) do
      {:ok, %WeightsInfoResponse{} = info} ->
        {:ok, info}

      {:ok, data} when is_map(data) ->
        {:ok, WeightsInfoResponse.from_json(data)}

      {:error, _} = error ->
        error
    end
  end

  defp whoami(token, opts) do
    case request(:get, "#{endpoint(opts)}/api/whoami-v2", auth_headers(token), nil, opts) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        Jason.decode(body)
        |> case do
          {:ok, payload} when is_map(payload) ->
            {:ok, payload}

          _ ->
            {:error, Error.new(:request_failed, "Invalid Hugging Face whoami response")}
        end

      {:ok, %{status: 401}} ->
        {:error, Error.new(:validation, "Invalid Hugging Face token", category: :user)}

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(:request_failed, "Hugging Face whoami failed (#{status})",
           data: %{body: truncate_body(body)}
         )}

      {:error, _} = error ->
        error
    end
  end

  defp create_repo(repo_id, token, whoami_payload, public?, opts) do
    {organization, name} =
      case String.split(repo_id, "/", parts: 2) do
        [single] -> {nil, single}
        [org, repo_name] -> {org, repo_name}
      end

    payload =
      %{"name" => name, "organization" => organization, "private" => !public?}
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case json_request(
           :post,
           "#{endpoint(opts)}/api/repos/create",
           auth_headers(token),
           payload,
           opts
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, %{"url" => url}} -> {:ok, repo_id_from_url(url)}
          _ -> {:ok, normalize_repo_id(repo_id, whoami_payload)}
        end

      {:ok, %{status: 409}} ->
        {:ok, normalize_repo_id(repo_id, whoami_payload)}

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(:request_failed, "Failed to create Hugging Face repo (#{status})",
           data: %{body: truncate_body(body)}
         )}

      {:error, _} = error ->
        error
    end
  end

  defp ensure_readme_matches(full_repo_id, checkpoint_path, revision, token, opts) do
    case fetch_remote_readme_tinker_path(full_repo_id, revision, token, opts) do
      {:ok, nil} ->
        :ok

      {:ok, ^checkpoint_path} ->
        :ok

      {:ok, other_path} ->
        {:error,
         Error.new(
           :validation,
           "Repo ID appears to contain a different Tinker checkpoint",
           category: :user,
           data: %{found: other_path, expected: checkpoint_path}
         )}

      {:error, %Error{status: 404}} ->
        :ok

      {:error, _} = error ->
        error
    end
  end

  defp fetch_remote_readme_tinker_path(full_repo_id, revision, token, opts) do
    url = "#{endpoint(opts)}/#{full_repo_id}/resolve/#{revision}/README.md"

    case request(:get, url, auth_headers(token), nil, opts) do
      {:ok, %{status: status, body: body}} when status >= 200 and status < 300 ->
        {:ok, extract_tinker_path(body)}

      {:ok, %{status: 404}} ->
        {:error, Error.new(:api_status, "README.md not found", status: 404)}

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(:request_failed, "Failed to fetch remote README (#{status})",
           data: %{body: truncate_body(body)}
         )}

      {:error, _} = error ->
        error
    end
  end

  defp collect_upload_files(extract_dir, opts) do
    allow_patterns = Keyword.get(opts, :allow_patterns)

    ignore_patterns =
      opts
      |> Keyword.get(:ignore_patterns, [])
      |> List.wrap()
      |> then(fn patterns ->
        if is_nil(allow_patterns) and "checkpoint_complete" not in patterns do
          patterns ++ ["checkpoint_complete"]
        else
          patterns
        end
      end)

    files =
      extract_dir
      |> list_regular_files()
      |> Enum.filter(&matches_allow_patterns?(&1, extract_dir, allow_patterns))
      |> Enum.reject(&matches_ignore_patterns?(&1, extract_dir, ignore_patterns))
      |> Enum.map(fn path -> build_upload_file(path, extract_dir) end)

    case files do
      [] ->
        {:error,
         Error.new(:validation, "No files matched the selected upload patterns", category: :user)}

      list ->
        {:ok, list}
    end
  end

  defp preupload_files(full_repo_id, revision, files, token, opts) do
    payload = %{
      "files" =>
        Enum.map(files, fn file ->
          %{
            "path" => file.path_in_repo,
            "sample" => Base.encode64(file.sample),
            "size" => file.size
          }
        end)
    }

    url = "#{endpoint(opts)}/api/models/#{full_repo_id}/preupload/#{revision}"

    case json_request(:post, maybe_create_pr(url, opts), auth_headers(token), payload, opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        decode_preupload_response(files, body)

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(:request_failed, "Hugging Face preupload failed (#{status})",
           data: %{body: truncate_body(body)}
         )}

      {:error, _} = error ->
        error
    end
  end

  defp upload_lfs_files(_full_repo_id, _revision, files, _token, _opts)
       when files == [] or is_nil(files) do
    :ok
  end

  defp upload_lfs_files(full_repo_id, revision, files, token, opts) do
    lfs_files =
      Enum.filter(files, fn file ->
        file.upload_mode == "lfs" and not file.should_ignore
      end)

    case lfs_files do
      [] ->
        :ok

      list ->
        payload = %{
          "operation" => "upload",
          "transfers" => ["basic", "multipart"],
          "objects" => Enum.map(list, &%{"oid" => &1.sha256, "size" => &1.size}),
          "hash_algo" => "sha256",
          "ref" => %{"name" => revision}
        }

        url = "#{endpoint(opts)}/#{full_repo_id}.git/info/lfs/objects/batch"

        case json_request(
               :post,
               url,
               lfs_headers(token),
               payload,
               opts,
               content_type: @lfs_content_type
             ) do
          {:ok, %{status: status, body: body}} when status in 200..299 ->
            handle_lfs_batch_response(list, body, token, opts)

          {:ok, %{status: status, body: body}} ->
            {:error,
             Error.new(:request_failed, "Hugging Face LFS batch failed (#{status})",
               data: %{body: truncate_body(body)}
             )}

          {:error, _} = error ->
            error
        end
    end
  end

  defp decode_preupload_response(files, body) do
    case Jason.decode(body) do
      {:ok, %{"files" => preupload_files}} ->
        infos_by_path =
          Map.new(preupload_files, fn info ->
            {info["path"],
             %{
               upload_mode: info["uploadMode"] || "regular",
               should_ignore: info["shouldIgnore"] || false
             }}
          end)

        {:ok,
         Enum.map(files, fn file ->
           info = Map.get(infos_by_path, file.path_in_repo, %{})

           Map.merge(file, %{
             upload_mode: Map.get(info, :upload_mode, "regular"),
             should_ignore: Map.get(info, :should_ignore, false)
           })
         end)}

      _ ->
        {:error, Error.new(:request_failed, "Invalid preupload response")}
    end
  end

  defp handle_lfs_batch_response(files, body, token, opts) do
    case Jason.decode(body) do
      {:ok, %{"objects" => objects}} ->
        files_by_oid = Map.new(files, &{&1.sha256, &1})

        Enum.reduce_while(
          objects,
          :ok,
          &upload_lfs_object(&1, files_by_oid, token, opts, &2)
        )

      _ ->
        {:error, Error.new(:request_failed, "Invalid LFS batch response")}
    end
  end

  defp upload_lfs_object(object, files_by_oid, token, opts, _acc) do
    case Map.fetch(files_by_oid, object["oid"]) do
      :error ->
        {:halt, {:error, Error.new(:request_failed, "Unknown LFS object in batch response")}}

      {:ok, file} ->
        actions = object["actions"] || %{}

        result =
          cond do
            is_nil(actions["upload"]) ->
              :ok

            is_map(actions["upload"]["header"]) and actions["upload"]["header"]["chunk_size"] ->
              upload_lfs_multipart(file, actions["upload"], opts)

            true ->
              upload_lfs_single(file, actions["upload"], opts)
          end

        with :ok <- result,
             :ok <- verify_lfs_upload(file, actions["verify"], token, opts) do
          {:cont, :ok}
        else
          {:error, _} = error -> {:halt, error}
        end
    end
  end

  defp upload_lfs_single(file, %{"href" => href}, opts) do
    case raw_request(:put, href, [], File.read!(file.local_path), opts) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> lfs_upload_error(status, body)
      {:error, _} = error -> error
    end
  end

  defp upload_lfs_multipart(file, %{"href" => href, "header" => header}, opts) do
    with {:ok, part_urls, chunk_size} <- multipart_part_urls(header, file.size),
         {:ok, etags} <- upload_lfs_parts(file.local_path, part_urls, chunk_size, opts),
         payload <- %{"oid" => file.sha256, "parts" => build_completion_parts(etags)},
         {:ok, %{status: status, body: body}} <-
           json_request(
             :post,
             href,
             [{"content-type", @lfs_content_type}, {"accept", @lfs_content_type}],
             payload,
             opts,
             content_type: @lfs_content_type
           ) do
      if status in 200..299 do
        :ok
      else
        lfs_upload_error(status, body)
      end
    end
  end

  defp verify_lfs_upload(_file, nil, _token, _opts), do: :ok

  defp verify_lfs_upload(file, %{"href" => href}, token, opts) do
    payload = %{"oid" => file.sha256, "size" => file.size}

    case json_request(:post, href, auth_headers(token), payload, opts) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> lfs_upload_error(status, body)
      {:error, _} = error -> error
    end
  end

  defp create_commit(full_repo_id, revision, checkpoint_path, files, token, opts) do
    commit_message = Keyword.get(opts, :commit_message, "Upload adapter from #{checkpoint_path}")

    lines =
      [
        Jason.encode!(%{
          "key" => "header",
          "value" => %{"summary" => commit_message, "description" => ""}
        })
      ] ++
        Enum.flat_map(files, fn file ->
          if file.should_ignore do
            []
          else
            [Jason.encode!(commit_line(file))]
          end
        end)

    url = maybe_create_pr("#{endpoint(opts)}/api/models/#{full_repo_id}/commit/#{revision}", opts)

    case request(
           :post,
           url,
           auth_headers(token) ++ [{"content-type", @ndjson_content_type}],
           Enum.join(lines, "\n") <> "\n",
           opts,
           content_type: @ndjson_content_type
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(:request_failed, "Hugging Face commit failed (#{status})",
           data: %{body: truncate_body(body)}
         )}

      {:error, _} = error ->
        error
    end
  end

  defp commit_line(file) do
    if file.upload_mode == "lfs" do
      %{
        "key" => "lfsFile",
        "value" => %{
          "path" => file.path_in_repo,
          "algo" => "sha256",
          "oid" => file.sha256,
          "size" => file.size
        }
      }
    else
      %{
        "key" => "file",
        "value" => %{
          "content" => file.local_path |> File.read!() |> Base.encode64(),
          "path" => file.path_in_repo,
          "encoding" => "base64"
        }
      }
    end
  end

  defp validate_adapter_contents(extract_dir) do
    adapter_config = Path.join(extract_dir, "adapter_config.json")
    adapter_safetensors = Path.join(extract_dir, "adapter_model.safetensors")
    adapter_bin = Path.join(extract_dir, "adapter_model.bin")
    checkpoint_complete = Path.join(extract_dir, "checkpoint_complete")

    cond do
      not File.exists?(adapter_config) ->
        {:error,
         Error.new(:validation, "Checkpoint archive does not contain adapter_config.json",
           category: :user
         )}

      not (File.exists?(adapter_safetensors) or File.exists?(adapter_bin)) ->
        {:error,
         Error.new(
           :validation,
           "Checkpoint archive does not contain adapter_model.safetensors or adapter_model.bin",
           category: :user
         )}

      not File.exists?(checkpoint_complete) ->
        {:error,
         Error.new(:validation, "Checkpoint archive is missing checkpoint_complete",
           category: :user
         )}

      true ->
        :ok
    end
  end

  defp patch_adapter_config(extract_dir, base_model) do
    path = Path.join(extract_dir, "adapter_config.json")

    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      payload =
        if is_binary(payload["base_model_name_or_path"]) do
          payload
        else
          Map.put(payload, "base_model_name_or_path", base_model || "unknown")
        end

      File.write(path, Jason.encode!(payload, pretty: true) <> "\n")
    else
      {:error, reason} ->
        {:error,
         Error.new(:request_failed, "Failed to update adapter_config.json",
           data: %{reason: inspect(reason)}
         )}
    end
  end

  defp derive_destination(parsed, base_model, nil, nil) do
    base_short =
      base_model
      |> case do
        nil -> "adapter"
        model -> model |> String.split("/") |> List.last()
      end
      |> sanitize_repo_name()

    {:ok, sanitize_repo_name("tinker-#{base_short}-#{parsed.training_run_id}"),
     sanitize_repo_name(parsed.checkpoint_id)}
  end

  defp derive_destination(_parsed, _base_model, repo_id, nil) when is_binary(repo_id) do
    {:ok, repo_id, "main"}
  end

  defp derive_destination(_parsed, _base_model, repo_id, revision)
       when is_binary(repo_id) and is_binary(revision) do
    {:ok, repo_id, revision}
  end

  defp maybe_write_model_card(_extract_dir, _checkpoint_path, _repo_id, _weights_info, false),
    do: :ok

  defp maybe_write_model_card(extract_dir, checkpoint_path, repo_id, weights_info, true) do
    readme_path = Path.join(extract_dir, "README.md")

    if File.exists?(readme_path) do
      :ok
    else
      base_model = weights_info.base_model || "unknown"

      lines =
        ([
           "---",
           "base_model: #{base_model}",
           "library_name: peft",
           "tags:",
           "- tinker",
           "- peft",
           "- lora"
         ] ++
           if(base_model == "unknown", do: [], else: ["- base_model:adapter:#{base_model}"]) ++
           [
             "tinker_path: #{checkpoint_path}",
             "---",
             "",
             "# Tinker LoRA Adapter",
             "",
             "This repository contains a LoRA adapter exported from Tinkex.",
             "",
             "## Usage",
             "",
             "```python",
             "from transformers import AutoModelForCausalLM",
             "",
             "adapter_id = \"#{repo_id}\"",
             "base_model = \"#{base_model}\"",
             "",
             "model = AutoModelForCausalLM.from_pretrained(adapter_id, device_map=\"auto\")",
             "```",
             "",
             "## Source",
             "",
             "```",
             checkpoint_path,
             "```",
             "",
             "## Details",
             "",
             "- Base model: #{base_model}"
           ])
        |> maybe_append_detail("- LoRA rank: #{weights_info.lora_rank}", weights_info.lora_rank)
        |> maybe_append_training_details(weights_info)

      File.write(readme_path, Enum.join(lines ++ [""], "\n"))
    end
  end

  defp maybe_append_training_details(lines, weights_info) do
    if Enum.any?(
         [weights_info.train_attn, weights_info.train_mlp, weights_info.train_unembed],
         &(!is_nil(&1))
       ) do
      lines ++
        [
          "- Trained modules: attn=#{weights_info.train_attn}, mlp=#{weights_info.train_mlp}, unembed=#{weights_info.train_unembed}"
        ]
    else
      lines
    end
  end

  defp maybe_append_detail(lines, _detail, nil), do: lines
  defp maybe_append_detail(lines, detail, _value), do: lines ++ [detail]

  defp build_upload_file(path, root) do
    %{
      local_path: path,
      path_in_repo: Path.relative_to(path, root),
      size: File.stat!(path).size,
      sample: read_sample(path),
      sha256: sha256_file(path)
    }
  end

  defp read_sample(path) do
    {:ok, file} = File.open(path, [:read, :binary])

    try do
      case IO.binread(file, 512) do
        data when is_binary(data) -> data
        :eof -> <<>>
        {:error, reason} -> raise File.Error, reason: reason, action: "read", path: path
      end
    after
      File.close(file)
    end
  end

  defp sha256_file(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp list_regular_files(root) do
    root
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  defp matches_allow_patterns?(_path, _root, nil), do: true

  defp matches_allow_patterns?(path, root, patterns),
    do: path_matches_patterns?(path, root, patterns)

  defp matches_ignore_patterns?(_path, _root, []), do: false

  defp matches_ignore_patterns?(path, root, patterns),
    do: path_matches_patterns?(path, root, patterns)

  defp path_matches_patterns?(path, root, patterns) do
    relative = Path.relative_to(path, root)
    basename = Path.basename(path)

    Enum.any?(List.wrap(patterns), fn pattern ->
      path_match?(relative, pattern) or path_match?(basename, pattern)
    end)
  end

  defp path_match?(value, pattern) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> then(&("^" <> &1 <> "$"))
      |> Regex.compile!()

    Regex.match?(regex, value)
  end

  defp download_file(url, destination, opts) do
    case request(:get, url, [], nil, opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        File.write(destination, body)

      {:ok, %{status: status, body: body}} ->
        {:error,
         Error.new(:request_failed, "Failed to download checkpoint archive (#{status})",
           data: %{body: truncate_body(body)}
         )}

      {:error, _} = error ->
        error
    end
  end

  defp safe_extract_tar(archive_path, extract_dir) do
    with {:ok, entries, tar_opts} <- tar_entries(archive_path),
         :ok <- validate_tar_entries(entries) do
      extract_tar(archive_path, extract_dir, tar_opts)
    end
  end

  defp tar_entries(archive_path) do
    case :erl_tar.table(String.to_charlist(archive_path)) do
      {:ok, entries} ->
        {:ok, entries, []}

      {:error, _reason} ->
        case :erl_tar.table(String.to_charlist(archive_path), [:compressed]) do
          {:ok, entries} ->
            {:ok, entries, [:compressed]}

          {:error, reason} ->
            {:error,
             Error.new(:request_failed, "Failed to inspect tar archive",
               data: %{reason: inspect(reason)}
             )}
        end
    end
  end

  defp validate_tar_entries(entries) do
    entries
    |> Enum.map(&to_string/1)
    |> Enum.reduce_while(:ok, fn entry, _acc ->
      segments = Path.split(entry)

      cond do
        Path.type(entry) == :absolute ->
          {:halt,
           {:error, Error.new(:validation, "Unsafe path in checkpoint archive", category: :user)}}

        Enum.any?(segments, &(&1 == "..")) ->
          {:halt,
           {:error, Error.new(:validation, "Unsafe path in checkpoint archive", category: :user)}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp extract_tar(archive_path, extract_dir, tar_opts) do
    case :erl_tar.extract(String.to_charlist(archive_path), [
           {:cwd, String.to_charlist(extract_dir)} | tar_opts
         ]) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         Error.new(:request_failed, "Failed to extract tar archive",
           data: %{reason: inspect(reason)}
         )}
    end
  end

  defp multipart_part_urls(header, size) do
    with {chunk_size, ""} <- Integer.parse(to_string(header["chunk_size"] || "")),
         true <- chunk_size > 0 do
      part_urls =
        header
        |> Enum.filter(fn {key, _value} -> key != "chunk_size" and key =~ ~r/^\d+$/ end)
        |> Enum.sort_by(fn {key, _value} -> String.to_integer(key) end)
        |> Enum.map(fn {_key, value} -> value end)

      expected_parts = ceil(size / chunk_size)

      if length(part_urls) == expected_parts do
        {:ok, part_urls, chunk_size}
      else
        {:error, Error.new(:request_failed, "Invalid multipart upload instructions")}
      end
    else
      _ -> {:error, Error.new(:request_failed, "Invalid multipart upload instructions")}
    end
  end

  defp upload_lfs_parts(path, part_urls, chunk_size, opts) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :binary])

    try do
      part_urls
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {part_url, index}, {:ok, acc} ->
        offset = index * chunk_size

        case :file.pread(file, offset, chunk_size) do
          {:ok, chunk} ->
            case raw_request(:put, part_url, [], chunk, opts) do
              {:ok, %{status: status, headers: headers}} when status in 200..299 ->
                etag =
                  headers
                  |> Enum.find_value(fn
                    {"etag", value} -> value
                    _ -> nil
                  end)

                if is_binary(etag) do
                  {:cont, {:ok, acc ++ [etag]}}
                else
                  {:halt,
                   {:error, Error.new(:request_failed, "Missing ETag for multipart upload")}}
                end

              {:ok, %{status: status, body: body}} ->
                {:halt, lfs_upload_error(status, body)}

              {:error, _} = error ->
                {:halt, error}
            end

          :eof ->
            {:halt, {:ok, acc}}

          {:error, reason} ->
            {:halt,
             {:error,
              Error.new(:request_failed, "Failed to read file for multipart upload",
                data: %{reason: inspect(reason)}
              )}}
        end
      end)
    after
      :file.close(file)
    end
  end

  defp build_completion_parts(etags) do
    etags
    |> Enum.with_index(1)
    |> Enum.map(fn {etag, index} -> %{"partNumber" => index, "etag" => etag} end)
  end

  defp lfs_upload_error(status, body) do
    {:error,
     Error.new(:request_failed, "Hugging Face LFS upload failed (#{status})",
       data: %{body: truncate_body(body)}
     )}
  end

  defp request(method, url, headers, body, opts, extra \\ []) do
    with :ok <- ensure_httpc_started() do
      timeout_ms = Keyword.get(opts, :http_timeout_ms, 120_000)

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

      request =
        build_httpc_request(
          method,
          url,
          headers,
          body,
          Keyword.get(extra, :content_type, @raw_content_type)
        )

      case :httpc.request(method, request, http_options, options) do
        {:ok, {{_, status, _}, response_headers, response_body}} ->
          {:ok,
           %{
             status: status,
             headers: normalize_headers(response_headers),
             body: response_body || ""
           }}

        {:error, reason} ->
          {:error,
           Error.new(
             :api_connection,
             "Hugging Face request failed",
             data: %{reason: inspect(reason), url: url}
           )}
      end
    end
  end

  defp json_request(method, url, headers, payload, opts, extra \\ []) do
    request(
      method,
      url,
      headers,
      Jason.encode!(payload),
      opts,
      Keyword.put(extra, :content_type, Keyword.get(extra, :content_type, @json_content_type))
    )
  end

  defp raw_request(method, url, headers, body, opts) do
    request(method, url, headers, body, opts, content_type: @raw_content_type)
  end

  defp build_httpc_request(:get, url, headers, _body, _content_type) do
    {String.to_charlist(url), to_httpc_headers(headers)}
  end

  defp build_httpc_request(method, url, headers, body, content_type)
       when method in [:post, :put] do
    {String.to_charlist(url), to_httpc_headers(headers), String.to_charlist(content_type), body}
  end

  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp lfs_headers(token) do
    auth_headers(token) ++
      [
        {"accept", @lfs_content_type},
        {"content-type", @lfs_content_type}
      ]
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase(), to_string(value)}
    end)
  end

  defp to_httpc_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {String.to_charlist(name), String.to_charlist(value)}
    end)
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

  defp maybe_create_pr(url, opts) do
    if Keyword.get(opts, :create_pr, false) do
      separator = if String.contains?(url, "?"), do: "&", else: "?"
      url <> "#{separator}create_pr=1"
    else
      url
    end
  end

  defp normalize_repo_id(repo_id, whoami_payload) do
    if String.contains?(repo_id, "/") do
      repo_id
    else
      "#{whoami_name(whoami_payload)}/#{repo_id}"
    end
  end

  defp repo_id_from_url(url) do
    uri = URI.parse(url)
    uri.path |> String.trim_leading("/") |> String.trim_trailing("/")
  end

  defp whoami_name(payload) do
    payload["name"] || get_in(payload, ["user", "name"]) ||
      raise ArgumentError, "Unable to determine Hugging Face username from whoami response"
  end

  defp extract_tinker_path(body) do
    case Regex.run(~r/tinker:\/\/[^\s`]+/, body) do
      [path] -> path
      _ -> nil
    end
  end

  defp with_temp_dir(fun) do
    tmp_dir = Path.join(System.tmp_dir!(), "tinkex_hf_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    try do
      fun.(tmp_dir)
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp normalize_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_opts(opts) when is_list(opts), do: opts

  defp first_present(values) do
    Enum.find_value(values, fn
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end)
  end

  defp read_token_file(nil), do: nil

  defp read_token_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, token} ->
        token
        |> String.trim()
        |> case do
          "" -> nil
          value -> value
        end

      {:error, _reason} ->
        nil
    end
  end

  defp endpoint(opts), do: Keyword.get(opts, :endpoint, @base_url)

  defp truncate_body(body) when is_binary(body) and byte_size(body) > 500,
    do: binary_part(body, 0, 500)

  defp truncate_body(body), do: body

  defp sanitize_repo_name(value) do
    value
    |> String.graphemes()
    |> Enum.map_join(fn ch ->
      if String.match?(ch, ~r/^[[:alnum:]_.-]$/) do
        ch
      else
        "-"
      end
    end)
    |> String.replace(~r/-+/, "-")
    |> String.trim("-_. ")
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
