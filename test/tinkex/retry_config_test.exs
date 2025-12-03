defmodule Tinkex.RetryConfigTest do
  use ExUnit.Case, async: true

  alias Tinkex.RetryConfig

  describe "new/1" do
    test "builds with defaults" do
      config = RetryConfig.new()

      assert config.max_retries == :infinity
      assert config.base_delay_ms == 500
      assert config.max_delay_ms == 10_000
      assert config.jitter_pct == 0.25
      assert config.progress_timeout_ms == 7_200_000
      assert config.max_connections == 100
      assert config.enable_retry_logic == true
    end

    test "accepts keyword overrides" do
      config =
        RetryConfig.new(
          max_retries: 2,
          base_delay_ms: 100,
          max_delay_ms: 200,
          jitter_pct: 0.1,
          progress_timeout_ms: 5_000,
          max_connections: 5,
          enable_retry_logic: false
        )

      assert config.max_retries == 2
      assert config.base_delay_ms == 100
      assert config.max_delay_ms == 200
      assert config.jitter_pct == 0.1
      assert config.progress_timeout_ms == 5_000
      assert config.max_connections == 5
      assert config.enable_retry_logic == false
    end

    test "allows :infinity max_retries" do
      config = RetryConfig.new(max_retries: :infinity)
      assert config.max_retries == :infinity
    end
  end

  describe "validate!/1" do
    test "raises on invalid values" do
      assert_raise ArgumentError, fn -> RetryConfig.new(max_retries: -1) end
      assert_raise ArgumentError, fn -> RetryConfig.new(max_retries: :never) end
      assert_raise ArgumentError, fn -> RetryConfig.new(base_delay_ms: 0) end
      assert_raise ArgumentError, fn -> RetryConfig.new(max_delay_ms: 1) end
      assert_raise ArgumentError, fn -> RetryConfig.new(jitter_pct: -0.1) end
      assert_raise ArgumentError, fn -> RetryConfig.new(jitter_pct: 1.1) end
      assert_raise ArgumentError, fn -> RetryConfig.new(progress_timeout_ms: 0) end
      assert_raise ArgumentError, fn -> RetryConfig.new(max_connections: 0) end
      assert_raise ArgumentError, fn -> RetryConfig.new(enable_retry_logic: :nope) end
    end
  end

  describe "to_handler_opts/1" do
    test "exports options for RetryHandler" do
      config =
        RetryConfig.new(
          max_retries: 4,
          base_delay_ms: 600,
          max_delay_ms: 1200,
          jitter_pct: 0.2,
          progress_timeout_ms: 10_000
        )

      assert RetryConfig.to_handler_opts(config) == [
               max_retries: 4,
               base_delay_ms: 600,
               max_delay_ms: 1200,
               jitter_pct: 0.2,
               progress_timeout_ms: 10_000
             ]
    end
  end
end
