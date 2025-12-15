defmodule Tinkex.ConfigProxyTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Config

  describe "proxy configuration" do
    test "accepts proxy as tuple" do
      config = Config.new(api_key: "tml-test", proxy: {:http, "proxy.example.com", 8080, []})

      assert config.proxy == {:http, "proxy.example.com", 8080, []}
      assert config.proxy_headers == []
    end

    test "accepts proxy as URL string without auth" do
      config = Config.new(api_key: "tml-test", proxy: "http://proxy.example.com:8080")

      assert config.proxy == {:http, "proxy.example.com", 8080, []}
      assert config.proxy_headers == []
    end

    test "accepts proxy as URL string with auth" do
      config = Config.new(api_key: "tml-test", proxy: "http://user:pass@proxy.example.com:8080")

      assert config.proxy == {:http, "proxy.example.com", 8080, []}
      assert [{"proxy-authorization", "Basic dXNlcjpwYXNz"}] = config.proxy_headers
    end

    test "accepts https proxy" do
      config = Config.new(api_key: "tml-test", proxy: "https://proxy.example.com:443")

      assert config.proxy == {:https, "proxy.example.com", 443, []}
    end

    test "uses default port for http" do
      config = Config.new(api_key: "tml-test", proxy: "http://proxy.example.com")

      assert config.proxy == {:http, "proxy.example.com", 80, []}
    end

    test "uses default port for https" do
      config = Config.new(api_key: "tml-test", proxy: "https://proxy.example.com")

      assert config.proxy == {:https, "proxy.example.com", 443, []}
    end

    test "accepts nil proxy" do
      config = Config.new(api_key: "tml-test", proxy: nil)

      assert config.proxy == nil
    end

    test "proxy defaults to nil when not provided" do
      config = Config.new(api_key: "tml-test")

      assert config.proxy == nil
    end

    test "raises on invalid proxy scheme" do
      assert_raise ArgumentError, ~r/proxy URL scheme must be http or https/, fn ->
        Config.new(api_key: "tml-test", proxy: "ftp://proxy.example.com:21")
      end
    end

    test "raises on invalid proxy format" do
      assert_raise ArgumentError, ~r/proxy must be a URL string or/, fn ->
        Config.new(api_key: "tml-test", proxy: "invalid")
      end
    end

    test "raises on proxy tuple with invalid scheme" do
      assert_raise ArgumentError, ~r/proxy must be/, fn ->
        Config.new(api_key: "tml-test", proxy: {:ftp, "proxy.example.com", 21, []})
      end
    end

    test "raises on proxy tuple with invalid port" do
      assert_raise ArgumentError, ~r/proxy must be/, fn ->
        Config.new(api_key: "tml-test", proxy: {:http, "proxy.example.com", 0, []})
      end

      assert_raise ArgumentError, ~r/proxy must be/, fn ->
        Config.new(api_key: "tml-test", proxy: {:http, "proxy.example.com", 99999, []})
      end
    end
  end

  describe "proxy_headers configuration" do
    test "accepts valid proxy headers" do
      headers = [{"proxy-authorization", "Basic abc123"}]
      config = Config.new(api_key: "tml-test", proxy_headers: headers)

      assert config.proxy_headers == headers
    end

    test "accepts empty proxy headers list" do
      config = Config.new(api_key: "tml-test", proxy_headers: [])

      assert config.proxy_headers == []
    end

    test "proxy_headers defaults to empty list" do
      config = Config.new(api_key: "tml-test")

      assert config.proxy_headers == []
    end

    test "raises on invalid proxy headers format" do
      assert_raise ArgumentError, ~r/proxy_headers must be a list/, fn ->
        Config.new(api_key: "tml-test", proxy_headers: "invalid")
      end
    end

    test "raises on proxy headers with non-string values" do
      assert_raise ArgumentError, ~r/proxy_headers must be a list of/, fn ->
        Config.new(api_key: "tml-test", proxy_headers: [{"name", 123}])
      end
    end

    test "raises on proxy headers with invalid tuple format" do
      assert_raise ArgumentError, ~r/proxy_headers must be a list of/, fn ->
        Config.new(api_key: "tml-test", proxy_headers: ["invalid"])
      end
    end
  end

  describe "proxy from environment" do
    test "reads proxy from TINKEX_PROXY env var" do
      System.put_env("TINKEX_PROXY", "http://env-proxy.example.com:3128")

      config = Config.new(api_key: "tml-test")

      assert config.proxy == {:http, "env-proxy.example.com", 3128, []}

      System.delete_env("TINKEX_PROXY")
    end

    test "proxy option overrides environment" do
      System.put_env("TINKEX_PROXY", "http://env-proxy.example.com:3128")

      config = Config.new(api_key: "tml-test", proxy: "http://opt-proxy.example.com:8080")

      assert config.proxy == {:http, "opt-proxy.example.com", 8080, []}

      System.delete_env("TINKEX_PROXY")
    end

    test "proxy option overrides application config" do
      Application.put_env(:tinkex, :proxy, {:http, "app-proxy.example.com", 9090, []})

      config = Config.new(api_key: "tml-test", proxy: "http://opt-proxy.example.com:8080")

      assert config.proxy == {:http, "opt-proxy.example.com", 8080, []}

      Application.delete_env(:tinkex, :proxy)
    end
  end

  describe "combined proxy and headers" do
    test "accepts both proxy and proxy_headers" do
      config =
        Config.new(
          api_key: "tml-test",
          proxy: "http://proxy.example.com:8080",
          proxy_headers: [{"custom-header", "value"}]
        )

      assert config.proxy == {:http, "proxy.example.com", 8080, []}
      assert config.proxy_headers == [{"custom-header", "value"}]
    end
  end
end
