defmodule Tinkex.Examples.CLIRunPromptFile do
  @moduledoc false
  alias Tinkex.CLI

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key =
      System.get_env("TINKER_API_KEY") ||
        raise "Set TINKER_API_KEY to run this example"

    base_model = System.get_env("TINKER_BASE_MODEL", "Qwen/Qwen2.5-7B")
    base_url = System.get_env("TINKER_BASE_URL")

    prompt_content =
      System.get_env("TINKER_PROMPT_TOKENS") ||
        System.get_env("TINKER_PROMPT", "Hello from a prompt file")

    tmp_dir = System.tmp_dir!()
    prompt_path = Path.join(tmp_dir, "tinkex_prompt_#{System.unique_integer([:positive])}.txt")
    output_path = Path.join(tmp_dir, "tinkex_output_#{System.unique_integer([:positive])}.json")

    File.write!(prompt_path, prompt_content)

    args =
      [
        "run",
        "--base-model",
        base_model,
        "--prompt-file",
        prompt_path,
        "--json",
        "--output",
        output_path,
        "--api-key",
        api_key
      ]
      |> maybe_add_base_url(base_url)

    IO.puts("Running CLI with prompt file #{prompt_path}")

    case CLI.run(args) do
      {:ok, %{response: _resp}} ->
        IO.puts("JSON output written to #{output_path}")
        IO.puts("Preview:")
        IO.puts(File.read!(output_path))

      {:error, reason} ->
        IO.puts(:stderr, "CLI failed: #{inspect(reason)}")
    end
  end

  defp maybe_add_base_url(args, nil), do: args
  defp maybe_add_base_url(args, ""), do: args
  defp maybe_add_base_url(args, url), do: args ++ ["--base-url", url]
end

Tinkex.Examples.CLIRunPromptFile.run()
