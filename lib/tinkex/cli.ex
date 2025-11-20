defmodule Tinkex.CLI do
  @moduledoc """
  Command-line interface entrypoint for the Tinkex escript.

  `main/1` is a thin wrapper over `run/1` so the CLI can be tested without halting
  the VM. The checkpoint command drives the Service/Training client flow to save
  weights; the run command remains scaffolded for the next phase.
  """

  alias Tinkex.Error
  alias Tinkex.Types.LoraConfig

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

  defp dispatch(:checkpoint, options) do
    run_checkpoint(options)
  end

  defp dispatch(:run, options) do
    IO.puts("run command (scaffold). Parsed options: #{format_options(options)}")
    {:ok, %{command: :run, options: options}}
  end

  defp dispatch(:version, options) do
    version = current_version()

    case Map.get(options, :json, false) do
      true ->
        output = %{"version" => version}
        IO.puts(Jason.encode!(output))

      false ->
        IO.puts("tinkex #{version}")
    end

    {:ok, %{command: :version, version: version, options: options}}
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
    config_opts =
      options
      |> Map.take([:api_key, :base_url, :timeout])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.new()

    {:ok, config_module.new(config_opts)}
  rescue
    e in ArgumentError ->
      {:error, Error.new(:validation, Exception.message(e), category: :user)}
  end

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
      [base_model: base_model, lora_config: lora_config]
      |> maybe_put(:model_path, Map.get(options, :model_path))

    case deps.service_client_module.create_lora_training_client(service, training_opts) do
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

  defp save_weights(training, options, deps, config, _base_model) do
    save_opts = build_save_options(options, config)

    case deps.training_client_module.save_weights_for_sampler(training, save_opts) do
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

  defp parse([]), do: {:help, global_help()}
  defp parse(["--help"]), do: {:help, global_help()}
  defp parse(["-h"]), do: {:help, global_help()}
  defp parse(["--version" | rest]), do: parse_command(:version, rest)
  defp parse(["checkpoint" | rest]), do: parse_command(:checkpoint, rest)
  defp parse(["run" | rest]), do: parse_command(:run, rest)
  defp parse(["version" | rest]), do: parse_command(:version, rest)

  defp parse([unknown | _rest]) do
    {:error, "Unknown command: #{unknown}\n\n" <> global_help()}
  end

  defp parse_command(:checkpoint, argv) do
    parse_subcommand(:checkpoint, argv, checkpoint_switches(), &checkpoint_help/0)
  end

  defp parse_command(:run, argv) do
    parse_subcommand(:run, argv, run_switches(), &run_help/0)
  end

  defp parse_command(:version, argv) do
    parse_subcommand(:version, argv, version_switches(), &version_help/0)
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

  defp current_version do
    case :application.get_key(:tinkex, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _ -> "unknown"
    end
  end

  defp format_options(options) do
    options
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{inspect(value)}" end)
    |> case do
      "" -> "none"
      formatted -> formatted
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
      checkpoint   Manage checkpoints (Phase 7B)
      run          Generate text with a sampling client (Phase 7C)
      version      Show version information

    Run `tinkex <command> --help` for command-specific options.
    """
  end

  defp checkpoint_help do
    """
    Usage:
      tinkex checkpoint [options]

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

  defp run_help do
    """
    Usage:
      tinkex run [options]

    Options:
      --base-model <id>       Base model identifier
      --model-path <path>     Local model path
      --prompt <text>         Prompt text
      --prompt-file <path>    Path to file containing prompt text
      --max-tokens <int>      Maximum tokens to generate
      --temperature <float>   Sampling temperature
      --top-k <int>           Top-k sampling parameter
      --top-p <float>         Nucleus sampling parameter
      --num-samples <int>     Number of samples to return
      --api-key <key>         API key
      --base-url <url>        API base URL
      --timeout <ms>          Request timeout in milliseconds
      --http-pool <name>      HTTP pool name to use
      --json                  Output JSON (reserved)
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
      json: :boolean
    ]
  end

  defp version_switches do
    [
      help: :boolean,
      json: :boolean,
      deps: :boolean
    ]
  end

  defp aliases do
    [h: :help]
  end
end
