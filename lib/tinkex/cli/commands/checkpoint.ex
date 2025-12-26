defmodule Tinkex.CLI.Commands.Checkpoint do
  @moduledoc """
  Checkpoint management commands: save, list, info, publish, unpublish, delete, download.
  """

  alias Tinkex.Error

  alias Tinkex.Types.{
    CheckpointsListResponse,
    LoraConfig,
    ParsedCheckpointTinkerPath,
    WeightsInfoResponse
  }

  @doc """
  Saves a checkpoint with the given options and dependencies.
  """
  @spec run_checkpoint(map(), map()) :: {:ok, map()} | {:error, term()}
  def run_checkpoint(options, overrides \\ %{}) when is_map(options) and is_map(overrides) do
    deps = checkpoint_deps(overrides)

    with {:ok, output_path} <- fetch_output_path(options),
         {:ok, base_model} <- fetch_base_model(options),
         :ok <- ensure_started(deps),
         {:ok, config} <- build_config(options, deps),
         {:ok, service} <- start_service_client(config, deps),
         {:ok, training} <- create_training_client(service, base_model, options, deps),
         {:ok, response} <- save_weights(training, options, deps, config, base_model),
         {:ok, metadata} <- persist_metadata(output_path, base_model, response, deps) do
      IO.puts("Checkpoint saved to #{output_path}")
      {:ok, %{command: :checkpoint, metadata: metadata}}
    else
      {:error, reason} ->
        log_checkpoint_error(reason)
        {:error, reason}
    end
  end

  @doc """
  Manages checkpoint operations (list, info, publish, unpublish, delete, download).
  """
  @spec run_checkpoint_management(atom(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_checkpoint_management(action, options, overrides \\ %{}) do
    deps = management_deps(overrides)

    with {:ok, config} <- build_config(options, deps) do
      case action do
        :list -> checkpoint_list(config, options, deps)
        :info -> checkpoint_info(config, options, deps)
        :publish -> checkpoint_publish(config, options, deps)
        :unpublish -> checkpoint_unpublish(config, options, deps)
        :delete -> checkpoint_delete(config, options, deps)
        :download -> checkpoint_download(config, options, deps)
      end
    end
  end

  defp checkpoint_deps(overrides) do
    env_overrides = Application.get_env(:tinkex, :cli_checkpoint_deps, %{}) || %{}

    %{
      app_module: Application,
      config_module: Tinkex.Config,
      service_client_module: Tinkex.ServiceClient,
      training_client_module: Tinkex.TrainingClient,
      sampling_client_module: Tinkex.SamplingClient,
      json_module: Jason,
      file_module: File,
      now_fun: &DateTime.utc_now/0
    }
    |> Map.merge(env_overrides)
    |> Map.merge(overrides)
  end

  defp management_deps(overrides) do
    env_overrides = Application.get_env(:tinkex, :cli_management_deps, %{}) || %{}

    %{
      rest_api_module: Tinkex.API.Rest,
      rest_client_module: Tinkex.RestClient,
      checkpoint_download_module: Tinkex.CheckpointDownload,
      config_module: Tinkex.Config,
      json_module: Jason,
      checkpoint_page_size: 1000,
      run_page_size: 100
    }
    |> Map.merge(env_overrides)
    |> Map.merge(overrides)
  end

  defp fetch_output_path(%{output: output}) when is_binary(output) and byte_size(output) > 0,
    do: {:ok, output}

  defp fetch_output_path(_opts),
    do:
      {:error,
       Error.new(:validation, "--output is required for checkpoint command", category: :user)}

  defp fetch_base_model(options) do
    case Map.get(options, :base_model) || Map.get(options, :model_path) do
      nil ->
        {:error,
         Error.new(:validation, "Missing --base-model (or --model-path)", category: :user)}

      base when is_binary(base) ->
        {:ok, base}

      other ->
        {:error, Error.new(:validation, "Invalid base model: #{inspect(other)}", category: :user)}
    end
  end

  defp ensure_started(%{app_module: app_module}) do
    case app_module.ensure_all_started(:tinkex) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _app}} ->
        :ok

      {:error, reason} ->
        {:error, Error.new(:request_failed, "Failed to start Tinkex", data: reason)}
    end
  rescue
    e -> {:error, e}
  end

  defp build_config(options, %{config_module: config_module}) do
    http_pool =
      options
      |> Map.get(:http_pool)
      |> normalize_http_pool()

    config_opts =
      options
      |> Map.take([:api_key, :base_url, :timeout])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.new()
      |> maybe_put_http_pool(http_pool)

    {:ok, config_module.new(config_opts)}
  rescue
    e in ArgumentError ->
      {:error, Error.new(:validation, Exception.message(e), category: :user)}
  end

  defp normalize_http_pool(nil), do: nil
  defp normalize_http_pool(pool) when is_atom(pool), do: pool

  defp normalize_http_pool(pool) when is_binary(pool) and byte_size(pool) > 0 do
    String.to_atom(pool)
  end

  defp normalize_http_pool(pool) when is_binary(pool), do: nil

  defp normalize_http_pool(other),
    do: raise(ArgumentError, "http_pool must be a string or atom, got: #{inspect(other)}")

  defp maybe_put_http_pool(keyword, nil), do: keyword
  defp maybe_put_http_pool(keyword, pool), do: Keyword.put(keyword, :http_pool, pool)

  defp start_service_client(config, deps) do
    opts =
      [
        config: config,
        training_client_module: deps.training_client_module,
        sampling_client_module: Map.get(deps, :sampling_client_module)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case deps.service_client_module.start_link(opts) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:request_failed, "Failed to start service client", data: reason)}

      other ->
        {:error, Error.new(:request_failed, "Unexpected service client response", data: other)}
    end
  end

  defp create_training_client(service, base_model, options, deps) do
    lora_config = build_lora_config(options)

    training_opts =
      [lora_config: lora_config]
      |> maybe_put(:model_path, Map.get(options, :model_path))

    case deps.service_client_module.create_lora_training_client(
           service,
           base_model,
           training_opts
         ) do
      {:ok, training} ->
        {:ok, training}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:request_failed, "Failed to create training client", data: reason)}

      other ->
        {:error, Error.new(:request_failed, "Unexpected training client response", data: other)}
    end
  end

  defp build_lora_config(options) do
    %LoraConfig{
      rank: Map.get(options, :rank, 32),
      seed: Map.get(options, :seed),
      train_mlp: boolean_default(Map.get(options, :train_mlp), true),
      train_attn: boolean_default(Map.get(options, :train_attn), true),
      train_unembed: boolean_default(Map.get(options, :train_unembed), true)
    }
  end

  defp boolean_default(nil, default), do: default
  defp boolean_default(value, _default) when is_boolean(value), do: value
  defp boolean_default(_value, default), do: default

  defp save_weights(training, options, deps, config, base_model) do
    save_opts = build_save_options(options, config)
    name = checkpoint_name(options, base_model)

    case deps.training_client_module.save_weights_for_sampler(training, name, save_opts) do
      {:ok, %Task{} = task} ->
        await_checkpoint_task(task, save_opts)

      {:ok, response} ->
        {:ok, normalize_response(response)}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:request_failed, "save_weights_for_sampler failed", data: reason)}

      other ->
        {:error,
         Error.new(:request_failed, "Unexpected save_weights_for_sampler response", data: other)}
    end
  end

  defp build_save_options(options, config) do
    timeout = Map.get(options, :timeout, config.timeout)

    options
    |> Map.take([:timeout])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Keyword.new()
    |> Keyword.put_new(:timeout, timeout)
    |> Keyword.put_new(:await_timeout, timeout)
  end

  defp checkpoint_name(options, base_model) do
    case Map.get(options, :name) do
      nil ->
        # Generate default name from base_model
        model_slug =
          base_model
          |> String.replace(~r{[/:]}, "-")
          |> String.downcase()

        "checkpoint-#{model_slug}"

      name ->
        name
    end
  end

  defp await_checkpoint_task(%Task{} = task, save_opts) do
    timeout = Keyword.get(save_opts, :await_timeout, :infinity)

    try do
      case Task.await(task, timeout) do
        {:ok, response} ->
          {:ok, normalize_response(response)}

        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.new(:request_failed, "Checkpoint failed: #{inspect(reason)}")}

        other ->
          {:ok, normalize_response(other)}
      end
    catch
      :exit, {:timeout, _} ->
        {:error,
         Error.new(:api_timeout, "Timed out while awaiting checkpoint save",
           data: %{timeout: timeout}
         )}

      :exit, reason ->
        {:error, Error.new(:request_failed, "Checkpoint task exited: #{inspect(reason)}")}
    end
  end

  defp normalize_response(%_{} = struct), do: Map.from_struct(struct)
  defp normalize_response(%{} = map), do: map
  defp normalize_response(other), do: %{"result" => other}

  defp persist_metadata(output_path, base_model, response, deps) do
    file_module = deps.file_module
    json_module = deps.json_module

    timestamp =
      deps.now_fun.()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    data = normalize_response(response)

    metadata = %{
      "base_model" => base_model,
      "model_id" => extract_model_id(data) || base_model,
      "weights_path" => extract_weights_path(data),
      "saved_at" => timestamp,
      "response" => data
    }

    with :ok <- ensure_output_dir(file_module, output_path),
         :ok <- file_module.write(output_path, json_module.encode!(metadata) <> "\n") do
      {:ok, metadata}
    else
      {:error, reason} ->
        {:error,
         Error.new(:request_failed, "Failed to write checkpoint metadata",
           data: %{reason: reason}
         )}

      other ->
        {:error,
         Error.new(:request_failed, "Failed to write checkpoint metadata", data: %{reason: other})}
    end
  end

  defp ensure_output_dir(file_module, output_path) do
    dir = Path.dirname(output_path)

    case dir do
      "." -> :ok
      "" -> :ok
      _ -> file_module.mkdir_p(dir)
    end
  end

  defp extract_model_id(%{"model_id" => model_id}) when is_binary(model_id), do: model_id
  defp extract_model_id(%{model_id: model_id}) when is_binary(model_id), do: model_id
  defp extract_model_id(_), do: nil

  defp extract_weights_path(%{"path" => path}) when is_binary(path), do: path
  defp extract_weights_path(%{path: path}) when is_binary(path), do: path
  defp extract_weights_path(_), do: nil

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp log_checkpoint_error(%Error{} = error) do
    prefix =
      if Error.user_error?(error) do
        "Checkpoint failed. Please check your inputs: "
      else
        "Checkpoint failed due to server or transient error: "
      end

    IO.puts(:stderr, prefix <> Error.format(error))
  end

  defp log_checkpoint_error(%ArgumentError{} = error) do
    IO.puts(:stderr, "Checkpoint failed: #{Exception.message(error)}")
  end

  defp log_checkpoint_error(reason) do
    IO.puts(:stderr, "Checkpoint failed: #{inspect(reason)}")
  end

  # Management operations

  defp checkpoint_list(config, options, deps) do
    with {:ok, format} <- management_format(options),
         {:ok, response} <- do_checkpoint_list(config, options, deps) do
      render_checkpoint_list(response, format, deps)
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Checkpoint list failed: #{Error.format(error)}")
        {:error, error}

      {:error, reason} ->
        IO.puts(:stderr, "Checkpoint list failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_checkpoint_list(config, options, deps) do
    run_id = Map.get(options, :run_id)
    limit = options |> Map.get(:limit, 20) |> max(0)
    offset = max(Map.get(options, :offset, 0), 0)
    page_size = Map.get(deps, :checkpoint_page_size, 1000)

    if run_id do
      with {:ok, resp} <-
             normalize_checkpoint_response(deps.rest_api_module.list_checkpoints(config, run_id)) do
        checkpoints = resp.checkpoints

        {:ok,
         %{
           checkpoints: checkpoints,
           total: length(checkpoints),
           shown: length(checkpoints),
           run_id: run_id
         }}
      end
    else
      paginate_checkpoints(config, deps, limit, offset, page_size)
    end
  end

  defp paginate_checkpoints(config, deps, limit, offset, page_size) do
    alias Tinkex.CLI.Pagination

    initial_limit = Pagination.initial_page_limit(limit, page_size)

    with {:ok, resp} <-
           normalize_checkpoint_response(
             deps.rest_api_module.list_user_checkpoints(config, initial_limit, offset)
           ),
         {:ok, %{items: checkpoints, total: total}} <-
           Pagination.paginate_with(
             fn req_limit, req_offset ->
               case normalize_checkpoint_response(
                      deps.rest_api_module.list_user_checkpoints(config, req_limit, req_offset)
                    ) do
                 {:ok, %CheckpointsListResponse{} = response} ->
                   {:ok, {response.checkpoints, response.cursor}}

                 {:error, _} = error ->
                   error
               end
             end,
             resp.checkpoints,
             offset + length(resp.checkpoints),
             page_size,
             Pagination.pagination_target(limit, Pagination.cursor_total(resp.cursor), offset),
             Pagination.cursor_total(resp.cursor),
             offset,
             "checkpoints"
           ) do
      shown = length(checkpoints)
      final_total = total || Pagination.cursor_total(resp.cursor) || offset + shown

      {:ok,
       %{
         checkpoints: checkpoints,
         total: final_total,
         shown: shown,
         run_id: nil
       }}
    end
  end

  defp checkpoint_info(config, options, deps) do
    path = Map.fetch!(options, :path)

    with {:ok, [parsed]} <- validate_checkpoint_paths([path]),
         {:ok, format} <- management_format(options),
         {:ok, checkpoint} <- fetch_checkpoint_by_path(config, parsed, deps),
         {:ok, weights_info} <- fetch_weights_info(config, parsed.tinker_path, deps) do
      render_checkpoint_info(checkpoint, weights_info, format, deps)
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Checkpoint info failed: #{Error.format(error)}")
        {:error, error}

      {:error, reason} ->
        IO.puts(:stderr, "Checkpoint info failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp checkpoint_publish(config, options, deps) do
    path = Map.fetch!(options, :path)

    with {:ok, format} <- management_format(options),
         {:ok, _} <- deps.rest_api_module.publish_checkpoint(config, path) do
      maybe_print_json(format, deps.json_module, %{action: :publish, path: path})
      if format == :table, do: IO.puts("Published #{path}")
      {:ok, %{command: :checkpoint, action: :publish, path: path}}
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Publish failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp checkpoint_unpublish(config, options, deps) do
    path = Map.fetch!(options, :path)

    with {:ok, format} <- management_format(options),
         {:ok, _} <- deps.rest_api_module.unpublish_checkpoint(config, path) do
      maybe_print_json(format, deps.json_module, %{action: :unpublish, path: path})
      if format == :table, do: IO.puts("Unpublished #{path}")
      {:ok, %{command: :checkpoint, action: :unpublish, path: path}}
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Unpublish failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp checkpoint_download(config, options, deps) do
    path = Map.fetch!(options, :path)
    output_dir = Map.get(options, :output)
    force = Map.get(options, :force, false)
    rest_client = deps.rest_client_module.new("cli", config)

    with {:ok, format} <- management_format(options),
         {:ok, result} <-
           deps.checkpoint_download_module.download(rest_client, path,
             output_dir: output_dir,
             force: force
           ) do
      render_download_result(format, path, result, deps)
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Download failed: #{Error.format(error)}")
        {:error, error}

      {:error, reason} ->
        IO.puts(:stderr, "Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp render_download_result(format, path, result, deps) do
    if format == :json do
      maybe_print_json(format, deps.json_module, %{path: path, destination: result.destination})
    else
      IO.puts("Downloaded to #{result.destination}")
    end

    {:ok, %{command: :checkpoint, action: :download, path: path, destination: result.destination}}
  end

  defp checkpoint_delete(config, options, deps) do
    paths =
      options
      |> Map.get(:paths, [])
      |> case do
        [] -> List.wrap(Map.get(options, :path))
        list -> list
      end
      |> Enum.reject(&is_nil/1)

    with {:ok, format} <- management_format(options),
         {:ok, parsed_paths} <- validate_checkpoint_paths(paths) do
      tinker_paths = Enum.map(parsed_paths, & &1.tinker_path)
      execute_checkpoint_delete(config, format, parsed_paths, tinker_paths, options, deps)
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Delete failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp execute_checkpoint_delete(config, format, parsed_paths, tinker_paths, options, deps) do
    if confirm_delete?(tinker_paths, Map.get(options, :yes, false)) do
      perform_deletes(config, format, parsed_paths, tinker_paths, deps)
    else
      handle_delete_cancellation(format, tinker_paths, deps)
    end
  end

  defp perform_deletes(config, format, parsed_paths, tinker_paths, deps) do
    total = length(tinker_paths)

    results =
      parsed_paths
      |> Enum.with_index(1)
      |> Enum.map(fn {parsed, idx} ->
        delete_single_checkpoint(config, parsed, idx, total, deps)
      end)

    summary = summarize_deletes(results, tinker_paths)

    json_summary =
      Map.update(summary, :failures, [], fn failures ->
        Enum.map(failures, fn %{path: path, error: error} ->
          %{path: path, error: Error.format(error)}
        end)
      end)

    maybe_print_json(format, deps.json_module, json_summary)

    if summary.failed > 0, do: {:error, summary}, else: {:ok, summary}
  end

  defp delete_single_checkpoint(config, parsed, idx, total, deps) do
    IO.puts("Deleting #{idx}/#{total}: #{parsed.tinker_path}")

    case deps.rest_api_module.delete_checkpoint(config, parsed.tinker_path) do
      {:ok, _} ->
        IO.puts("Deleted #{parsed.tinker_path}")
        {:ok, parsed.tinker_path}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Delete failed for #{parsed.tinker_path}: #{Error.format(error)}")
        {:error, {parsed.tinker_path, error}}

      {:error, reason} ->
        error =
          Error.new(:request_failed, "Delete failed for #{parsed.tinker_path}",
            data: %{reason: reason}
          )

        IO.puts(:stderr, "Delete failed for #{parsed.tinker_path}: #{Error.format(error)}")
        {:error, {parsed.tinker_path, error}}
    end
  end

  defp handle_delete_cancellation(format, tinker_paths, deps) do
    result = %{
      command: :checkpoint,
      action: :delete,
      cancelled: true,
      paths: tinker_paths
    }

    IO.puts("Aborted delete of #{length(tinker_paths)} checkpoint(s).")
    maybe_print_json(format, deps.json_module, result)
    {:ok, result}
  end

  defp validate_checkpoint_paths([]) do
    {:error, Error.new(:validation, "Checkpoint path is required", category: :user)}
  end

  defp validate_checkpoint_paths(paths) do
    paths
    |> Enum.reduce_while([], fn path, acc ->
      case ParsedCheckpointTinkerPath.from_tinker_path(path) do
        {:ok, parsed} -> {:cont, [parsed | acc]}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      parsed -> {:ok, Enum.reverse(parsed)}
    end
  end

  defp confirm_delete?(_paths, true), do: true

  defp confirm_delete?(paths, false) do
    count = length(paths)
    IO.puts("Preparing to delete #{count} checkpoint#{if count == 1, do: "", else: "s"}:")
    Enum.each(paths, &IO.puts("  - #{&1}"))

    case IO.gets("Proceed? [y/N] ") do
      :eof -> false
      {:error, _reason} -> false
      input -> String.downcase(String.trim(to_string(input))) in ["y", "yes"]
    end
  end

  defp summarize_deletes(results, paths) do
    failures =
      for {:error, {path, error}} <- results do
        %{path: path, error: error}
      end

    %{
      command: :checkpoint,
      action: :delete,
      paths: paths,
      deleted: Enum.count(results, &match?({:ok, _}, &1)),
      failed: length(failures),
      failures: failures
    }
  end

  defp fetch_checkpoint_by_path(config, %ParsedCheckpointTinkerPath{} = parsed, deps) do
    with {:ok, %CheckpointsListResponse{} = resp} <-
           normalize_checkpoint_response(
             deps.rest_api_module.list_checkpoints(config, parsed.training_run_id)
           ) do
      case Enum.find(resp.checkpoints, &(&1.tinker_path == parsed.tinker_path)) do
        nil ->
          {:error,
           Error.new(:validation, "Checkpoint not found for #{to_string(parsed.tinker_path)}",
             category: :user
           )}

        checkpoint ->
          {:ok, checkpoint}
      end
    end
  end

  defp fetch_checkpoint_by_path(config, path, deps) when is_binary(path) do
    with {:ok, [parsed]} <- validate_checkpoint_paths([path]) do
      fetch_checkpoint_by_path(config, parsed, deps)
    end
  end

  defp fetch_weights_info(config, path, deps) do
    case deps.rest_api_module.get_weights_info_by_tinker_path(config, path) do
      {:ok, %WeightsInfoResponse{} = info} ->
        {:ok, info}

      {:ok, data} ->
        {:ok, WeightsInfoResponse.from_json(data)}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp render_checkpoint_list(
         %{checkpoints: checkpoints, total: total, shown: shown} = resp,
         format,
         deps
       ) do
    alias Tinkex.CLI.Formatting

    run_id = Map.get(resp, :run_id)

    case format do
      :json ->
        payload =
          %{
            "checkpoints" => Enum.map(checkpoints, &Formatting.checkpoint_to_map/1),
            "total" => total,
            "shown" => shown
          }
          |> maybe_put_run_id(run_id)

        IO.puts(deps.json_module.encode!(payload))

      :table ->
        header =
          if run_id do
            "Checkpoints for #{run_id} (#{shown}/#{total})"
          else
            "Checkpoints (#{shown}/#{total})"
          end

        IO.puts(header)
        IO.puts("Checkpoint ID\tType\tSize\tPublic\tCreated\tPath")

        Enum.each(checkpoints, fn ckpt ->
          map = Formatting.checkpoint_to_map(ckpt)

          IO.puts(
            Enum.join(
              [
                map["checkpoint_id"],
                map["checkpoint_type"],
                Formatting.format_size(map["size_bytes"]),
                to_string(map["public"]),
                Formatting.format_datetime(map["time"]),
                map["tinker_path"]
              ],
              "\t"
            )
          )
        end)
    end

    {:ok,
     %{
       command: :checkpoint,
       action: :list,
       count: shown,
       total: total,
       run_id: run_id
     }}
  end

  defp render_checkpoint_info(checkpoint, weights_info, format, deps) do
    alias Tinkex.CLI.Formatting

    map = Formatting.checkpoint_to_map(checkpoint)
    weights_map = Formatting.weights_info_to_map(weights_info)

    case format do
      :json ->
        IO.puts(deps.json_module.encode!(Map.merge(map, weights_map)))

      :table ->
        props =
          [
            {"Checkpoint ID", map["checkpoint_id"]},
            {"Training run ID", map["training_run_id"]},
            {"Type", map["checkpoint_type"]},
            {"Path", map["tinker_path"]},
            {"Size", Formatting.format_size(map["size_bytes"])},
            {"Public", to_string(map["public"])},
            {"Created", Formatting.format_datetime(map["time"])},
            {"Base model", weights_map["base_model"]},
            {"LoRA", to_string(weights_map["is_lora"])}
          ]
          |> maybe_append_lora_rank(weights_map["lora_rank"])

        Enum.each(props, fn {label, value} -> IO.puts("#{label}: #{value}") end)
    end

    {:ok, %{command: :checkpoint, action: :info, path: map["tinker_path"]}}
  end

  defp maybe_append_lora_rank(props, nil), do: props
  defp maybe_append_lora_rank(props, rank), do: props ++ [{"LoRA rank", to_string(rank)}]

  defp maybe_put_run_id(payload, nil), do: payload
  defp maybe_put_run_id(payload, run_id), do: Map.put(payload, "run_id", run_id)

  defp maybe_print_json(:json, json_module, payload), do: IO.puts(json_module.encode!(payload))
  defp maybe_print_json(_format, _json_module, _payload), do: :ok

  defp management_format(options) do
    format =
      cond do
        Map.get(options, :json, false) -> "json"
        is_binary(Map.get(options, :format)) -> String.downcase(Map.get(options, :format))
        Map.get(options, :format) == :json -> "json"
        Map.get(options, :format) == :table -> "table"
        true -> "table"
      end

    case format do
      "json" -> {:ok, :json}
      "table" -> {:ok, :table}
      other -> {:error, Error.new(:validation, "Invalid format: #{other}", category: :user)}
    end
  end

  defp normalize_checkpoint_response({:ok, %CheckpointsListResponse{} = resp}), do: {:ok, resp}

  defp normalize_checkpoint_response({:ok, data}) when is_map(data) do
    {:ok, CheckpointsListResponse.from_map(data)}
  end

  defp normalize_checkpoint_response({:error, _} = error), do: error
end
