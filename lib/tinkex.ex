defmodule Tinkex do
  @moduledoc """
  Thin entrypoint for configuring and using the Tinkex SDK.
  """

  alias Pristine.Core.Context
  alias Tinkex.Config

  @doc """
  Build a `Tinkex.Config` from runtime options.
  """
  @spec config(keyword()) :: Config.t()
  def config(opts \\ []) do
    Config.new(opts)
  end

  @doc """
  Build a generated client from a config or keyword options.
  """
  @spec client(Config.t() | keyword()) :: Tinkex.Generated.Client.t()
  def client(%Config{} = config), do: Config.client(config)
  def client(opts) when is_list(opts), do: config(opts) |> Config.client()

  @doc """
  Build a generated client from a config plus override options.
  """
  @spec client(Config.t(), keyword()) :: Tinkex.Generated.Client.t()
  def client(%Config{} = config, opts) when is_list(opts) do
    Config.client(config, opts)
  end

  @doc """
  Build a Pristine context from a config or keyword options.
  """
  @spec context(Config.t() | keyword()) :: Context.t()
  def context(%Config{} = config), do: Config.context(config)
  def context(opts) when is_list(opts), do: config(opts) |> Config.context()

  @doc """
  Build a Pristine context from a config plus override options.
  """
  @spec context(Config.t(), keyword()) :: Context.t()
  def context(%Config{} = config, opts) when is_list(opts) do
    Config.context(config, opts)
  end
end
