defmodule Tinkex.Adapters.PoolManager do
  @moduledoc """
  Pool manager adapter backed by `Tinkex.PoolKey`.
  """

  @behaviour Tinkex.Ports.PoolManager

  alias Tinkex.PoolKey

  @impl true
  def normalize_base_url(url), do: PoolKey.normalize_base_url(url)

  @impl true
  def destination(url), do: PoolKey.destination(url)

  @impl true
  def build(base_url, pool_type), do: PoolKey.build(base_url, pool_type)

  @impl true
  def pool_name(base_pool, base_url, pool_type) do
    PoolKey.pool_name(base_pool, base_url, pool_type)
  end

  @impl true
  def resolve_pool_name(base_pool, base_url, pool_type) do
    PoolKey.resolve_pool_name(base_pool, base_url, pool_type)
  end
end
