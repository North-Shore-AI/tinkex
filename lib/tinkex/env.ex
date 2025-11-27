defmodule Tinkex.Env do
  @moduledoc """
  Centralized environment variable access for Tinkex.

  Normalizes values, applies defaults, and provides helpers for redaction so
  callers avoid scattered `System.get_env/1` usage.
  """

  @truthy ~w(1 true yes on)
  @falsey ~w(0 false no off)

  @type env_source :: :system | %{optional(String.t()) => String.t()}

  @doc """
  Snapshot all known env-driven values in one map.
  """
  @spec snapshot(env_source()) :: map()
  def snapshot(env \\ :system) do
    %{
      api_key: api_key(env),
      base_url: base_url(env),
      tags: tags(env),
      feature_gates: feature_gates(env),
      telemetry_enabled?: telemetry_enabled?(env),
      log_level: log_level(env),
      cf_access_client_id: cf_access_client_id(env),
      cf_access_client_secret: cf_access_client_secret(env),
      dump_headers?: dump_headers?(env),
      parity_mode: parity_mode(env),
      pool_size: pool_size(env),
      pool_count: pool_count(env)
    }
  end

  @spec api_key(env_source()) :: String.t() | nil
  def api_key(env \\ :system), do: env |> fetch("TINKER_API_KEY") |> normalize()

  @spec base_url(env_source()) :: String.t() | nil
  def base_url(env \\ :system), do: env |> fetch("TINKER_BASE_URL") |> normalize()

  @spec cf_access_client_id(env_source()) :: String.t() | nil
  def cf_access_client_id(env \\ :system),
    do: env |> fetch("CLOUDFLARE_ACCESS_CLIENT_ID") |> normalize()

  @spec cf_access_client_secret(env_source()) :: String.t() | nil
  def cf_access_client_secret(env \\ :system),
    do: env |> fetch("CLOUDFLARE_ACCESS_CLIENT_SECRET") |> normalize()

  @spec tags(env_source()) :: [String.t()]
  def tags(env \\ :system), do: env |> fetch("TINKER_TAGS") |> split_list()

  @spec feature_gates(env_source()) :: [String.t()]
  def feature_gates(env \\ :system), do: env |> fetch("TINKER_FEATURE_GATES") |> split_list()

  @spec telemetry_enabled?(env_source()) :: boolean()
  def telemetry_enabled?(env \\ :system) do
    env
    |> fetch("TINKER_TELEMETRY")
    |> normalize()
    |> normalize_bool(default: true)
  end

  @spec dump_headers?(env_source()) :: boolean()
  def dump_headers?(env \\ :system) do
    env
    |> fetch("TINKEX_DUMP_HEADERS")
    |> normalize()
    |> normalize_bool(default: false)
  end

  @spec log_level(env_source()) :: :debug | :info | :warn | :error | nil
  def log_level(env \\ :system) do
    env
    |> fetch("TINKER_LOG")
    |> normalize()
    |> case do
      nil -> nil
      value -> parse_log_level(value)
    end
  end

  @doc """
  Get parity mode from environment.

  Set `TINKEX_PARITY=python` to use Python SDK defaults for timeout and retries.
  """
  @spec parity_mode(env_source()) :: :python | nil
  def parity_mode(env \\ :system) do
    env
    |> fetch("TINKEX_PARITY")
    |> normalize()
    |> parse_parity_mode()
  end

  @doc """
  Get HTTP pool size from environment.

  Python SDK uses `max_connections=1000` by default.
  Set `TINKEX_POOL_SIZE` to override.
  """
  @spec pool_size(env_source()) :: pos_integer() | nil
  def pool_size(env \\ :system) do
    env
    |> fetch("TINKEX_POOL_SIZE")
    |> normalize()
    |> parse_positive_integer()
  end

  @doc """
  Get HTTP pool count from environment.

  Set `TINKEX_POOL_COUNT` to override the number of connection pools.
  """
  @spec pool_count(env_source()) :: pos_integer() | nil
  def pool_count(env \\ :system) do
    env
    |> fetch("TINKEX_POOL_COUNT")
    |> normalize()
    |> parse_positive_integer()
  end

  defp parse_positive_integer(nil), do: nil

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_parity_mode(nil), do: nil
  defp parse_parity_mode("python"), do: :python
  defp parse_parity_mode("Python"), do: :python
  defp parse_parity_mode("PYTHON"), do: :python
  defp parse_parity_mode(_), do: nil

  @doc """
  Redact secrets in a snapshot or map using simple replacement.
  """
  @spec redact(map()) :: map()
  def redact(map) when is_map(map) do
    map
    |> maybe_update(:api_key, &mask_secret/1)
    |> maybe_update(:cf_access_client_secret, &mask_secret/1)
  end

  @doc """
  Replace a secret with a constant marker.
  """
  @spec mask_secret(term()) :: term()
  def mask_secret(nil), do: nil
  def mask_secret(value) when is_binary(value), do: "[REDACTED]"
  def mask_secret(other), do: other

  defp split_list(nil), do: []

  defp split_list(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize(nil), do: nil

  defp normalize(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize(_other), do: nil

  defp normalize_bool(nil, default: default), do: default

  defp normalize_bool(value, default: default) when is_binary(value) do
    downcased = String.downcase(value)

    cond do
      downcased in @truthy -> true
      downcased in @falsey -> false
      true -> default
    end
  end

  defp normalize_bool(_other, default: default), do: default

  defp parse_log_level(value) do
    case String.downcase(value) do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warn
      "warning" -> :warn
      "error" -> :error
      _ -> nil
    end
  end

  defp fetch(:system, key), do: System.get_env(key)
  defp fetch(env, key) when is_map(env), do: Map.get(env, key)
  defp fetch(_env, _key), do: nil

  defp maybe_update(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end
end
