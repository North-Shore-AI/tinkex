defmodule Tinkex.API.Compression do
  @moduledoc """
  Response compression handling for Tinkex API.

  Handles gzip decompression and content-encoding header management.
  """

  @doc """
  Decompresses a Finch response if it's gzip-encoded.

  Checks the content-encoding header and decompresses the body if it's gzip.
  Strips the content-encoding header after decompression.

  ## Examples

      iex> response = %Finch.Response{
      ...>   body: :zlib.gzip("test"),
      ...>   headers: [{"content-encoding", "gzip"}]
      ...> }
      iex> decompressed = decompress(response)
      iex> decompressed.body
      "test"
  """
  @spec decompress(Finch.Response.t()) :: Finch.Response.t()
  def decompress(%Finch.Response{} = response) do
    case normalized_header(response.headers, "content-encoding") do
      "gzip" ->
        body =
          try do
            :zlib.gunzip(response.body)
          rescue
            _ ->
              response.body
          end

        %{response | body: body, headers: strip_content_encoding(response.headers)}

      _ ->
        response
    end
  end

  # Private functions

  defp normalized_header(headers, name) do
    name_lower = String.downcase(name)

    headers
    |> Enum.find_value(fn {k, v} ->
      if String.downcase(k) == name_lower, do: String.downcase(String.trim(v))
    end)
  end

  defp strip_content_encoding(headers) do
    Enum.reject(headers, fn {name, _} -> String.downcase(name) == "content-encoding" end)
  end
end
