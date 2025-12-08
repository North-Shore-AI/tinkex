defmodule Tinkex.API.URL do
  @moduledoc """
  URL building and query parameter management for Tinkex API requests.

  Handles:
  - URL construction from base URL and path
  - Query parameter normalization and merging
  - Query string encoding/decoding
  """

  @doc """
  Builds a complete URL from base URL, path, and query parameters.

  Merges query parameters in priority order (later overrides earlier):
  1. Default query from config
  2. Query parameters embedded in the path
  3. Explicit request query parameters

  ## Examples

      iex> build_url("https://api.example.com", "/v1/test", %{}, %{"key" => "value"})
      "https://api.example.com/v1/test?key=value"

      iex> build_url("https://api.example.com", "/v1/test?existing=1", %{}, %{"new" => "2"})
      "https://api.example.com/v1/test?existing=1&new=2"
  """
  @spec build_url(String.t(), String.t(), map(), map()) :: String.t()
  def build_url(base_url, path, default_query, request_query) do
    base = URI.parse(base_url)
    base_path = base.path || "/"

    {relative_path, path_query} =
      case String.split(path, "?", parts: 2) do
        [p, q] -> {p, q}
        [p] -> {p, nil}
      end

    merged_path =
      relative_path
      |> String.trim_leading("/")
      |> then(fn trimmed -> Path.join(base_path, trimmed) end)

    uri = %{base | path: merged_path}

    merged_query =
      default_query
      |> merge_query_maps(decode_query(path_query))
      |> merge_query_maps(request_query)

    uri =
      case map_size(merged_query) do
        0 -> uri
        _ -> %{uri | query: URI.encode_query(merged_query)}
      end

    URI.to_string(uri)
  end

  @doc """
  Normalizes query parameters from various input formats into a map.

  Accepts:
  - nil (returns empty map)
  - Map with string or atom keys
  - Keyword list

  Filters out nil values and ensures all keys/values are strings.

  ## Examples

      iex> normalize_query_params(nil)
      %{}

      iex> normalize_query_params(%{key: "value", nil_key: nil})
      %{"key" => "value"}

      iex> normalize_query_params([key: "value", other: 123])
      %{"key" => "value", "other" => "123"}
  """
  @spec normalize_query_params(nil | map() | keyword()) :: map()
  def normalize_query_params(nil), do: %{}

  def normalize_query_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(&normalize_query_kv/1)
    |> Map.new()
  end

  def normalize_query_params(params) when is_list(params) do
    if Enum.all?(params, &match?({_, _}, &1)) do
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(&normalize_query_kv/1)
      |> Map.new()
    else
      raise ArgumentError, "query must be a map or keyword list, got: #{inspect(params)}"
    end
  end

  def normalize_query_params(other),
    do: raise(ArgumentError, "query must be a map or keyword list, got: #{inspect(other)}")

  # Private functions

  defp decode_query(nil), do: %{}

  defp decode_query(query) when is_binary(query) do
    URI.decode_query(query)
  rescue
    _ -> %{}
  end

  defp merge_query_maps(primary, secondary) when is_map(primary) and is_map(secondary) do
    primary
    |> Map.merge(secondary, fn _k, _v1, v2 -> v2 end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp merge_query_maps(_primary, _secondary), do: %{}

  defp normalize_query_kv({key, value}) do
    normalized_key =
      key
      |> to_string()
      |> String.trim()
      |> case do
        "" -> raise ArgumentError, "query keys must be non-empty strings"
        other -> other
      end

    normalized_value =
      case value do
        v when is_binary(v) -> v
        v when is_number(v) -> to_string(v)
        v when is_atom(v) -> Atom.to_string(v)
        v -> raise ArgumentError, "query values must be string-able, got: #{inspect(v)}"
      end

    {normalized_key, normalized_value}
  end
end
