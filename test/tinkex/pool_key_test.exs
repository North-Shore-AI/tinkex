defmodule Tinkex.PoolKeyTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.PoolKey

  describe "normalize_base_url/1" do
    test "removes standard HTTPS port" do
      assert PoolKey.normalize_base_url("https://example.com:443") ==
               "https://example.com"
    end

    test "removes standard HTTP port" do
      assert PoolKey.normalize_base_url("http://example.com:80") ==
               "http://example.com"
    end

    test "preserves non-standard ports" do
      assert PoolKey.normalize_base_url("https://example.com:8443") ==
               "https://example.com:8443"
    end

    test "handles URLs without port" do
      assert PoolKey.normalize_base_url("https://example.com") ==
               "https://example.com"
    end

    test "downcases host for case-insensitive matching" do
      assert PoolKey.normalize_base_url("https://EXAMPLE.COM") ==
               "https://example.com"

      assert PoolKey.normalize_base_url("https://Example.Com:8080") ==
               "https://example.com:8080"
    end

    test "raises on bare host without scheme" do
      assert_raise ArgumentError, ~r/invalid base_url/, fn ->
        PoolKey.normalize_base_url("example.com")
      end
    end

    test "raises on invalid URL without host" do
      assert_raise ArgumentError, ~r/invalid base_url/, fn ->
        PoolKey.normalize_base_url("https://")
      end
    end

    test "raises on completely invalid URL" do
      assert_raise ArgumentError, ~r/invalid base_url/, fn ->
        PoolKey.normalize_base_url("not-a-url")
      end
    end
  end

  describe "build/2" do
    test "creates tuple for training pool" do
      assert PoolKey.build("https://example.com:443", :training) ==
               {{:https, "example.com", 443}, :training}
    end

    test "creates tuple for default pool" do
      assert PoolKey.build("https://example.com", :default) ==
               {{:https, "example.com", 443}, :default}
    end

    test "creates tuple for sampling pool" do
      assert PoolKey.build("https://EXAMPLE.COM", :sampling) ==
               {{:https, "example.com", 443}, :sampling}
    end

    test "normalizes URL in pool key" do
      assert PoolKey.build("https://example.com:443", :futures) ==
               {{:https, "example.com", 443}, :futures}
    end
  end

  describe "pool_name/3" do
    test "derives deterministic pool names" do
      base = :tinkex_pool
      base_url = "https://Example.com:443/path"
      expected = :"#{base}.session.#{:erlang.phash2(PoolKey.normalize_base_url(base_url))}"

      assert PoolKey.pool_name(base, base_url, :session) == expected
    end

    test "resolve_pool_name falls back to base when typed pool is missing" do
      base = :tinkex_pool
      base_url = "https://example.com"

      resolved = PoolKey.resolve_pool_name(base, base_url, :training)
      assert resolved == base

      typed = PoolKey.pool_name(base, base_url, :training)
      {:ok, pid} = Agent.start_link(fn -> :ok end, name: typed)

      assert PoolKey.resolve_pool_name(base, base_url, :training) == typed
      Agent.stop(pid)
    end
  end
end
