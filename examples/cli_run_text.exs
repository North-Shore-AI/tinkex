defmodule Tinkex.Examples.CLIRunText do
  @moduledoc false
  alias Tinkex.CLI

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key =
      System.get_env("TINKER_API_KEY") ||
        raise "Set TINKER_API_KEY to run this example"

    base_model = System.get_env("TINKER_BASE_MODEL", "meta-llama/Llama-3.1-8B")
    base_url = System.get_env("TINKER_BASE_URL")
    prompt = System.get_env("TINKER_PROMPT", "Hello from the CLI runner")

    max_tokens = env_integer("TINKER_MAX_TOKENS", 64)
    temperature = env_float("TINKER_TEMPERATURE", 0.7)
    num_samples = env_integer("TINKER_NUM_SAMPLES", 1)

    args =
      [
        "run",
        "--base-model",
        base_model,
        "--prompt",
        prompt,
        "--max-tokens",
        Integer.to_string(max_tokens),
        "--temperature",
        Float.to_string(temperature),
        "--num-samples",
        Integer.to_string(num_samples),
        "--api-key",
        api_key
      ]
      |> maybe_add_base_url(base_url)

    IO.puts("Running CLI with args: #{Enum.join(args, " ")}")

    case CLI.run(args) do
      {:ok, %{response: response}} ->
        IO.inspect(response, label: "sampling response")

      {:error, reason} ->
        IO.puts(:stderr, "CLI failed: #{inspect(reason)}")
    end
  end

  defp env_integer(var, default) do
    case System.get_env(var) do
      nil ->
        default

      value ->
        try do
          String.to_integer(value)
        rescue
          _ -> default
        end
    end
  end

  defp env_float(var, default) do
    case System.get_env(var) do
      nil ->
        default

      value ->
        try do
          String.to_float(value)
        rescue
          _ -> default
        end
    end
  end

  defp maybe_add_base_url(args, nil), do: args
  defp maybe_add_base_url(args, ""), do: args
  defp maybe_add_base_url(args, url), do: args ++ ["--base-url", url]
end

Tinkex.Examples.CLIRunText.run()
