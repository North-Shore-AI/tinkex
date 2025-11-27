defmodule Tinkex.Multipart.Encoder do
  @moduledoc """
  Build multipart/form-data request bodies (Finch does not encode multipart for us).
  """

  @crlf "\r\n"

  @spec encode_multipart(map(), map() | list(), String.t() | nil) ::
          {:ok, binary(), String.t()} | {:error, term()}
  def encode_multipart(form_fields, files, boundary \\ nil)

  def encode_multipart(form_fields, files, boundary) when is_map(form_fields) do
    resolved_boundary = boundary || generate_boundary()

    with {:ok, parts} <- encode_parts(resolved_boundary, form_fields, files) do
      body = IO.iodata_to_binary([parts, "--", resolved_boundary, "--", @crlf])
      {:ok, body, "multipart/form-data; boundary=#{resolved_boundary}"}
    end
  end

  def encode_multipart(_form_fields, _files, _boundary), do: {:error, :invalid_form_fields}

  @spec generate_boundary() :: String.t()
  def generate_boundary do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp encode_parts(boundary, form_fields, files) do
    with {:ok, field_parts} <- encode_form_fields(boundary, form_fields),
         {:ok, file_parts} <- encode_files(boundary, files) do
      {:ok, [field_parts, file_parts]}
    end
  end

  defp encode_form_fields(boundary, form_fields) do
    parts =
      form_fields
      |> Enum.flat_map(fn {name, value} ->
        case value do
          list when is_list(list) ->
            Enum.map(list, &encode_field_part(boundary, name, &1))

          other ->
            [encode_field_part(boundary, name, other)]
        end
      end)

    {:ok, parts}
  end

  defp encode_files(_boundary, nil), do: {:ok, []}

  defp encode_files(boundary, files) when is_map(files) do
    parts =
      Enum.map(files, fn {name, file} ->
        encode_file_part(boundary, name, normalize_file(file))
      end)

    {:ok, parts}
  end

  defp encode_files(boundary, files) when is_list(files) do
    parts =
      Enum.map(files, fn {name, file} ->
        encode_file_part(boundary, name, normalize_file(file))
      end)

    {:ok, parts}
  end

  defp encode_files(_boundary, files), do: {:error, {:invalid_files, files}}

  defp encode_field_part(boundary, name, value) do
    [
      "--",
      boundary,
      @crlf,
      "Content-Disposition: form-data; name=\"",
      to_string(name),
      "\"",
      @crlf,
      @crlf,
      to_string(value),
      @crlf
    ]
  end

  defp encode_file_part(boundary, name, {filename, content, content_type, headers}) do
    disposition =
      case filename do
        nil ->
          ["Content-Disposition: form-data; name=\"", to_string(name), "\"", @crlf]

        _ ->
          [
            "Content-Disposition: form-data; name=\"",
            to_string(name),
            "\"; filename=\"",
            filename,
            "\"",
            @crlf
          ]
      end

    type_line = ["Content-Type: ", content_type || "application/octet-stream", @crlf]

    header_lines =
      headers
      |> Enum.map(fn {k, v} -> [to_string(k), ": ", to_string(v), @crlf] end)

    [
      "--",
      boundary,
      @crlf,
      disposition,
      type_line,
      header_lines,
      @crlf,
      content,
      @crlf
    ]
  end

  defp normalize_file({filename, content}) do
    {filename, content, nil, []}
  end

  defp normalize_file({filename, content, content_type}) do
    {filename, content, content_type, []}
  end

  defp normalize_file({filename, content, content_type, headers}) do
    {filename, content, content_type, normalize_headers(headers)}
  end

  defp normalize_file(content) do
    {nil, content, nil, []}
  end

  defp normalize_headers(headers) when is_map(headers), do: Map.to_list(headers)
  defp normalize_headers(headers) when is_list(headers), do: headers
  defp normalize_headers(_), do: []
end
