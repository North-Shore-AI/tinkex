defmodule Tinkex.CLI do
  @moduledoc """
  Command-line interface entrypoint for the Tinkex escript.

  `main/1` is a thin wrapper over `run/1` so the CLI can be tested without halting
  the VM. The checkpoint command drives the Service/Training client flow to save
  weights; the run command remains scaffolded for the next phase.
  """

  alias Tinkex.CLI.Commands.{Checkpoint, Run, Sample, Version}
  alias Tinkex.CLI.Parser

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
    case Parser.parse(argv) do
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
    Version.run_version(options)
  end

  @doc false
  @spec run_sampling(map(), map()) :: {:ok, map()} | {:error, term()}
  def run_sampling(options, overrides \\ %{}) when is_map(options) and is_map(overrides) do
    Sample.run_sampling(options, overrides)
  end

  @doc false
  @spec run_checkpoint(map(), map()) :: {:ok, map()} | {:error, term()}
  def run_checkpoint(options, overrides \\ %{}) when is_map(options) and is_map(overrides) do
    Checkpoint.run_checkpoint(options, overrides)
  end

  @doc false
  @spec run_checkpoint_management(atom(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_checkpoint_management(action, options, overrides \\ %{}) do
    Checkpoint.run_checkpoint_management(action, options, overrides)
  end

  @doc false
  @spec run_run_management(atom(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_run_management(action, options, overrides \\ %{}) do
    Run.run_run_management(action, options, overrides)
  end
end
