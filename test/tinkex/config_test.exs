defmodule Tinkex.ConfigTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Config

  defmodule StubHTTPClient do
    @behaviour Tinkex.HTTPClient

    def post(_path, _body, _opts), do: {:ok, %{}}
    def get(_path, _opts), do: {:ok, %{}}
    def delete(_path, _opts), do: {:ok, %{}}
  end

  describe "new/1" do
    test "creates config with defaults" do
      config = Config.new(api_key: "tml-test-key")

      assert config.api_key == "tml-test-key"
      assert config.base_url =~ "tinker.thinkingmachines.dev"
      assert config.timeout == 60_000
      assert config.max_retries == 10
      assert config.poll_backoff == nil
      assert config.http_pool == Tinkex.HTTP.Pool
      assert config.http_client == Tinkex.API
      assert config.tags == ["tinkex-elixir"]
      assert config.feature_gates == ["async_sampling"]
      refute config.telemetry_enabled?
      refute config.dump_headers?
      assert config.default_headers == %{}
      assert config.default_query == %{}
      assert config.recovery == nil
    end

    test "overrides defaults with options" do
      with_base_url("https://staging.example.com", fn ->
        config =
          Config.new(
            api_key: "tml-test-key",
            base_url: "https://staging.example.com",
            timeout: 60_000,
            max_retries: 5
          )

        assert config.base_url == "https://staging.example.com"
        assert config.timeout == 60_000
        assert config.max_retries == 5
      end)
    end

    test "accepts custom http_pool" do
      config = Config.new(api_key: "tml-test-key", http_pool: :custom_pool)
      assert config.http_pool == :custom_pool
    end

    test "accepts user_metadata" do
      config = Config.new(api_key: "tml-test-key", user_metadata: %{user_id: "123"})
      assert config.user_metadata == %{user_id: "123"}
    end

    test "normalizes recovery policy maps" do
      config = Config.new(api_key: "tml-test-key", recovery: %{enabled: true, max_attempts: 5})

      assert %Tinkex.Recovery.Policy{enabled: true, max_attempts: 5} = config.recovery
    end

    test "uses env and app config precedence" do
      System.put_env("TINKER_API_KEY", "tml-env-key")
      Application.put_env(:tinkex, :api_key, "tml-app-key")

      config = Config.new(api_key: "tml-opt-key")
      assert config.api_key == "tml-opt-key"

      Application.delete_env(:tinkex, :api_key)
      config = Config.new()
      assert config.api_key == "tml-env-key"

      System.delete_env("TINKER_API_KEY")
    end

    test "applies opts > app config > env > defaults for shared fields" do
      env_snapshot =
        snapshot_env(
          ~w[TINKER_API_KEY TINKER_BASE_URL TINKER_TELEMETRY TINKER_LOG TINKEX_DUMP_HEADERS TINKEX_DEFAULT_HEADERS TINKEX_DEFAULT_QUERY TINKEX_HTTP_CLIENT TINKEX_HTTP_POOL TINKEX_POLL_BACKOFF]
        )

      app_snapshot =
        snapshot_app([
          :api_key,
          :base_url,
          :telemetry_enabled?,
          :log_level,
          :dump_headers?,
          :default_headers,
          :default_query,
          :http_client,
          :http_pool,
          :poll_backoff
        ])

      on_exit(fn ->
        restore_env(env_snapshot)
        restore_app(app_snapshot)
      end)

      System.put_env("TINKER_API_KEY", "tml-env-key")
      System.put_env("TINKER_BASE_URL", "https://env.example.com/base")
      System.put_env("TINKER_TELEMETRY", "1")
      System.put_env("TINKER_LOG", "debug")
      System.put_env("TINKEX_DUMP_HEADERS", "1")
      System.put_env("TINKEX_DEFAULT_HEADERS", ~s({"x-env":"1"}))
      System.put_env("TINKEX_DEFAULT_QUERY", ~s({"env":"1"}))
      System.put_env("TINKEX_HTTP_CLIENT", "Tinkex.API")
      System.put_env("TINKEX_HTTP_POOL", "env_pool")
      System.put_env("TINKEX_POLL_BACKOFF", "exponential")

      Application.put_env(:tinkex, :api_key, "tml-app-key")
      Application.put_env(:tinkex, :base_url, "https://app.example.com/base")
      Application.put_env(:tinkex, :telemetry_enabled?, false)
      Application.put_env(:tinkex, :log_level, :warn)
      Application.put_env(:tinkex, :dump_headers?, false)
      Application.put_env(:tinkex, :default_headers, %{"x-app" => "1"})
      Application.put_env(:tinkex, :default_query, %{"app" => "1"})
      Application.put_env(:tinkex, :http_client, StubHTTPClient)
      Application.put_env(:tinkex, :http_pool, :app_pool)
      Application.put_env(:tinkex, :poll_backoff, :none)

      config = Config.new()
      assert config.api_key == "tml-app-key"
      assert config.base_url == "https://app.example.com/base"
      refute config.telemetry_enabled?
      assert config.log_level == :warn
      refute config.dump_headers?
      assert config.default_headers == %{"x-app" => "1"}
      assert config.default_query == %{"app" => "1"}
      assert config.http_client == StubHTTPClient
      assert config.http_pool == :app_pool
      assert config.poll_backoff == :none

      config =
        Config.new(
          api_key: "tml-opt-key",
          base_url: "https://opt.example.com/base",
          telemetry_enabled?: true,
          log_level: :error,
          dump_headers?: true,
          default_headers: %{"x-opt" => "1"},
          default_query: %{"opt" => "1"},
          http_client: Tinkex.API,
          http_pool: :opt_pool,
          poll_backoff: :exponential
        )

      assert config.api_key == "tml-opt-key"
      assert config.base_url == "https://opt.example.com/base"
      assert config.telemetry_enabled?
      assert config.log_level == :error
      assert config.dump_headers?
      assert config.default_headers == %{"x-opt" => "1"}
      assert config.default_query == %{"opt" => "1"}
      assert config.http_client == Tinkex.API
      assert config.http_pool == :opt_pool
      assert config.poll_backoff == :exponential

      Application.delete_env(:tinkex, :api_key)
      Application.delete_env(:tinkex, :base_url)
      Application.delete_env(:tinkex, :telemetry_enabled?)
      Application.delete_env(:tinkex, :log_level)
      Application.delete_env(:tinkex, :dump_headers?)
      Application.delete_env(:tinkex, :default_headers)
      Application.delete_env(:tinkex, :default_query)
      Application.delete_env(:tinkex, :http_client)
      Application.delete_env(:tinkex, :http_pool)
      Application.delete_env(:tinkex, :poll_backoff)

      config = Config.new()
      assert config.api_key == "tml-env-key"
      assert config.base_url == "https://env.example.com/base"
      assert config.telemetry_enabled?
      assert config.log_level == :debug
      assert config.dump_headers?
      assert config.default_headers == %{"x-env" => "1"}
      assert config.default_query == %{"env" => "1"}
      assert config.http_client == Tinkex.API
      assert config.http_pool == :env_pool
      assert config.poll_backoff == :exponential
    end

    test "feature_gates default to async_sampling with precedence" do
      env_snapshot = snapshot_env(~w[TINKER_FEATURE_GATES])
      app_snapshot = snapshot_app([:feature_gates])

      on_exit(fn ->
        restore_env(env_snapshot)
        restore_app(app_snapshot)
      end)

      System.delete_env("TINKER_FEATURE_GATES")
      Application.delete_env(:tinkex, :feature_gates)

      default_config = Config.new(api_key: "tml-key")
      assert default_config.feature_gates == ["async_sampling"]

      System.put_env("TINKER_FEATURE_GATES", "env1,env2")
      env_config = Config.new(api_key: "tml-key")
      assert env_config.feature_gates == ["env1", "env2"]

      Application.put_env(:tinkex, :feature_gates, ["app"])
      app_config = Config.new(api_key: "tml-key")
      assert app_config.feature_gates == ["app"]

      opt_config = Config.new(api_key: "tml-key", feature_gates: [])
      assert opt_config.feature_gates == []
    end

    test "pulls cloudflare credentials from env" do
      System.put_env("TINKER_API_KEY", "tml-key")
      System.put_env("CLOUDFLARE_ACCESS_CLIENT_ID", "cf-id")
      System.put_env("CLOUDFLARE_ACCESS_CLIENT_SECRET", "cf-secret")

      config = Config.new()

      assert config.cf_access_client_id == "cf-id"
      assert config.cf_access_client_secret == "cf-secret"

      System.delete_env("CLOUDFLARE_ACCESS_CLIENT_ID")
      System.delete_env("CLOUDFLARE_ACCESS_CLIENT_SECRET")
      System.delete_env("TINKER_API_KEY")
    end

    test "raises without api_key" do
      without_api_key_sources(fn ->
        assert_raise ArgumentError, ~r/api_key is required/, fn ->
          Config.new([])
        end
      end)
    end

    test "raises with invalid timeout" do
      assert_raise ArgumentError, ~r/timeout must be a positive integer/, fn ->
        Config.new(api_key: "tml-key", timeout: -1)
      end
    end

    test "raises with invalid max_retries" do
      assert_raise ArgumentError, ~r/max_retries must be a non-negative integer/, fn ->
        Config.new(api_key: "tml-key", max_retries: -1)
      end
    end

    test "normalizes default headers and query" do
      config =
        Config.new(
          api_key: "tml-key",
          default_headers: [foo: 1, bar: :baz],
          default_query: %{limit: 10, mode: :fast}
        )

      assert config.default_headers == %{"bar" => "baz", "foo" => "1"}
      assert config.default_query == %{"limit" => "10", "mode" => "fast"}
    end

    test "validates http_client modules" do
      assert_raise ArgumentError, ~r/http_client must implement/, fn ->
        Config.new(api_key: "tml-key", http_client: String)
      end
    end
  end

  describe "validate!/1" do
    test "returns config if valid" do
      with_base_url("https://example.com", fn ->
        config = %Config{
          api_key: "tml-key",
          base_url: "https://example.com",
          http_pool: :pool,
          timeout: 1_000,
          max_retries: 2,
          user_metadata: nil,
          tags: [],
          feature_gates: [],
          telemetry_enabled?: false,
          log_level: nil,
          cf_access_client_id: nil,
          cf_access_client_secret: nil,
          dump_headers?: false
        }

        assert Config.validate!(config) == config
      end)
    end

    test "raises if api_key is nil" do
      with_base_url("https://example.com", fn ->
        config = %Config{
          api_key: nil,
          base_url: "https://example.com",
          http_pool: :pool,
          timeout: 1_000,
          max_retries: 2,
          user_metadata: nil
        }

        assert_raise ArgumentError, ~r/api_key is required/, fn ->
          Config.validate!(config)
        end
      end)
    end

    test "raises if api_key is missing 'tml-' prefix" do
      with_base_url("https://example.com", fn ->
        config = %Config{
          api_key: "not-prefixed",
          base_url: "https://example.com",
          http_pool: :pool,
          timeout: 1_000,
          max_retries: 2,
          user_metadata: nil,
          tags: [],
          feature_gates: [],
          telemetry_enabled?: false,
          log_level: nil,
          cf_access_client_id: nil,
          cf_access_client_secret: nil,
          dump_headers?: false
        }

        assert_raise ArgumentError, ~r/api_key must start with the 'tml-' prefix/, fn ->
          Config.validate!(config)
        end
      end)
    end
  end

  describe "mask_api_key/1" do
    test "masks long keys" do
      assert Config.mask_api_key("tml-abcdef123456") == "tml-ab...3456"
    end

    test "replaces short keys with asterisks" do
      assert Config.mask_api_key("abcd") == "****"
    end
  end

  describe "Inspect implementation" do
    test "hides raw api key" do
      config = Config.new(api_key: "tml-abcdef123456")
      inspected = inspect(config)

      refute inspected =~ "tml-abcdef123456"
      assert inspected =~ "tml-ab...3456"
    end

    test "hides cloudflare secret" do
      config =
        Config.new(
          api_key: "tml-key",
          cf_access_client_secret: "super-secret"
        )

      inspected = inspect(config)
      refute inspected =~ "super-secret"
      assert inspected =~ "[REDACTED]"
    end
  end

  defp snapshot_env(keys) do
    Enum.into(keys, %{}, fn key -> {key, System.get_env(key)} end)
  end

  defp restore_env(snapshot) do
    Enum.each(snapshot, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)
  end

  defp snapshot_app(keys) do
    Enum.into(keys, %{}, fn key -> {key, Application.get_env(:tinkex, key)} end)
  end

  defp restore_app(snapshot) do
    Enum.each(snapshot, fn
      {key, nil} -> Application.delete_env(:tinkex, key)
      {key, value} -> Application.put_env(:tinkex, key, value)
    end)
  end

  defp without_api_key_sources(fun) when is_function(fun, 0) do
    prev_app_key = Application.get_env(:tinkex, :api_key)
    prev_env_key = System.get_env("TINKER_API_KEY")

    Application.delete_env(:tinkex, :api_key)
    System.delete_env("TINKER_API_KEY")

    on_exit(fn ->
      if prev_app_key do
        Application.put_env(:tinkex, :api_key, prev_app_key)
      else
        Application.delete_env(:tinkex, :api_key)
      end

      if prev_env_key do
        System.put_env("TINKER_API_KEY", prev_env_key)
      else
        System.delete_env("TINKER_API_KEY")
      end
    end)

    fun.()
  end

  defp with_base_url(base_url, fun) when is_function(fun, 0) do
    previous = Application.get_env(:tinkex, :base_url)
    Application.put_env(:tinkex, :base_url, base_url)

    on_exit(fn ->
      if previous do
        Application.put_env(:tinkex, :base_url, previous)
      else
        Application.delete_env(:tinkex, :base_url)
      end
    end)

    fun.()
  end
end
