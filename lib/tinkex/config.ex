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

  @enforce_keys [:base_url, :api_key]
  defstruct [
    :base_url,
    :api_key,
    :http_pool,
    :timeout,
    :max_retries,
    :user_metadata
  ]

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t(),
          http_pool: atom(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          user_metadata: map() | nil
        }

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_timeout 120_000
  @default_max_retries 2

  @doc """
  Build a config struct using runtime options + application/env defaults.

  `max_retries` is the number of additional attempts after the initial request.
  With the default of 2, the SDK will perform up to three total attempts.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    api_key =
      opts[:api_key] ||
        Application.get_env(:tinkex, :api_key) ||
        System.get_env("TINKER_API_KEY")

    base_url =
      opts[:base_url] ||
        Application.get_env(:tinkex, :base_url, @default_base_url)

    http_pool = opts[:http_pool] || Application.get_env(:tinkex, :http_pool, Tinkex.HTTP.Pool)
    timeout = opts[:timeout] || Application.get_env(:tinkex, :timeout, @default_timeout)

    max_retries =
      opts[:max_retries] || Application.get_env(:tinkex, :max_retries, @default_max_retries)

    config = %__MODULE__{
      base_url: base_url,
      api_key: api_key,
      http_pool: http_pool,
      timeout: timeout,
      max_retries: max_retries,
      user_metadata: opts[:user_metadata]
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

    unless is_integer(config.timeout) and config.timeout > 0 do
      raise ArgumentError, "timeout must be a positive integer, got: #{inspect(config.timeout)}"
    end

    unless is_integer(config.max_retries) and config.max_retries >= 0 do
      raise ArgumentError,
            "max_retries must be a non-negative integer, got: #{inspect(config.max_retries)}"
    end

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
end

defimpl Inspect, for: Tinkex.Config do
  import Inspect.Algebra

  def inspect(config, opts) do
    data =
      config
      |> Map.from_struct()
      |> Map.update(:api_key, nil, &Tinkex.Config.mask_api_key/1)

    concat(["#Tinkex.Config<", to_doc(data, opts), ">"])
  end
end
