defmodule Tinkex.ConfigTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Config

  describe "new/1" do
    test "creates config with defaults" do
      config = Config.new(api_key: "test-key")

      assert config.api_key == "test-key"
      assert config.base_url =~ "tinker.thinkingmachines.dev"
      assert config.timeout == 120_000
      assert config.max_retries == 2
      assert config.http_pool == Tinkex.HTTP.Pool
      assert config.tags == ["tinkex-elixir"]
      assert config.feature_gates == []
      refute config.telemetry_enabled?
      refute config.dump_headers?
    end

    test "overrides defaults with options" do
      with_base_url("https://staging.example.com", fn ->
        config =
          Config.new(
            api_key: "test-key",
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
      config = Config.new(api_key: "test-key", http_pool: :custom_pool)
      assert config.http_pool == :custom_pool
    end

    test "accepts user_metadata" do
      config = Config.new(api_key: "test-key", user_metadata: %{user_id: "123"})
      assert config.user_metadata == %{user_id: "123"}
    end

    test "uses env and app config precedence" do
      System.put_env("TINKER_API_KEY", "env-key")
      Application.put_env(:tinkex, :api_key, "app-key")

      config = Config.new(api_key: "opt-key")
      assert config.api_key == "opt-key"

      Application.delete_env(:tinkex, :api_key)
      config = Config.new()
      assert config.api_key == "env-key"

      System.delete_env("TINKER_API_KEY")
    end

    test "applies opts > app config > env > defaults for shared fields" do
      env_snapshot =
        snapshot_env(
          ~w[TINKER_API_KEY TINKER_BASE_URL TINKER_TELEMETRY TINKER_LOG TINKEX_DUMP_HEADERS]
        )

      app_snapshot =
        snapshot_app([
          :api_key,
          :base_url,
          :telemetry_enabled?,
          :log_level,
          :dump_headers?
        ])

      on_exit(fn ->
        restore_env(env_snapshot)
        restore_app(app_snapshot)
      end)

      System.put_env("TINKER_API_KEY", "env-key")
      System.put_env("TINKER_BASE_URL", "https://env.example.com/base")
      System.put_env("TINKER_TELEMETRY", "1")
      System.put_env("TINKER_LOG", "debug")
      System.put_env("TINKEX_DUMP_HEADERS", "1")

      Application.put_env(:tinkex, :api_key, "app-key")
      Application.put_env(:tinkex, :base_url, "https://app.example.com/base")
      Application.put_env(:tinkex, :telemetry_enabled?, false)
      Application.put_env(:tinkex, :log_level, :warn)
      Application.put_env(:tinkex, :dump_headers?, false)

      config = Config.new()
      assert config.api_key == "app-key"
      assert config.base_url == "https://app.example.com/base"
      refute config.telemetry_enabled?
      assert config.log_level == :warn
      refute config.dump_headers?

      config =
        Config.new(
          api_key: "opt-key",
          base_url: "https://opt.example.com/base",
          telemetry_enabled?: true,
          log_level: :error,
          dump_headers?: true
        )

      assert config.api_key == "opt-key"
      assert config.base_url == "https://opt.example.com/base"
      assert config.telemetry_enabled?
      assert config.log_level == :error
      assert config.dump_headers?

      Application.delete_env(:tinkex, :api_key)
      Application.delete_env(:tinkex, :base_url)
      Application.delete_env(:tinkex, :telemetry_enabled?)
      Application.delete_env(:tinkex, :log_level)
      Application.delete_env(:tinkex, :dump_headers?)

      config = Config.new()
      assert config.api_key == "env-key"
      assert config.base_url == "https://env.example.com/base"
      assert config.telemetry_enabled?
      assert config.log_level == :debug
      assert config.dump_headers?
    end

    test "pulls cloudflare credentials from env" do
      System.put_env("TINKER_API_KEY", "key")
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
        Config.new(api_key: "key", timeout: -1)
      end
    end

    test "raises with invalid max_retries" do
      assert_raise ArgumentError, ~r/max_retries must be a non-negative integer/, fn ->
        Config.new(api_key: "key", max_retries: -1)
      end
    end
  end

  describe "validate!/1" do
    test "returns config if valid" do
      with_base_url("https://example.com", fn ->
        config = %Config{
          api_key: "key",
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
          api_key: "key",
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
