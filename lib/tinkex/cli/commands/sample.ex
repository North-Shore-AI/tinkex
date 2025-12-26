defmodule Tinkex.CLI.Commands.Sample do
  @moduledoc """
  Sampling/text generation command.
  """

  alias Tinkex.Error
  alias Tinkex.Types.{ModelInput, SampleResponse, SamplingParams, StopReason}

  @doc """
  Runs sampling with the given options and dependencies.
  """
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

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

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

  defp default_if_nil(nil, default), do: default
  defp default_if_nil(value, _default), do: value

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

  defp ensure_output_dir(file_module, output_path) do
    dir = Path.dirname(output_path)

    case dir do
      "." -> :ok
      "" -> :ok
      _ -> file_module.mkdir_p(dir)
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
end
