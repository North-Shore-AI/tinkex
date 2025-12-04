defmodule Tinkex.Env do
  @moduledoc """
  Centralized environment variable access for Tinkex.

  ## Naming Convention
  - `TINKER_*` variables: Shared with Python SDK for cross-language compatibility
  - `TINKEX_*` variables: Elixir-specific features (pool config, debug tools)
  - `CLOUDFLARE_*` variables: Third-party service credentials

  Normalizes values, applies defaults, and provides helpers for redaction so
  callers avoid scattered `System.get_env/1` usage.
  """

  @truthy ~w(1 true yes on)
  @falsey ~w(0 false no off)
  @default_feature_gates ["async_sampling"]

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
      pool_count: pool_count(env),
      proxy: proxy(env),
      proxy_headers: proxy_headers(env),
      default_headers: default_headers(env),
      default_query: default_query(env),
      http_client: http_client(env),
      http_pool: http_pool(env)
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
  def feature_gates(env \\ :system) do
    env
    |> fetch("TINKER_FEATURE_GATES")
    |> split_list()
    |> default_feature_gates()
  end

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

  Defaults to Python parity. Set `TINKEX_PARITY=beam` to use BEAM-conservative
  defaults (`timeout: 120_000`, `max_retries: 2`), or `TINKEX_PARITY=python` to
  explicitly select Python SDK defaults (`timeout: 60_000`, `max_retries: 10`).
  """
  @spec parity_mode(env_source()) :: :python | :beam | nil
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

  @doc """
  Get proxy configuration from environment.

  Set `TINKEX_PROXY` to a URL string like "http://proxy.example.com:8080"
  or "http://user:pass@proxy.example.com:8080".
  """
  @spec proxy(env_source()) :: String.t() | nil
  def proxy(env \\ :system), do: env |> fetch("TINKEX_PROXY") |> normalize()

  @doc """
  Get proxy headers from environment.

  Set `TINKEX_PROXY_HEADERS` to a JSON array of {name, value} tuples.
  Example: `TINKEX_PROXY_HEADERS='[["proxy-authorization", "Basic abc123"]]'`
  """
  @spec proxy_headers(env_source()) :: [{String.t(), String.t()}]
  def proxy_headers(env \\ :system) do
    env
    |> fetch("TINKEX_PROXY_HEADERS")
    |> normalize()
    |> parse_proxy_headers()
  end

  @doc """
  Get default headers map from environment.

  Set `TINKEX_DEFAULT_HEADERS` to a JSON object of header name/value pairs.
  """
  @spec default_headers(env_source()) :: map()
  def default_headers(env \\ :system) do
    env
    |> fetch("TINKEX_DEFAULT_HEADERS")
    |> normalize()
    |> parse_json_map()
  end

  @doc """
  Get default query params map from environment.

  Set `TINKEX_DEFAULT_QUERY` to a JSON object of query name/value pairs.
  """
  @spec default_query(env_source()) :: map()
  def default_query(env \\ :system) do
    env
    |> fetch("TINKEX_DEFAULT_QUERY")
    |> normalize()
    |> parse_json_map()
  end

  @doc """
  Get custom HTTP client module from environment.

  Set `TINKEX_HTTP_CLIENT` to a module name (e.g., `Tinkex.API`).
  """
  @spec http_client(env_source()) :: module() | nil
  def http_client(env \\ :system) do
    env
    |> fetch("TINKEX_HTTP_CLIENT")
    |> normalize()
    |> parse_module()
  end

  @doc """
  Get HTTP pool name from environment.

  Set `TINKEX_HTTP_POOL` to an atom name (e.g., `Tinkex.HTTP.Pool`).
  """
  @spec http_pool(env_source()) :: atom() | nil
  def http_pool(env \\ :system) do
    env
    |> fetch("TINKEX_HTTP_POOL")
    |> normalize()
    |> parse_atom()
  end

  defp parse_proxy_headers(nil), do: []

  defp parse_proxy_headers(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, headers} when is_list(headers) ->
        headers
        |> Enum.map(fn
          [name, val] when is_binary(name) and is_binary(val) -> {name, val}
          {name, val} when is_binary(name) and is_binary(val) -> {name, val}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
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
  defp parse_parity_mode("beam"), do: :beam
  defp parse_parity_mode("BEAM"), do: :beam
  defp parse_parity_mode("elixir"), do: :beam
  defp parse_parity_mode("ELIXIR"), do: :beam
  defp parse_parity_mode(_), do: nil

  defp parse_json_map(nil), do: %{}

  defp parse_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) ->
        map
        |> Enum.reduce(%{}, fn
          {k, v}, acc when is_binary(k) ->
            Map.put(acc, k, normalize_value(v))

          {k, v}, acc ->
            Map.put(acc, to_string(k), normalize_value(v))
        end)

      _ ->
        %{}
    end
  end

  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value), do: to_string(value)

  defp parse_module(nil), do: nil

  defp parse_module(value) when is_binary(value) do
    trimmed = String.trim(value)

    candidate =
      if String.starts_with?(trimmed, "Elixir.") do
        trimmed
      else
        "Elixir." <> trimmed
      end

    try do
      String.to_existing_atom(candidate)
    rescue
      ArgumentError -> nil
    end
  end

  defp parse_atom(nil), do: nil

  defp parse_atom(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      nil
    else
      try do
        String.to_atom(trimmed)
      rescue
        ArgumentError -> nil
      end
    end
  end

  @doc """
  Redact secrets in a snapshot or map using simple replacement.
  """
  @spec redact(map()) :: map()
  def redact(map) when is_map(map) do
    map
    |> maybe_update(:api_key, &mask_secret/1)
    |> maybe_update(:cf_access_client_secret, &mask_secret/1)
    |> maybe_update(:default_headers, &redact_header_map/1)
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

  defp default_feature_gates([]), do: @default_feature_gates
  defp default_feature_gates(gates), do: gates

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

  defp redact_header_map(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      if secret_header?(key) do
        Map.put(acc, key, mask_secret(value))
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp redact_header_map(other), do: other

  defp secret_header?(key) do
    key
    |> to_string()
    |> String.downcase()
    |> then(
      &(&1 in ["x-api-key", "cf-access-client-secret", "authorization", "proxy-authorization"])
    )
  end
end
