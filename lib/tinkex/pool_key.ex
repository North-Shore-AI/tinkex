defmodule Tinkex.PoolKey do
  @moduledoc """
  Centralized pool key generation and URL normalization.

  Ensures every pool key follows the `{normalized_base_url, pool_type}` convention
  and derives deterministic Finch pool names per host + operation type.
  """

  @doc """
  Normalize a base URL for consistent pool keys.

  Downcases the host and strips default ports (80 for http, 443 for https). Paths
  are discarded because Finch pools connections per host, not per path.

  ## Examples

      iex> Tinkex.PoolKey.normalize_base_url("https://example.com:443")
      "https://example.com"

  """
  @spec normalize_base_url(String.t()) :: String.t()
  def normalize_base_url(url) when is_binary(url) do
    uri = parse_base_url(url)
    normalized_host = String.downcase(uri.host)
    port = normalize_port(uri.scheme, uri.port)
    "#{uri.scheme}://#{normalized_host}#{port}"
  end

  @doc """
  Normalize a base URL into a Finch destination URL string (scheme + host + port).

  Finch >= 0.20 expects pool keys as binaries (not tuples). Paths are stripped
  because connection pools are keyed per host/port, not per path.
  """
  @spec destination(String.t()) :: String.t()
  def destination(url) when is_binary(url), do: normalize_base_url(url)

  @doc """
  Build the Finch pool key tuple for the given base URL and pool type.
  """
  @spec build(String.t(), atom()) ::
          {destination :: String.t(), atom()}
  def build(base_url, pool_type) when is_atom(pool_type) do
    {destination(base_url), pool_type}
  end

  @doc """
  Derive a Finch pool name for a base pool, base URL, and pool type.

  Names are deterministic per base URL + pool type pair to ensure isolation across
  session/training/sampling/futures/telemetry pools.
  """
  @spec pool_name(atom(), String.t(), atom()) :: atom()
  def pool_name(base_pool, base_url, pool_type)
      when is_atom(base_pool) and is_atom(pool_type) and is_binary(base_url) do
    normalized = normalize_base_url(base_url)
    :"#{base_pool}.#{pool_type}.#{:erlang.phash2(normalized)}"
  end

  @doc """
  Resolve the running Finch pool for a given pool type, falling back to the base
  pool name if the typed pool has not been started.
  """
  @spec resolve_pool_name(atom(), String.t(), atom()) :: atom()
  def resolve_pool_name(base_pool, base_url, pool_type) do
    typed_name = pool_name(base_pool, base_url, pool_type)

    cond do
      Process.whereis(typed_name) ->
        typed_name

      Process.whereis(base_pool) ->
        base_pool

      true ->
        base_pool
    end
  end

  defp parse_base_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when is_binary(scheme) and is_binary(host) and host != "" ->
        uri

      _ ->
        raise ArgumentError,
              "invalid base_url for pool key: #{inspect(url)} (must have scheme and host, e.g., 'https://api.example.com')"
    end
  end

  defp normalize_port("http", 80), do: ""
  defp normalize_port("http", nil), do: ""
  defp normalize_port("https", 443), do: ""
  defp normalize_port("https", nil), do: ""
  defp normalize_port(_scheme, nil), do: ""
  defp normalize_port(_scheme, value), do: ":#{value}"
end
