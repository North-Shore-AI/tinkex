defmodule Tinkex do
  @moduledoc """
  Documentation for `Tinkex`.
  """

  alias Tinkex.API

  @doc """
  Hello world.

  ## Examples

      iex> Tinkex.hello()
      :world

  """
  def hello do
    :world
  end

  @doc false
  def http_post(path, body, opts \\ []) do
    API.post(path, body, opts)
  end

  @doc false
  def http_get(path, opts \\ []) do
    API.get(path, opts)
  end
end
