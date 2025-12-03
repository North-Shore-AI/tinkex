defmodule Tinkex.Config do
  @moduledoc """
  Client configuration for the Tinkex SDK.

  Instances of this struct are passed through every API call to support
  multi-tenant usage (different API keys, base URLs, timeouts, and retry policies
  within the same BEAM VM). Construction is the only place where we consult
  `Application.get_env/3`; the request hot path only works with the struct that
  callers provide.
  """

  require Logger
  alias Tinkex.Env

  @enforce_keys [:base_url, :api_key]
  defstruct base_url: nil,
            api_key: nil,
            http_pool: Tinkex.HTTP.Pool,
            http_client: Tinkex.API,
            timeout: nil,
            max_retries: nil,
            user_metadata: nil,
            tags: nil,
            feature_gates: nil,
            telemetry_enabled?: nil,
            log_level: nil,
            cf_access_client_id: nil,
            cf_access_client_secret: nil,
            dump_headers?: nil,
            proxy: nil,
            proxy_headers: [],
            default_headers: %{},
            default_query: %{}

  @type proxy ::
          {:http | :https, host :: String.t(), port :: 1..65535, opts :: keyword()} | nil

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t(),
          http_pool: atom(),
          http_client: module(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          user_metadata: map() | nil,
          tags: [String.t()] | nil,
          feature_gates: [String.t()] | nil,
          telemetry_enabled?: boolean(),
          log_level: :debug | :info | :warn | :error | nil,
          cf_access_client_id: String.t() | nil,
          cf_access_client_secret: String.t() | nil,
          dump_headers?: boolean(),
          proxy: proxy(),
          proxy_headers: [{String.t(), String.t()}],
          default_headers: map(),
          default_query: map()
        }

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"

  # Elixir/BEAM conservative defaults
  @default_timeout 120_000
  @default_max_retries 2

  # Python SDK parity defaults (tinker/_constants.py)
  @python_timeout 60_000
  @python_max_retries 10

  @doc """
  Build a config struct using runtime options + application/env defaults.

  `max_retries` is the number of additional attempts after the initial request.
  With the default of 2, the SDK will perform up to three total attempts.

  ## Parity Mode

  By default, Tinkex uses BEAM-conservative defaults:
    * `timeout: 120_000` (2 minutes)
    * `max_retries: 2` (3 total attempts)

  To match Python SDK defaults, enable parity mode:

      # Via options
      config = Tinkex.Config.new(parity_mode: :python)

      # Via application config
      config :tinkex, parity_mode: :python

      # Via environment variable
      export TINKEX_PARITY=python

  Python parity mode sets:
    * `timeout: 60_000` (1 minute)
    * `max_retries: 10` (11 total attempts)

  Explicit timeout/max_retries options always override parity defaults.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    env = Env.snapshot()

    # Determine parity mode: opts > app config > env
    parity_mode = determine_parity_mode(opts, env)
    {default_timeout, default_max_retries} = defaults_for_parity(parity_mode)

    api_key =
      pick([
        opts[:api_key],
        Application.get_env(:tinkex, :api_key),
        env.api_key
      ])

    base_url =
      pick(
        [
          opts[:base_url],
          Application.get_env(:tinkex, :base_url),
          env.base_url
        ],
        @default_base_url
      )

    http_pool =
      pick(
        [opts[:http_pool], Application.get_env(:tinkex, :http_pool), env.http_pool],
        Tinkex.HTTP.Pool
      )

    http_client =
      pick(
        [opts[:http_client], Application.get_env(:tinkex, :http_client), env.http_client],
        Tinkex.API
      )

    timeout = pick([opts[:timeout], Application.get_env(:tinkex, :timeout)], default_timeout)

    max_retries =
      pick([opts[:max_retries], Application.get_env(:tinkex, :max_retries)], default_max_retries)

    tags =
      pick(
        [opts[:tags], Application.get_env(:tinkex, :tags)],
        default_tags(env.tags)
      )

    feature_gates =
      pick(
        [opts[:feature_gates], Application.get_env(:tinkex, :feature_gates)],
        env.feature_gates
      )

    telemetry_enabled? =
      pick(
        [
          opts[:telemetry_enabled?],
          Application.get_env(:tinkex, :telemetry_enabled?)
        ],
        env.telemetry_enabled?
      )

    log_level =
      pick(
        [opts[:log_level], Application.get_env(:tinkex, :log_level)],
        env.log_level
      )

    cf_access_client_id =
      pick(
        [opts[:cf_access_client_id], Application.get_env(:tinkex, :cf_access_client_id)],
        env.cf_access_client_id
      )

    cf_access_client_secret =
      pick(
        [opts[:cf_access_client_secret], Application.get_env(:tinkex, :cf_access_client_secret)],
        env.cf_access_client_secret
      )

    dump_headers? =
      pick(
        [
          opts[:dump_headers?],
          Application.get_env(:tinkex, :dump_headers?)
        ],
        env.dump_headers?
      )

    default_headers =
      [
        opts[:default_headers],
        Application.get_env(:tinkex, :default_headers),
        env.default_headers
      ]
      |> pick(%{})
      |> normalize_string_map!(:default_headers)

    default_query =
      [opts[:default_query], Application.get_env(:tinkex, :default_query), env.default_query]
      |> pick(%{})
      |> normalize_string_map!(:default_query)

    {proxy, derived_proxy_headers} =
      pick([
        opts[:proxy],
        Application.get_env(:tinkex, :proxy),
        env.proxy
      ])
      |> parse_proxy()

    proxy_headers =
      pick(
        [
          opts[:proxy_headers],
          Application.get_env(:tinkex, :proxy_headers),
          env.proxy_headers
        ],
        []
      )
      |> default_proxy_headers(derived_proxy_headers)

    config = %__MODULE__{
      base_url: base_url,
      api_key: api_key,
      http_pool: http_pool,
      http_client: http_client,
      timeout: timeout,
      max_retries: max_retries,
      user_metadata: opts[:user_metadata],
      tags: tags,
      feature_gates: feature_gates,
      telemetry_enabled?: telemetry_enabled?,
      log_level: log_level,
      cf_access_client_id: cf_access_client_id,
      cf_access_client_secret: cf_access_client_secret,
      dump_headers?: dump_headers?,
      proxy: proxy,
      proxy_headers: proxy_headers,
      default_headers: default_headers,
      default_query: default_query
    }

    # Fail fast on malformed URLs so pool creation does not explode deeper in the stack.
    _ = Tinkex.PoolKey.normalize_base_url(config.base_url)

    validate!(config)
  end

  @doc """
  Validate an existing config struct.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    unless config.api_key do
      raise ArgumentError,
            "api_key is required. Pass :api_key option or set TINKER_API_KEY env var"
    end

    unless config.base_url do
      raise ArgumentError, "base_url is required in config"
    end

    unless is_atom(config.http_pool) do
      raise ArgumentError, "http_pool must be an atom, got: #{inspect(config.http_pool)}"
    end

    unless valid_http_client?(config.http_client) do
      raise ArgumentError,
            "http_client must implement Tinkex.HTTPClient callbacks, got: #{inspect(config.http_client)}"
    end

    unless is_integer(config.timeout) and config.timeout > 0 do
      raise ArgumentError, "timeout must be a positive integer, got: #{inspect(config.timeout)}"
    end

    unless is_integer(config.max_retries) and config.max_retries >= 0 do
      raise ArgumentError,
            "max_retries must be a non-negative integer, got: #{inspect(config.max_retries)}"
    end

    unless is_list(config.tags) do
      raise ArgumentError, "tags must be a list of strings, got: #{inspect(config.tags)}"
    end

    unless is_list(config.feature_gates) do
      raise ArgumentError,
            "feature_gates must be a list of strings, got: #{inspect(config.feature_gates)}"
    end

    unless is_boolean(config.telemetry_enabled?) do
      raise ArgumentError,
            "telemetry_enabled? must be boolean, got: #{inspect(config.telemetry_enabled?)}"
    end

    unless is_boolean(config.dump_headers?) do
      raise ArgumentError,
            "dump_headers? must be boolean, got: #{inspect(config.dump_headers?)}"
    end

    unless config.log_level in [nil, :debug, :info, :warn, :error] do
      raise ArgumentError, "log_level must be one of :debug | :info | :warn | :error | nil"
    end

    validate_proxy!(config.proxy)
    validate_proxy_headers!(config.proxy_headers)
    validate_default_headers!(config.default_headers)
    validate_default_query!(config.default_query)

    maybe_warn_about_base_url(config)
    config
  end

  defp maybe_warn_about_base_url(%__MODULE__{} = config) do
    if Application.get_env(:tinkex, :suppress_base_url_warning, false) do
      :ok
    else
      app_base = Application.get_env(:tinkex, :base_url, @default_base_url)

      with {:ok, config_normalized} <- {:ok, Tinkex.PoolKey.normalize_base_url(config.base_url)},
           {:ok, app_normalized} <- {:ok, Tinkex.PoolKey.normalize_base_url(app_base)},
           true <- config_normalized != app_normalized do
        Logger.warning("""
        Config base_url (#{config_normalized}) differs from Application config (#{app_normalized}).
        Requests will use Finch's default pool, not the tuned pools configured in Tinkex.Application.
        For production multi-tenant scenarios, configure dedicated Finch pools per base URL.
        """)
      else
        _ -> :ok
      end
    end
  end

  @doc false
  @spec mask_api_key(String.t() | nil) :: String.t() | nil
  def mask_api_key(nil), do: nil

  def mask_api_key(api_key) when is_binary(api_key) do
    case String.length(api_key) do
      len when len <= 4 ->
        String.duplicate("*", len)

      len ->
        prefix = String.slice(api_key, 0, min(6, len - 2))
        suffix = String.slice(api_key, -4, 4)
        "#{prefix}...#{suffix}"
    end
  end

  def mask_api_key(other), do: other

  @doc false
  @spec redact_headers(map()) :: map()
  def redact_headers(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      if secret_header?(key) do
        Map.put(acc, key, Env.mask_secret(value))
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp secret_header?(key) do
    downcased = key |> to_string() |> String.downcase()
    downcased in ["x-api-key", "cf-access-client-secret", "authorization", "proxy-authorization"]
  end

  defp pick(values, default \\ nil) do
    case Enum.find(values, &(!is_nil(&1))) do
      nil -> default
      value -> value
    end
  end

  defp normalize_string_map!(value, field) do
    case normalize_string_map(value) do
      {:ok, map} ->
        map

      {:error, reason} ->
        raise ArgumentError, "#{field} #{reason}"
    end
  end

  defp normalize_string_map(nil), do: {:ok, %{}}

  defp normalize_string_map(map) when is_map(map) do
    reduce_string_map(map)
  rescue
    e in ArgumentError -> {:error, e.message}
  end

  defp normalize_string_map(list) when is_list(list) do
    if Enum.all?(list, &match?({_, _}, &1)) do
      reduce_string_map(Map.new(list))
    else
      {:error, "must be a map or keyword list, got: #{inspect(list)}"}
    end
  rescue
    e in ArgumentError -> {:error, e.message}
  end

  defp normalize_string_map(other),
    do: {:error, "must be a map or keyword list, got: #{inspect(other)}"}

  defp reduce_string_map(map) do
    result =
      Enum.reduce(map, %{}, fn
        {_k, nil}, acc ->
          acc

        {k, v}, acc ->
          key = normalize_string_key(k)
          value = normalize_string_value(v)
          Map.put(acc, key, value)
      end)

    {:ok, result}
  end

  defp normalize_string_key(key) do
    key
    |> to_string()
    |> String.trim()
    |> case do
      "" -> raise ArgumentError, "must use non-empty string keys"
      value -> value
    end
  end

  defp normalize_string_value(value) when is_binary(value), do: value
  defp normalize_string_value(value) when is_number(value), do: to_string(value)
  defp normalize_string_value(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_string_value(value) do
    raise ArgumentError, "must use string-able values, got: #{inspect(value)}"
  end

  defp default_tags([]), do: ["tinkex-elixir"]
  defp default_tags(tags) when is_list(tags), do: tags

  # Parity mode helpers

  defp determine_parity_mode(opts, env) do
    pick([
      opts[:parity_mode],
      Application.get_env(:tinkex, :parity_mode),
      parse_parity_env(env)
    ])
  end

  defp parse_parity_env(%{parity_mode: mode}) when mode in [:python, "python"], do: :python
  defp parse_parity_env(_), do: nil

  defp defaults_for_parity(:python), do: {@python_timeout, @python_max_retries}
  defp defaults_for_parity(_), do: {@default_timeout, @default_max_retries}

  # Proxy parsing and validation

  defp parse_proxy(nil), do: {nil, []}

  defp parse_proxy({scheme, host, port, opts} = proxy)
       when scheme in [:http, :https] and is_binary(host) and is_integer(port) and
              is_list(opts) do
    {proxy, []}
  end

  defp parse_proxy(url) when is_binary(url) do
    uri = URI.parse(url)

    scheme =
      case uri.scheme do
        "http" ->
          :http

        "https" ->
          :https

        nil ->
          raise ArgumentError,
                "proxy must be a URL string or {:http | :https, host, port, opts} tuple, got: #{inspect(url)}"

        other ->
          raise ArgumentError, "proxy URL scheme must be http or https, got: #{other}"
      end

    host = uri.host || raise ArgumentError, "proxy URL must have a host"
    port = uri.port || default_port_for_scheme(scheme)

    # Extract auth from userinfo and convert to proxy-authorization header
    proxy_headers =
      case uri.userinfo do
        nil ->
          []

        userinfo ->
          encoded = Base.encode64(userinfo)
          [{"proxy-authorization", "Basic #{encoded}"}]
      end

    {{scheme, host, port, []}, proxy_headers}
  end

  defp parse_proxy(other) do
    raise ArgumentError,
          "proxy must be a URL string or {:http | :https, host, port, opts} tuple, got: #{inspect(other)}"
  end

  defp default_proxy_headers([], derived) when is_list(derived) and derived != [], do: derived
  defp default_proxy_headers(headers, _derived), do: headers

  defp default_port_for_scheme(:http), do: 80
  defp default_port_for_scheme(:https), do: 443

  defp validate_proxy!(nil), do: :ok

  defp validate_proxy!({scheme, host, port, opts})
       when scheme in [:http, :https] and is_binary(host) and is_integer(port) and
              port in 1..65535 and is_list(opts) do
    :ok
  end

  defp validate_proxy!(proxy) do
    raise ArgumentError,
          "proxy must be {:http | :https, host, port, opts} with port in 1..65535, got: #{inspect(proxy)}"
  end

  defp validate_proxy_headers!(headers) when is_list(headers) do
    unless Enum.all?(headers, &valid_header?/1) do
      raise ArgumentError,
            "proxy_headers must be a list of {name, value} tuples with string values"
    end

    :ok
  end

  defp validate_proxy_headers!(other) do
    raise ArgumentError, "proxy_headers must be a list, got: #{inspect(other)}"
  end

  defp valid_header?({name, value}) when is_binary(name) and is_binary(value), do: true
  defp valid_header?(_), do: false

  defp validate_default_headers!(headers) when is_map(headers), do: :ok

  defp validate_default_headers!(other) do
    raise ArgumentError,
          "default_headers must be a map or keyword list with string-able values, got: #{inspect(other)}"
  end

  defp validate_default_query!(headers) when is_map(headers), do: :ok

  defp validate_default_query!(other) do
    raise ArgumentError,
          "default_query must be a map or keyword list with string-able values, got: #{inspect(other)}"
  end

  defp valid_http_client?(client) when is_atom(client) do
    Code.ensure_loaded?(client) and function_exported?(client, :post, 3) and
      function_exported?(client, :get, 2) and function_exported?(client, :delete, 2)
  end

  defp valid_http_client?(_), do: false

  @doc """
  Return BEAM-conservative default timeout (120s).
  """
  @spec default_timeout() :: pos_integer()
  def default_timeout, do: @default_timeout

  @doc """
  Return BEAM-conservative default max_retries (2).
  """
  @spec default_max_retries() :: non_neg_integer()
  def default_max_retries, do: @default_max_retries

  @doc """
  Return Python SDK parity timeout (60s).
  """
  @spec python_timeout() :: pos_integer()
  def python_timeout, do: @python_timeout

  @doc """
  Return Python SDK parity max_retries (10).
  """
  @spec python_max_retries() :: non_neg_integer()
  def python_max_retries, do: @python_max_retries
end

defimpl Inspect, for: Tinkex.Config do
  import Inspect.Algebra
  alias Tinkex.Env

  def inspect(config, opts) do
    data =
      config
      |> Map.from_struct()
      |> Map.update(:api_key, nil, &Tinkex.Config.mask_api_key/1)
      |> Map.update(:cf_access_client_secret, nil, &Env.mask_secret/1)
      |> Map.update(:default_headers, %{}, &Tinkex.Config.redact_headers/1)

    concat(["#Tinkex.Config<", to_doc(data, opts), ">"])
  end
end
