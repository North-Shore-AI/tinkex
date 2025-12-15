defmodule Tinkex.API.HelpersTest do
  @moduledoc """
  Tests for raw/streaming response helpers.

  Python parity: with_raw_response and with_streaming_response
  """
  use ExUnit.Case, async: true

  alias Tinkex.API.Helpers
  alias Tinkex.Config

  describe "with_raw_response/1" do
    test "adds response: :wrapped to keyword opts" do
      opts = [config: %Config{api_key: "tml-test", base_url: "http://test"}]
      result = Helpers.with_raw_response(opts)

      assert Keyword.get(result, :response) == :wrapped
      assert Keyword.has_key?(result, :config)
    end

    test "preserves existing options" do
      opts = [
        config: %Config{api_key: "tml-test", base_url: "http://test"},
        timeout: 5000,
        max_retries: 3
      ]

      result = Helpers.with_raw_response(opts)

      assert result[:response] == :wrapped
      assert result[:timeout] == 5000
      assert result[:max_retries] == 3
    end

    test "accepts Config struct directly" do
      config = %Config{
        api_key: "tml-test",
        base_url: "http://test",
        http_pool: Tinkex.HTTP.Pool,
        timeout: 60_000,
        max_retries: 2,
        tags: [],
        feature_gates: [],
        telemetry_enabled?: true,
        dump_headers?: false
      }

      result = Helpers.with_raw_response(config)

      assert result[:response] == :wrapped
      assert result[:config] == config
    end

    test "overwrites existing response option" do
      opts = [config: %Config{api_key: "tml-test", base_url: "http://test"}, response: :stream]
      result = Helpers.with_raw_response(opts)

      assert result[:response] == :wrapped
    end
  end

  describe "with_streaming_response/1" do
    test "adds response: :stream to keyword opts" do
      opts = [config: %Config{api_key: "tml-test", base_url: "http://test"}]
      result = Helpers.with_streaming_response(opts)

      assert Keyword.get(result, :response) == :stream
      assert Keyword.has_key?(result, :config)
    end

    test "preserves existing options" do
      opts = [
        config: %Config{api_key: "tml-test", base_url: "http://test"},
        timeout: 30_000,
        event_parser: :raw
      ]

      result = Helpers.with_streaming_response(opts)

      assert result[:response] == :stream
      assert result[:timeout] == 30_000
      assert result[:event_parser] == :raw
    end

    test "accepts Config struct directly" do
      config = %Config{
        api_key: "tml-test",
        base_url: "http://test",
        http_pool: Tinkex.HTTP.Pool,
        timeout: 60_000,
        max_retries: 2,
        tags: [],
        feature_gates: [],
        telemetry_enabled?: true,
        dump_headers?: false
      }

      result = Helpers.with_streaming_response(config)

      assert result[:response] == :stream
      assert result[:config] == config
    end

    test "overwrites existing response option" do
      opts = [config: %Config{api_key: "tml-test", base_url: "http://test"}, response: :wrapped]
      result = Helpers.with_streaming_response(opts)

      assert result[:response] == :stream
    end
  end
end
