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
    uri = parse_base_url(url)
    normalized_host = String.downcase(uri.host)
    port = normalize_port(uri.scheme, uri.port)
    "#{uri.scheme}://#{normalized_host}#{port}"
  end

  @doc """
  Convert a base URL into a Finch destination tuple `{scheme, host, port}`.
  """
  @spec destination(String.t()) :: {:http | :https, String.t(), pos_integer()}
  def destination(url) when is_binary(url) do
    uri = parse_base_url(url)
    scheme = uri.scheme |> String.downcase() |> String.to_atom()
    port = uri.port || default_port(scheme)
    {scheme, String.downcase(uri.host), port}
  end

  @doc """
  Build the Finch pool key tuple for the given base URL and pool type.
  """
  @spec build(String.t(), atom()) :: {:http | :https, String.t(), pos_integer()}
  def build(base_url, pool_type) when is_atom(pool_type) do
    _ = pool_type
    destination(base_url)
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

  defp default_port(:http), do: 80
  defp default_port(:https), do: 443
  defp default_port(_), do: 80
end
