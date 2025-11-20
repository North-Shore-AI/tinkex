defmodule Tinkex.Version do
  @moduledoc false

  @version Mix.Project.config()[:version]

  @spec current() :: String.t()
  def current, do: @version
end
