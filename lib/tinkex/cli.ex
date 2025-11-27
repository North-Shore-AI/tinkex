defmodule Tinkex.CLI do
  @moduledoc """
  Command-line interface entrypoint for the Tinkex escript.

  `main/1` is a thin wrapper over `run/1` so the CLI can be tested without halting
  the VM. The checkpoint command drives the Service/Training client flow to save
  weights; the run command remains scaffolded for the next phase.
  """

  alias Tinkex.Error

  alias Tinkex.Types.{
    CheckpointsListResponse,
    LoraConfig,
    ModelInput,
    SampleResponse,
    SamplingParams,
    StopReason,
    TrainingRun,
    TrainingRunsResponse,
    WeightsInfoResponse
  }

  @doc """
  Entry point invoked by the escript executable.
  """
  @spec main([String.t()]) :: no_return()
  def main(argv) do
    exit_code =
      case run(argv) do
        {:ok, _} -> 0
        {:error, _} -> 1
      end

    System.halt(exit_code)
  end

  @doc """
  Parses arguments and dispatches to the requested subcommand.
  """
  @spec run([String.t()]) :: {:ok, term()} | {:error, term()}
  def run(argv) do
    case parse(argv) do
      {:help, message} ->
        IO.puts(message)
        {:ok, :help}

      {:error, message} ->
        IO.puts(:stderr, message)
        {:error, :invalid_args}

      {:command, command, options} ->
        dispatch(command, options)
    end
  end

  defp dispatch({:checkpoint, :save}, options), do: run_checkpoint(options)

  defp dispatch({:checkpoint, action}, options) do
    run_checkpoint_management(action, options)
  end

  defp dispatch({:run, :sample}, options), do: run_sampling(options)

  defp dispatch({:run, action}, options) do
    run_run_management(action, options)
  end

  defp dispatch(:version, options) do
    deps = version_deps()
    version = current_version(deps)
    commit = current_commit(deps)
    payload = %{"version" => version, "commit" => commit}

    case Map.get(options, :json, false) do
      true ->
        IO.puts(deps.json_module.encode!(payload))

      false ->
        IO.puts(format_version(version, commit))
    end

    {:ok, %{command: :version, version: version, commit: commit, options: options}}
  end

  @doc false
  @spec run_sampling(map(), map()) :: {:ok, map()} | {:error, term()}
  def run_sampling(options, overrides \\ %{}) when is_map(options) and is_map(overrides) do
    deps = sampling_deps(overrides)

    with {:ok, model_name} <- fetch_base_model(options),
         {:ok, prompt_source} <- load_prompt(options, deps),
         :ok <- ensure_started(deps),
         {:ok, config} <- build_config(options, deps),
         {:ok, service} <- start_service_client(config, deps),
         {:ok, sampler} <- create_sampling_client(service, options, deps),
         {:ok, model_input} <- build_model_input(prompt_source, model_name, deps),
         {:ok, sampling_params} <- build_sampling_params(options),
         {:ok, response} <-
           perform_sampling(
             sampler,
             model_input,
             sampling_params,
             options,
             deps,
             model_name,
             config
           ) do
      {:ok, %{command: :run, response: response}}
    else
      {:error, reason} ->
        log_sampling_error(reason)
        {:error, reason}
    end
  end

  defp sampling_deps(overrides) do
    env_overrides = Application.get_env(:tinkex, :cli_run_deps, %{}) || %{}

    %{
      app_module: Application,
      config_module: Tinkex.Config,
      service_client_module: Tinkex.ServiceClient,
      sampling_client_module: Tinkex.SamplingClient,
      training_client_module: Tinkex.TrainingClient,
      model_input_module: ModelInput,
      tokenizer_module: Tinkex.Tokenizer,
      json_module: Jason,
      file_module: File
    }
    |> Map.merge(env_overrides)
    |> Map.merge(overrides)
  end

  @doc false
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
      json_module: Jason
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

  defp create_sampling_client(service, options, deps) do
    sampling_opts =
      []
      |> maybe_put(:base_model, Map.get(options, :base_model))
      |> maybe_put(:model_path, Map.get(options, :model_path))

    case deps.service_client_module.create_sampling_client(service, sampling_opts) do
      {:ok, sampling} ->
        {:ok, sampling}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:request_failed, "Failed to create sampling client", data: reason)}

      other ->
        {:error, Error.new(:request_failed, "Unexpected sampling client response", data: other)}
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

  defp default_if_nil(nil, default), do: default
  defp default_if_nil(value, _default), do: value

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

  defp load_prompt(options, deps) do
    prompt = Map.get(options, :prompt)
    prompt_file = Map.get(options, :prompt_file)

    cond do
      is_binary(prompt) and is_binary(prompt_file) ->
        {:error,
         Error.new(:validation, "--prompt and --prompt-file cannot both be provided",
           category: :user
         )}

      is_binary(prompt) ->
        {:ok, {:text, prompt}}

      is_binary(prompt_file) ->
        read_prompt_file(prompt_file, deps)

      true ->
        {:error,
         Error.new(:validation, "Missing prompt. Provide --prompt or --prompt-file",
           category: :user
         )}
    end
  end

  defp read_prompt_file(path, %{file_module: file_module, json_module: json_module}) do
    case file_module.read(path) do
      {:ok, content} ->
        {:ok, classify_prompt_content(content, json_module)}

      {:error, reason} ->
        {:error,
         Error.new(:validation, "Failed to read prompt file #{path}: #{inspect(reason)}",
           category: :user
         )}
    end
  end

  defp classify_prompt_content(content, json_module) do
    case decode_prompt_tokens(content, json_module) do
      {:ok, tokens} -> {:tokens, tokens}
      :error -> {:text, content}
    end
  end

  defp decode_prompt_tokens(content, json_module) do
    case safe_decode(json_module, content) do
      {:ok, tokens} when is_list(tokens) ->
        if Enum.all?(tokens, &is_integer/1), do: {:ok, tokens}, else: :error

      {:ok, %{"tokens" => tokens}} when is_list(tokens) ->
        if Enum.all?(tokens, &is_integer/1), do: {:ok, tokens}, else: :error

      _ ->
        :error
    end
  end

  defp safe_decode(json_module, content) do
    json_module.decode(content)
  rescue
    _ -> :error
  end

  defp build_model_input({:tokens, tokens}, _model_name, %{model_input_module: model_input_module}) do
    cond do
      not is_list(tokens) ->
        {:error,
         Error.new(:validation, "Prompt tokens must be a list of integers", category: :user)}

      not Enum.all?(tokens, &is_integer/1) ->
        {:error, Error.new(:validation, "Prompt tokens must be integers", category: :user)}

      true ->
        {:ok, model_input_module.from_ints(tokens)}
    end
  end

  defp build_model_input({:text, text}, model_name, %{model_input_module: model_input_module}) do
    case model_input_module.from_text(text, model_name: model_name) do
      {:ok, model_input} ->
        {:ok, model_input}

      {:error, %Error{} = error} ->
        {:error, mark_user_error(error)}

      {:error, reason} ->
        {:error,
         Error.new(:validation, "Failed to encode prompt: #{inspect(reason)}", category: :user)}
    end
  end

  defp mark_user_error(%Error{} = error) do
    if error.category do
      error
    else
      %{error | category: :user}
    end
  end

  defp build_sampling_params(options) do
    params = %SamplingParams{
      max_tokens: Map.get(options, :max_tokens),
      temperature: default_if_nil(Map.get(options, :temperature), 1.0),
      top_k: default_if_nil(Map.get(options, :top_k), -1),
      top_p: default_if_nil(Map.get(options, :top_p), 1.0)
    }

    {:ok, params}
  end

  defp perform_sampling(
         sampler,
         model_input,
         sampling_params,
         options,
         deps,
         model_name,
         config
       ) do
    num_samples = Map.get(options, :num_samples, 1)
    await_timeout = default_if_nil(Map.get(options, :timeout), config.timeout)

    sample_opts =
      []
      |> Keyword.put(:num_samples, num_samples)
      |> Keyword.put(:prompt_logprobs, false)
      |> Keyword.put(:topk_prompt_logprobs, 0)
      |> maybe_put(:timeout, await_timeout)

    IO.puts("Starting sampling...")

    case deps.sampling_client_module.sample(sampler, model_input, sampling_params, sample_opts) do
      {:ok, %Task{} = task} ->
        with {:ok, %SampleResponse{} = response} <- await_sampling_task(task, await_timeout),
             {:ok, output} <- format_sample_output(response, model_name, options, deps),
             :ok <- deliver_output(output, options, deps) do
          IO.puts("Sampling complete (#{length(response.sequences)} sequences)")
          {:ok, response}
        end

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:request_failed, "Sampling request failed", data: reason)}

      other ->
        {:error, Error.new(:request_failed, "Unexpected sampling response", data: other)}
    end
  end

  defp await_sampling_task(%Task{} = task, timeout) do
    try do
      case Task.await(task, timeout) do
        {:ok, %SampleResponse{} = response} ->
          {:ok, response}

        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.new(:request_failed, "Sampling failed: #{inspect(reason)}")}

        %SampleResponse{} = response ->
          {:ok, response}

        other ->
          {:error, Error.new(:request_failed, "Unexpected sampling result: #{inspect(other)}")}
      end
    catch
      :exit, {:timeout, _} ->
        {:error,
         Error.new(:api_timeout, "Timed out while awaiting sampling", data: %{timeout: timeout})}

      :exit, reason ->
        {:error, Error.new(:request_failed, "Sampling task exited: #{inspect(reason)}")}
    end
  end

  defp format_sample_output(%SampleResponse{} = response, model_name, options, deps) do
    case Map.get(options, :json, false) do
      true ->
        map = sample_response_to_map(response)
        json = deps.json_module.encode!(map)
        {:ok, %{mode: :json, content: json}}

      false ->
        text = format_sequences_plain(response, model_name, deps)
        {:ok, %{mode: :plain, content: text}}
    end
  end

  defp sample_response_to_map(%SampleResponse{} = response) do
    %{
      "sequences" =>
        Enum.map(response.sequences, fn seq ->
          %{
            "tokens" => seq.tokens,
            "logprobs" => seq.logprobs,
            "stop_reason" => stop_reason_string(seq.stop_reason)
          }
        end),
      "prompt_logprobs" => response.prompt_logprobs,
      "topk_prompt_logprobs" => format_topk_prompt_logprobs(response.topk_prompt_logprobs),
      "type" => response.type
    }
  end

  defp stop_reason_string(nil), do: nil
  defp stop_reason_string(reason), do: StopReason.to_string(reason)

  defp format_topk_prompt_logprobs(nil), do: nil

  defp format_topk_prompt_logprobs(items) when is_list(items) do
    Enum.map(items, fn
      nil ->
        nil

      inner when is_list(inner) ->
        Enum.map(inner, fn {token_id, logprob} -> [token_id, logprob] end)
    end)
  end

  defp format_sequences_plain(%SampleResponse{} = response, model_name, deps) do
    response.sequences
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {seq, idx} ->
      text = decode_tokens(seq.tokens, model_name, deps)
      metadata = format_sequence_metadata(seq)

      ["Sample #{idx}:", text, metadata]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n")
    end)
  end

  defp format_sequence_metadata(seq) do
    parts =
      []
      |> maybe_add_stop_reason(seq.stop_reason)
      |> maybe_add_logprobs(seq.logprobs)

    case Enum.reject(parts, &(&1 in [nil, ""])) do
      [] -> ""
      items -> Enum.join(items, " | ")
    end
  end

  defp maybe_add_stop_reason(parts, nil), do: parts

  defp maybe_add_stop_reason(parts, reason),
    do: parts ++ ["stop_reason=#{stop_reason_string(reason)}"]

  defp maybe_add_logprobs(parts, nil), do: parts

  defp maybe_add_logprobs(parts, logprobs) when is_list(logprobs) and logprobs != [] do
    avg = Enum.sum(logprobs) / length(logprobs)
    parts ++ ["avg_logprob=#{Float.round(avg, 3)}"]
  end

  defp maybe_add_logprobs(parts, _), do: parts

  defp decode_tokens(tokens, model_name, %{tokenizer_module: tokenizer_module}) do
    case tokenizer_module.decode(tokens, model_name) do
      {:ok, text} ->
        text

      {:error, %Error{} = error} ->
        "[decode error: #{Error.format(error)}]"

      {:error, reason} ->
        "[decode error: #{inspect(reason)}]"

      other when is_binary(other) ->
        other

      other ->
        "[decode error: #{inspect(other)}]"
    end
  rescue
    e ->
      "[decode error: #{Exception.message(e)}]"
  end

  defp deliver_output(%{content: content}, options, deps) do
    case Map.get(options, :output) do
      nil ->
        IO.puts(content)
        :ok

      path when is_binary(path) ->
        with :ok <- ensure_output_dir(deps.file_module, path),
             :ok <- deps.file_module.write(path, content <> "\n") do
          :ok
        else
          {:error, reason} ->
            {:error, Error.new(:request_failed, "Failed to write output", data: reason)}

          other ->
            {:error, Error.new(:request_failed, "Failed to write output", data: other)}
        end

      other ->
        {:error,
         Error.new(:validation, "Invalid output path: #{inspect(other)}", category: :user)}
    end
  end

  defp log_sampling_error(%Error{} = error) do
    prefix =
      if Error.user_error?(error) do
        "Sampling failed. Please check your inputs: "
      else
        "Sampling failed due to server or transient error. Consider retrying: "
      end

    IO.puts(:stderr, prefix <> Error.format(error))
  end

  defp log_sampling_error(%ArgumentError{} = error) do
    IO.puts(:stderr, "Sampling failed: #{Exception.message(error)}")
  end

  defp log_sampling_error(reason) do
    IO.puts(:stderr, "Sampling failed: #{inspect(reason)}")
  end

  @doc false
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

  @doc false
  @spec run_run_management(atom(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_run_management(action, options, overrides \\ %{}) do
    deps = management_deps(overrides)

    with {:ok, config} <- build_config(options, deps) do
      case action do
        :list -> run_list(config, options, deps)
        :info -> run_info(config, options, deps)
      end
    end
  end

  defp checkpoint_list(config, options, deps) do
    limit = Map.get(options, :limit, 20)
    offset = Map.get(options, :offset, 0)

    case deps.rest_api_module.list_user_checkpoints(config, limit, offset) do
      {:ok, %CheckpointsListResponse{} = resp} ->
        Enum.each(resp.checkpoints, fn ckpt ->
          IO.puts("#{ckpt.checkpoint_id}\t#{ckpt.tinker_path}")
        end)

        {:ok, %{command: :checkpoint, action: :list, count: length(resp.checkpoints)}}

      {:ok, data} when is_map(data) ->
        resp = CheckpointsListResponse.from_map(data)

        Enum.each(resp.checkpoints, fn ckpt ->
          IO.puts("#{ckpt.checkpoint_id}\t#{ckpt.tinker_path}")
        end)

        {:ok, %{command: :checkpoint, action: :list, count: length(resp.checkpoints)}}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Checkpoint list failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp checkpoint_info(config, options, deps) do
    path = Map.fetch!(options, :path)

    case deps.rest_api_module.get_weights_info_by_tinker_path(config, path) do
      {:ok, %WeightsInfoResponse{} = info} ->
        IO.puts("Base model: #{info.base_model}")
        IO.puts("LoRA: #{info.is_lora}")
        if info.lora_rank, do: IO.puts("LoRA rank: #{info.lora_rank}")
        {:ok, %{command: :checkpoint, action: :info, path: path}}

      {:ok, data} ->
        info = WeightsInfoResponse.from_json(data)
        IO.puts("Base model: #{info.base_model}")
        IO.puts("LoRA: #{info.is_lora}")
        if info.lora_rank, do: IO.puts("LoRA rank: #{info.lora_rank}")
        {:ok, %{command: :checkpoint, action: :info, path: path}}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Checkpoint info failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp checkpoint_publish(config, options, deps) do
    path = Map.fetch!(options, :path)

    case deps.rest_api_module.publish_checkpoint(config, path) do
      {:ok, _} ->
        IO.puts("Published #{path}")
        {:ok, %{command: :checkpoint, action: :publish, path: path}}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Publish failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp checkpoint_unpublish(config, options, deps) do
    path = Map.fetch!(options, :path)

    case deps.rest_api_module.unpublish_checkpoint(config, path) do
      {:ok, _} ->
        IO.puts("Unpublished #{path}")
        {:ok, %{command: :checkpoint, action: :unpublish, path: path}}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Unpublish failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp checkpoint_delete(config, options, deps) do
    path = Map.fetch!(options, :path)

    case deps.rest_api_module.delete_checkpoint(config, path) do
      {:ok, _} ->
        IO.puts("Deleted #{path}")
        {:ok, %{command: :checkpoint, action: :delete, path: path}}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Delete failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp checkpoint_download(config, options, deps) do
    path = Map.fetch!(options, :path)
    output_dir = Map.get(options, :output)
    force = Map.get(options, :force, false)
    rest_client = deps.rest_client_module.new("cli", config)

    case deps.checkpoint_download_module.download(rest_client, path,
           output_dir: output_dir,
           force: force
         ) do
      {:ok, result} ->
        IO.puts("Downloaded to #{result.destination}")

        {:ok,
         %{command: :checkpoint, action: :download, path: path, destination: result.destination}}

      {:error, reason} ->
        IO.puts(:stderr, "Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_list(config, options, deps) do
    limit = Map.get(options, :limit, 20)
    offset = Map.get(options, :offset, 0)

    case deps.rest_api_module.list_training_runs(config, limit, offset) do
      {:ok, %TrainingRunsResponse{} = resp} ->
        Enum.each(resp.training_runs, fn run ->
          IO.puts("#{run.training_run_id}\t#{run.base_model}")
        end)

        {:ok, %{command: :run, action: :list, count: length(resp.training_runs)}}

      {:ok, data} ->
        resp = TrainingRunsResponse.from_map(data)

        Enum.each(resp.training_runs, fn run ->
          IO.puts("#{run.training_run_id}\t#{run.base_model}")
        end)

        {:ok, %{command: :run, action: :list, count: length(resp.training_runs)}}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Run list failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp run_info(config, options, deps) do
    run_id = Map.fetch!(options, :run_id)

    case deps.rest_api_module.get_training_run(config, run_id) do
      {:ok, %TrainingRun{} = run} ->
        IO.puts("#{run.training_run_id} (#{run.base_model})")
        IO.puts("Owner: #{run.model_owner}")
        {:ok, %{command: :run, action: :info, run_id: run.training_run_id}}

      {:ok, data} ->
        run = TrainingRun.from_map(data)
        IO.puts("#{run.training_run_id} (#{run.base_model})")
        {:ok, %{command: :run, action: :info, run_id: run.training_run_id}}

      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Run info failed: #{Error.format(error)}")
        {:error, error}
    end
  end

  defp parse([]), do: {:help, global_help()}
  defp parse(["--help"]), do: {:help, global_help()}
  defp parse(["-h"]), do: {:help, global_help()}
  defp parse(["--version" | rest]), do: parse_command(:version, rest)
  defp parse(["checkpoint" | rest]), do: parse_checkpoint_command(rest)
  defp parse(["run" | rest]), do: parse_run_command(rest)
  defp parse(["version" | rest]), do: parse_command(:version, rest)

  defp parse([unknown | _rest]) do
    {:error, "Unknown command: #{unknown}\n\n" <> global_help()}
  end

  defp parse_checkpoint_command([sub | rest])
       when sub in ["list", "info", "publish", "unpublish", "delete", "download"] do
    parse_management_command({:checkpoint, String.to_atom(sub)}, rest)
  end

  defp parse_checkpoint_command(rest), do: parse_command({:checkpoint, :save}, rest)

  defp parse_run_command([sub | rest]) when sub in ["list", "info"] do
    parse_management_command({:run, String.to_atom(sub)}, rest)
  end

  defp parse_run_command(rest), do: parse_command({:run, :sample}, rest)

  defp parse_command({:checkpoint, :save}, argv) do
    parse_subcommand({:checkpoint, :save}, argv, checkpoint_switches(), &checkpoint_help/0)
  end

  defp parse_command({:run, :sample}, argv) do
    parse_subcommand({:run, :sample}, argv, run_switches(), &run_help/0)
  end

  defp parse_command(:version, argv) do
    parse_subcommand(:version, argv, version_switches(), &version_help/0)
  end

  defp parse_management_command({:checkpoint, action}, argv) do
    switches = checkpoint_management_switches(action)
    {parsed, remaining, invalid} = OptionParser.parse(argv, strict: switches, aliases: aliases())
    parsed_map = Map.new(parsed)

    cond do
      Map.get(parsed_map, :help, false) ->
        {:help, checkpoint_management_help()}

      invalid != [] ->
        {:error,
         invalid_option_message({:checkpoint, action}, invalid, &checkpoint_management_help/0)}

      action in [:info, :publish, :unpublish, :delete, :download] and remaining == [] ->
        {:error, "Checkpoint path is required\n\n" <> checkpoint_management_help()}

      remaining != [] and action == :list ->
        {:error,
         unexpected_args_message({:checkpoint, action}, remaining, &checkpoint_management_help/0)}

      true ->
        parsed_map =
          case {action, remaining} do
            {_act, [path | _]} -> Map.put(parsed_map, :path, path)
            _ -> parsed_map
          end

        {:command, {:checkpoint, action}, parsed_map}
    end
  end

  defp parse_management_command({:run, action}, argv) do
    switches = run_management_switches(action)
    {parsed, remaining, invalid} = OptionParser.parse(argv, strict: switches, aliases: aliases())
    parsed_map = Map.new(parsed)

    cond do
      Map.get(parsed_map, :help, false) ->
        {:help, run_management_help()}

      invalid != [] ->
        {:error, invalid_option_message({:run, action}, invalid, &run_management_help/0)}

      action == :info and remaining == [] ->
        {:error, "Run ID is required\n\n" <> run_management_help()}

      remaining != [] and action == :list ->
        {:error, unexpected_args_message({:run, action}, remaining, &run_management_help/0)}

      true ->
        parsed_map =
          case {action, remaining} do
            {:info, [run_id | _]} -> Map.put(parsed_map, :run_id, run_id)
            _ -> parsed_map
          end

        {:command, {:run, action}, parsed_map}
    end
  end

  defp parse_subcommand(command, argv, switches, help_fun) do
    {parsed, remaining, invalid} = OptionParser.parse(argv, strict: switches, aliases: aliases())
    parsed_map = Map.new(parsed)

    cond do
      Map.get(parsed_map, :help, false) ->
        {:help, help_fun.()}

      invalid != [] ->
        {:error, invalid_option_message(command, invalid, help_fun)}

      remaining != [] ->
        {:error, unexpected_args_message(command, remaining, help_fun)}

      true ->
        {:command, command, parsed_map}
    end
  end

  defp current_version(%{app_module: app_module}) do
    case app_module.spec(:tinkex, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  rescue
    _ -> "unknown"
  end

  defp current_commit(%{system_module: system_module}) do
    case system_module.cmd("git", ["rev-parse", "--short", "HEAD"]) do
      {commit, 0} -> normalize_commit(commit)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp normalize_commit(commit) when is_binary(commit) do
    commit
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_commit(nil), do: nil
  defp normalize_commit(other), do: to_string(other)

  defp format_version(version, commit) do
    case normalize_commit(commit) do
      nil -> "tinkex #{version}"
      value -> "tinkex #{version} (#{value})"
    end
  end

  defp invalid_option_message(command, invalid, help_fun) do
    details = Enum.map_join(invalid, ", ", fn {opt, _} -> opt end)

    "Invalid option(s) for #{command}: #{details}\n\n" <> help_fun.()
  end

  defp unexpected_args_message(command, remaining, help_fun) do
    unexpected = Enum.map_join(remaining, " ", &"'#{&1}'")

    "Unexpected argument(s) for #{command}: #{unexpected}\n\n" <> help_fun.()
  end

  defp global_help do
    """
    Usage:
      tinkex <command> [options]

    Commands:
      checkpoint   Save or manage checkpoints (list/info/publish/unpublish/delete/download)
      run          Generate text or manage training runs (list/info)
      version      Show version information

    Run `tinkex <command> --help` for command-specific options.
    """
  end

  defp checkpoint_help do
    """
    Usage:
      tinkex checkpoint [options]          # save checkpoint
      tinkex checkpoint <subcommand> ...   # management commands

    Options:
      --base-model <id>       Base model identifier (e.g., Qwen/Qwen2.5-7B)
      --model-path <path>     Local model path
      --output <path>         Path to write checkpoint metadata
      --rank <int>            LoRA rank
      --seed <int>            Random seed
      --train-mlp             Enable MLP training (LoRA)
      --train-attn            Enable attention training (LoRA)
      --train-unembed         Enable unembedding training (LoRA)
      --api-key <key>         API key
      --base-url <url>        API base URL
      --timeout <ms>          Request timeout in milliseconds
      -h, --help              Show this help text
    """
  end

  defp checkpoint_management_help do
    """
    Usage:
      tinkex checkpoint list [--limit <int>] [--offset <int>]
      tinkex checkpoint info <tinker_path>
      tinkex checkpoint publish <tinker_path>
      tinkex checkpoint unpublish <tinker_path>
      tinkex checkpoint delete <tinker_path>
      tinkex checkpoint download <tinker_path> [--output <dir>] [--force]

    Common options:
      --api-key <key>         API key
      --base-url <url>        API base URL
      --timeout <ms>          Request timeout in milliseconds
      -h, --help              Show this help text
    """
  end

  defp run_help do
    """
    Usage:
      tinkex run [options]              # sampling
      tinkex run <subcommand> ...       # management commands

    Options:
      --base-model <id>       Base model identifier
      --model-path <path>     Local model path
      --prompt <text>         Prompt text
      --prompt-file <path>    Path to file containing prompt text or token IDs (JSON)
      --max-tokens <int>      Maximum tokens to generate
      --temperature <float>   Sampling temperature
      --top-k <int>           Top-k sampling parameter
      --top-p <float>         Nucleus sampling parameter
      --num-samples <int>     Number of samples to return
      --api-key <key>         API key
      --base-url <url>        API base URL
      --timeout <ms>          Request timeout in milliseconds
      --http-pool <name>      HTTP pool name to use
      --output <path>         Write output to file (stdout by default)
      --json                  Output JSON (full response)
      -h, --help              Show this help text
    """
  end

  defp run_management_help do
    """
    Usage:
      tinkex run list [--limit <int>] [--offset <int>]
      tinkex run info <run_id>

    Common options:
      --api-key <key>         API key
      --base-url <url>        API base URL
      --timeout <ms>          Request timeout in milliseconds
      -h, --help              Show this help text
    """
  end

  defp version_help do
    """
    Usage:
      tinkex version [options]

    Options:
      --json      Output JSON (version payload)
      --deps      Reserved flag for dependency output
      -h, --help  Show this help text

    `tinkex --version` is an alias for this command.
    """
  end

  defp checkpoint_switches do
    [
      help: :boolean,
      base_model: :string,
      model_path: :string,
      name: :string,
      output: :string,
      rank: :integer,
      seed: :integer,
      train_mlp: :boolean,
      train_attn: :boolean,
      train_unembed: :boolean,
      api_key: :string,
      base_url: :string,
      timeout: :integer
    ]
  end

  defp run_switches do
    [
      help: :boolean,
      base_model: :string,
      model_path: :string,
      prompt: :string,
      prompt_file: :string,
      max_tokens: :integer,
      temperature: :float,
      top_k: :integer,
      top_p: :float,
      num_samples: :integer,
      api_key: :string,
      base_url: :string,
      timeout: :integer,
      http_pool: :string,
      output: :string,
      json: :boolean
    ]
  end

  defp checkpoint_management_switches(_action) do
    [
      help: :boolean,
      api_key: :string,
      base_url: :string,
      timeout: :integer,
      limit: :integer,
      offset: :integer,
      output: :string,
      force: :boolean
    ]
  end

  defp run_management_switches(_action) do
    [
      help: :boolean,
      api_key: :string,
      base_url: :string,
      timeout: :integer,
      limit: :integer,
      offset: :integer
    ]
  end

  defp version_switches do
    [
      help: :boolean,
      json: :boolean,
      deps: :boolean
    ]
  end

  defp version_deps(overrides \\ %{}) do
    env_overrides = Application.get_env(:tinkex, :cli_version_deps, %{}) || %{}

    %{
      app_module: Application,
      system_module: System,
      json_module: Jason
    }
    |> Map.merge(env_overrides)
    |> Map.merge(overrides)
  end

  defp aliases do
    [h: :help]
  end
end
