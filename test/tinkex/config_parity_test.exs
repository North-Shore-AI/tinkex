defmodule Tinkex.ConfigParityTest do
  use ExUnit.Case, async: true

  alias Tinkex.Config

  describe "default values (no parity mode)" do
    test "uses Python defaults" do
      config = Config.new(api_key: "tml-test-key")

      assert config.timeout == Config.python_timeout()
      assert config.max_retries == Config.python_max_retries()
      assert config.timeout == 60_000
      assert config.max_retries == 10
    end
  end

  describe "parity_mode: :beam via opts" do
    test "uses BEAM-conservative defaults for timeout and max_retries" do
      config = Config.new(api_key: "tml-test-key", parity_mode: :beam)

      assert config.timeout == Config.default_timeout()
      assert config.max_retries == Config.default_max_retries()
      assert config.timeout == 120_000
      assert config.max_retries == 2
    end

    test "explicit timeout overrides parity defaults" do
      config =
        Config.new(
          api_key: "tml-test-key",
          parity_mode: :beam,
          timeout: 30_000
        )

      assert config.timeout == 30_000
      assert config.max_retries == 2
    end

    test "explicit max_retries overrides parity defaults" do
      config =
        Config.new(
          api_key: "tml-test-key",
          parity_mode: :beam,
          max_retries: 5
        )

      assert config.timeout == 120_000
      assert config.max_retries == 5
    end

    test "both explicit values override parity defaults" do
      config =
        Config.new(
          api_key: "tml-test-key",
          parity_mode: :beam,
          timeout: 45_000,
          max_retries: 3
        )

      assert config.timeout == 45_000
      assert config.max_retries == 3
    end
  end

  describe "parity_mode via application config" do
    setup do
      # Store original value
      original = Application.get_env(:tinkex, :parity_mode)
      on_exit(fn -> Application.put_env(:tinkex, :parity_mode, original) end)
      :ok
    end

    test "reads parity_mode from application config" do
      Application.put_env(:tinkex, :parity_mode, :beam)

      config = Config.new(api_key: "tml-test-key")

      assert config.timeout == 120_000
      assert config.max_retries == 2
    end

    test "opts override application config" do
      Application.put_env(:tinkex, :parity_mode, :beam)

      # No parity mode in opts should still use app config
      config1 = Config.new(api_key: "tml-test-key")
      assert config1.timeout == 120_000

      # Opts can force python parity
      config_parity = Config.new(api_key: "tml-test-key", parity_mode: :python)
      assert config_parity.timeout == 60_000
      assert config_parity.max_retries == 10

      # Explicit timeout in opts overrides
      config2 = Config.new(api_key: "tml-test-key", timeout: 90_000)
      assert config2.timeout == 90_000
    end
  end

  describe "helper functions" do
    test "python_timeout returns 60_000" do
      assert Config.python_timeout() == 60_000
    end

    test "python_max_retries returns 10" do
      assert Config.python_max_retries() == 10
    end

    test "default_timeout returns 120_000" do
      assert Config.default_timeout() == 120_000
    end

    test "default_max_retries returns 2" do
      assert Config.default_max_retries() == 2
    end
  end

  describe "unknown parity modes" do
    test "unknown parity mode falls back to python defaults" do
      config = Config.new(api_key: "tml-test-key", parity_mode: :unknown)

      assert config.timeout == 60_000
      assert config.max_retries == 10
    end

    test "nil parity mode uses python defaults" do
      config = Config.new(api_key: "tml-test-key", parity_mode: nil)

      assert config.timeout == 60_000
      assert config.max_retries == 10
    end
  end
end
