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
          user_metadata: nil
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
