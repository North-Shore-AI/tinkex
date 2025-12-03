defmodule Tinkex.ApplicationTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Application
  alias Tinkex.PoolKey

  test "build_pool_map adds per-type pool specs" do
    base_url = "https://example.com"
    base_pool = :tinkex_pool
    pools = Application.build_pool_map(base_url, 50, 20, %{}, base_pool)

    destination = PoolKey.destination(base_url)

    session = Map.fetch!(pools, :session)
    training = Map.fetch!(pools, :training)
    sampling = Map.fetch!(pools, :sampling)
    futures = Map.fetch!(pools, :futures)
    telemetry = Map.fetch!(pools, :telemetry)
    default = Map.fetch!(pools, :default)

    assert session.name == PoolKey.pool_name(base_pool, base_url, :session)
    assert Keyword.fetch!(session.pools[destination], :size) == 5
    assert Keyword.fetch!(training.pools[destination], :count) == 2
    assert Keyword.fetch!(sampling.pools[destination], :size) == 50
    assert Keyword.fetch!(sampling.pools[destination], :count) == 20
    assert Keyword.fetch!(futures.pools[destination], :size) == 25
    assert Keyword.fetch!(futures.pools[destination], :count) == 10
    assert Keyword.fetch!(telemetry.pools[destination], :size) == 5
    assert default.name == base_pool
    assert Keyword.fetch!(default.pools[destination], :size) == 50
  end
end
