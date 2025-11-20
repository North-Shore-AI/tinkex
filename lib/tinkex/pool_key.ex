defmodule Tinkex.PoolKey do
  @moduledoc """
  Centralized pool key generation and URL normalization.

  Ensures every pool key follows the `{normalized_base_url, pool_type}` convention
  expected by Finch so connection pools can be tuned per host + operation type.
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
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when is_binary(scheme) and is_binary(host) and host != "" ->
        normalized_host = String.downcase(host)

        port =
          case {scheme, uri.port} do
            {"http", 80} -> ""
            {"http", nil} -> ""
            {"https", 443} -> ""
            {"https", nil} -> ""
            {_, nil} -> ""
            {_, value} -> ":#{value}"
          end

        "#{scheme}://#{normalized_host}#{port}"

      _ ->
        raise ArgumentError,
              "invalid base_url for pool key: #{inspect(url)} (must have scheme and host, e.g., 'https://api.example.com')"
    end
  end

  @doc """
  Build the Finch pool key tuple for the given base URL and pool type.
  """
  @spec build(String.t(), atom()) :: {String.t(), atom()}
  def build(base_url, pool_type) when is_atom(pool_type) do
    {normalize_base_url(base_url), pool_type}
  end
end
