defmodule Tinkex.CLI do
  @moduledoc """
  Command-line interface entrypoint for the Tinkex escript.

  `main/1` is a thin wrapper over `run/1` so the CLI can be tested without halting
  the VM. Each command currently logs a placeholder message while routing and
  option parsing are validated.
  """

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
    IO.puts("checkpoint command (scaffold). Parsed options: #{format_options(options)}")
    {:ok, %{command: :checkpoint, options: options}}
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
