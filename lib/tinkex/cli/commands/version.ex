defmodule Tinkex.CLI.Commands.Version do
  @moduledoc """
  Version command to display version information.
  """

  @doc """
  Runs the version command with the given options.
  """
  @spec run_version(map(), map()) :: {:ok, map()} | {:error, term()}
  def run_version(options, overrides \\ %{}) do
    deps = version_deps(overrides)
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

  defp version_deps(overrides) do
    env_overrides = Application.get_env(:tinkex, :cli_version_deps, %{}) || %{}

    %{
      app_module: Application,
      system_module: System,
      json_module: Jason
    }
    |> Map.merge(env_overrides)
    |> Map.merge(overrides)
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
end
