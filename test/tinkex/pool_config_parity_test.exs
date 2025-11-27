defmodule Tinkex.PoolConfigParityTest do
  @moduledoc """
  Tests for Python SDK parity in HTTP pool configuration.

  Reference: tinker/_constants.py `DEFAULT_CONNECTION_LIMITS`
  Python uses: httpx.Limits(max_connections=1000, max_keepalive_connections=20)
  """
  use ExUnit.Case, async: true

  alias Tinkex.Application
  alias Tinkex.Env

  # Python constants from _constants.py
  @python_max_connections 1000

  describe "pool defaults (Python parity)" do
    test "default pool size * count approximates Python max_connections" do
      pool_size = Application.default_pool_size()
      pool_count = Application.default_pool_count()

      total_connections = pool_size * pool_count

      # Should match Python's max_connections=1000
      assert total_connections == @python_max_connections,
             "Expected #{@python_max_connections} total connections, got #{total_connections}"
    end

    test "default pool_size is 50" do
      assert Application.default_pool_size() == 50
    end

    test "default pool_count is 20" do
      assert Application.default_pool_count() == 20
    end
  end

  describe "Env pool configuration" do
    test "pool_size parses positive integers" do
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "100"}) == 100
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "1"}) == 1
    end

    test "pool_size returns nil for invalid values" do
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "0"}) == nil
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "-1"}) == nil
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => "abc"}) == nil
      assert Env.pool_size(%{"TINKEX_POOL_SIZE" => ""}) == nil
      assert Env.pool_size(%{}) == nil
    end

    test "pool_count parses positive integers" do
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => "10"}) == 10
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => "1"}) == 1
    end

    test "pool_count returns nil for invalid values" do
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => "0"}) == nil
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => "-1"}) == nil
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => "abc"}) == nil
      assert Env.pool_count(%{"TINKEX_POOL_COUNT" => ""}) == nil
      assert Env.pool_count(%{}) == nil
    end

    test "snapshot includes pool_size and pool_count" do
      env = %{
        "TINKEX_POOL_SIZE" => "200",
        "TINKEX_POOL_COUNT" => "5"
      }

      snapshot = Env.snapshot(env)

      assert snapshot.pool_size == 200
      assert snapshot.pool_count == 5
    end
  end
end
