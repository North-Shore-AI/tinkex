defmodule Tinkex.Ports.PoolManager do
  @moduledoc """
  Port for pool name resolution and URL normalization.
  """

  @callback normalize_base_url(String.t()) :: String.t()
  @callback destination(String.t()) :: String.t()
  @callback build(String.t(), atom()) :: {String.t(), atom()}
  @callback pool_name(atom(), String.t(), atom()) :: atom()
  @callback resolve_pool_name(atom(), String.t(), atom()) :: atom()
end
