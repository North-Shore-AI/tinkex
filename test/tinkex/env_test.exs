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
      "TINKEX_DUMP_HEADERS" => "1"
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
  end

  test "defaults and blank values" do
    env = %{
      "TINKER_API_KEY" => " ",
      "TINKER_TELEMETRY" => "maybe",
      "TINKEX_DUMP_HEADERS" => ""
    }

    assert Env.api_key(env) == nil
    assert Env.base_url(env) == nil
    assert Env.tags(env) == []
    assert Env.feature_gates(env) == []
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
      api_key: "abc",
      cf_access_client_secret: "secret",
      tags: ["a"]
    }

    redacted = Env.redact(snapshot)
    assert redacted.api_key == "[REDACTED]"
    assert redacted.cf_access_client_secret == "[REDACTED]"
    assert redacted.tags == ["a"]
  end
end
