defmodule Tinkex.Version do
  @moduledoc false

  @version Mix.Project.config()[:version]
  @tinker_sdk_version Mix.Project.config()[:tinker_sdk_version] ||
                        raise("tinker_sdk_version must be set in mix.exs project config")

  @spec current() :: String.t()
  def current, do: @version

  @spec tinker_sdk() :: String.t()
  def tinker_sdk, do: @tinker_sdk_version
end
