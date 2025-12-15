defmodule Tinkex.EnvTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Env

  test "snapshot normalizes values" do
    env = %{
      "TINKER_API_KEY" => " api ",
      "TINKER_BASE_URL" => "https://example.com/ ",
      "TINKER_TAGS" => "tag1, tag2, ,tag3",
      "TINKER_FEATURE_GATES" => "async_sampling,other",
      "TINKER_TELEMETRY" => "0",
      "TINKER_LOG" => "Warning",
      "CLOUDFLARE_ACCESS_CLIENT_ID" => "cf-id",
      "CLOUDFLARE_ACCESS_CLIENT_SECRET" => "cf-secret",
      "TINKEX_DUMP_HEADERS" => "1",
      "TINKEX_DEFAULT_HEADERS" => ~s({"Authorization":"Bearer token","x-extra":"1"}),
      "TINKEX_DEFAULT_QUERY" => ~s({"mode":"fast","flag":true}),
      "TINKEX_HTTP_CLIENT" => "Tinkex.API",
      "TINKEX_HTTP_POOL" => "custom_pool"
    }

    snapshot = Env.snapshot(env)

    assert snapshot.api_key == "api"
    assert snapshot.base_url == "https://example.com/"
    assert snapshot.tags == ["tag1", "tag2", "tag3"]
    assert snapshot.feature_gates == ["async_sampling", "other"]
    refute snapshot.telemetry_enabled?
    assert snapshot.log_level == :warn
    assert snapshot.cf_access_client_id == "cf-id"
    assert snapshot.cf_access_client_secret == "cf-secret"
    assert snapshot.dump_headers?
    assert snapshot.default_headers == %{"Authorization" => "Bearer token", "x-extra" => "1"}
    assert snapshot.default_query == %{"flag" => "true", "mode" => "fast"}
    assert snapshot.http_client == Tinkex.API
    assert snapshot.http_pool == :custom_pool
  end

  test "defaults and blank values" do
    env = %{
      "TINKER_API_KEY" => " ",
      "TINKER_TELEMETRY" => "maybe",
      "TINKEX_DUMP_HEADERS" => "",
      "TINKER_FEATURE_GATES" => " "
    }

    assert Env.api_key(env) == nil
    assert Env.base_url(env) == nil
    assert Env.tags(env) == []
    assert Env.feature_gates(env) == ["async_sampling"]
    assert Env.telemetry_enabled?(env)
    refute Env.dump_headers?(env)
  end

  test "boolean parsing accepts common truthy/falsey values" do
    true_env = %{"TINKER_TELEMETRY" => "YES", "TINKEX_DUMP_HEADERS" => "on"}
    false_env = %{"TINKER_TELEMETRY" => "false", "TINKEX_DUMP_HEADERS" => "0"}

    assert Env.telemetry_enabled?(true_env)
    assert Env.dump_headers?(true_env)
    refute Env.telemetry_enabled?(false_env)
    refute Env.dump_headers?(false_env)
  end

  test "log level parsing normalizes supported values" do
    assert Env.log_level(%{"TINKER_LOG" => "DEBUG"}) == :debug
    assert Env.log_level(%{"TINKER_LOG" => "warn"}) == :warn
    assert Env.log_level(%{"TINKER_LOG" => "error"}) == :error
    assert Env.log_level(%{"TINKER_LOG" => "unknown"}) == nil
    assert Env.log_level(%{}) == nil
  end

  test "redacts secrets in snapshots" do
    snapshot = %{
      api_key: "tml-abc",
      cf_access_client_secret: "secret",
      default_headers: %{"Authorization" => "Bearer token", "x-extra" => "1"},
      tags: ["a"]
    }

    redacted = Env.redact(snapshot)
    assert redacted.api_key == "[REDACTED]"
    assert redacted.cf_access_client_secret == "[REDACTED]"
    assert redacted.default_headers == %{"Authorization" => "[REDACTED]", "x-extra" => "1"}
    assert redacted.tags == ["a"]
  end

  test "snapshot defaults feature_gates to async_sampling when unset" do
    snapshot = Env.snapshot(%{})
    assert snapshot.feature_gates == ["async_sampling"]
  end

  describe "parity_mode/1" do
    test "returns :python for TINKEX_PARITY=python" do
      assert Env.parity_mode(%{"TINKEX_PARITY" => "python"}) == :python
      assert Env.parity_mode(%{"TINKEX_PARITY" => "Python"}) == :python
      assert Env.parity_mode(%{"TINKEX_PARITY" => "PYTHON"}) == :python
    end

    test "returns nil for missing or empty value" do
      assert Env.parity_mode(%{}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => ""}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => " "}) == nil
    end

    test "returns nil for unknown values" do
      assert Env.parity_mode(%{"TINKEX_PARITY" => "java"}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => "rust"}) == nil
      assert Env.parity_mode(%{"TINKEX_PARITY" => "1"}) == nil
    end

    test "is included in snapshot" do
      env = %{"TINKEX_PARITY" => "python"}
      snapshot = Env.snapshot(env)
      assert snapshot.parity_mode == :python
    end
  end
end
