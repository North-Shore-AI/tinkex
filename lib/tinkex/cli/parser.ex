defmodule Tinkex.CLI.Parser do
  @moduledoc """
  Argument parsing helpers for the CLI.
  """

  @doc """
  Parses command-line arguments and returns the command and options.
  """
  def parse([]), do: {:help, global_help()}
  def parse(["--help"]), do: {:help, global_help()}
  def parse(["-h"]), do: {:help, global_help()}
  def parse(["--version" | rest]), do: parse_command(:version, rest)
  def parse(["checkpoint" | rest]), do: parse_checkpoint_command(rest)
  def parse(["run" | rest]), do: parse_run_command(rest)
  def parse(["version" | rest]), do: parse_command(:version, rest)

  def parse([unknown | _rest]) do
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

      action in [:info, :publish, :unpublish, :download] and length(remaining) > 1 ->
        {:error,
         unexpected_args_message(
           {:checkpoint, action},
           Enum.drop(remaining, 1),
           &checkpoint_management_help/0
         )}

      remaining != [] and action == :list ->
        {:error,
         unexpected_args_message({:checkpoint, action}, remaining, &checkpoint_management_help/0)}

      true ->
        parsed_map =
          case {action, remaining} do
            {:delete, paths} -> Map.put(parsed_map, :paths, paths)
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
      tinkex checkpoint list [--run-id <id>] [--limit <int>] [--offset <int>] [--format table|json]
      tinkex checkpoint info <tinker_path>
      tinkex checkpoint publish <tinker_path>
      tinkex checkpoint unpublish <tinker_path>
      tinkex checkpoint delete <tinker_path> [<tinker_path> ...] [--yes]
      tinkex checkpoint download <tinker_path> [--output <dir>] [--force]

    Common options:
      --api-key <key>         API key
      --base-url <url>        API base URL
      --timeout <ms>          Request timeout in milliseconds
      --format <table|json>   Output format (default: table)
      --json                  Shortcut for --format json
      -h, --help              Show this help text

    List options:
      --run-id <id>           Filter checkpoints for a single run
      --limit <int>           Maximum checkpoints to fetch (0 = all, default: 20)
      --offset <int>          Offset for pagination (default: 0)

    Delete options:
      --yes                   Skip confirmation prompt (delete is otherwise interactive)

    Download options:
      --force                 Overwrite existing files in the destination directory
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
      --limit <int>           Maximum runs to fetch (0 = all, default: 20)
      --offset <int>          Offset for pagination (default: 0)
      --format <table|json>   Output format (default: table)
      --json                  Shortcut for --format json
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
      yes: :boolean,
      api_key: :string,
      base_url: :string,
      timeout: :integer,
      limit: :integer,
      offset: :integer,
      output: :string,
      force: :boolean,
      format: :string,
      json: :boolean,
      run_id: :string
    ]
  end

  defp run_management_switches(_action) do
    [
      help: :boolean,
      api_key: :string,
      base_url: :string,
      timeout: :integer,
      limit: :integer,
      offset: :integer,
      format: :string,
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
    [h: :help, f: :format]
  end
end
