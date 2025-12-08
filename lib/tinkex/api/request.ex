defmodule Tinkex.API.Request do
  @moduledoc """
  Request preparation and body encoding for Tinkex API.

  Handles:
  - JSON body encoding
  - Multipart/form-data encoding for file uploads
  - Request body preparation and validation
  - Content-type header management
  """

  alias Tinkex.Transform
  alias Tinkex.Files.Transform, as: FileTransform
  alias Tinkex.Multipart.{Encoder, FormSerializer}
  alias Tinkex.API.Headers

  @doc """
  Prepares the request body and updates headers as needed.

  For multipart requests (with files), encodes as multipart/form-data.
  For regular requests, encodes body as JSON.

  Returns `{:ok, headers, body}` or `{:error, reason}`.
  """
  @spec prepare_body(term(), [{String.t(), String.t()}], term(), keyword()) ::
          {:ok, [{String.t(), String.t()}], iodata()} | {:error, term()}
  def prepare_body(body, headers, files, transform_opts) do
    if multipart_request?(files, headers) do
      prepare_multipart_body(body, headers, files, transform_opts)
    else
      {:ok, headers, encode_json_body(body, transform_opts)}
    end
  end

  @doc """
  Formats error reasons from request preparation into human-readable messages.
  """
  @spec format_error(term()) :: String.t()
  def format_error({:invalid_multipart_body, :binary}),
    do: "multipart body must be a map or keyword list"

  def format_error({:invalid_multipart_body, value}),
    do: "multipart body must be a map, got: #{inspect(value)}"

  def format_error({:invalid_request_files, value}),
    do: "invalid files option #{inspect(value)}"

  def format_error({:invalid_file_type, value}),
    do: "invalid file input #{inspect(value)}"

  def format_error(reason), do: inspect(reason)

  # Private functions

  defp multipart_request?(files, headers) do
    files_present?(files) or header_multipart?(headers)
  end

  defp files_present?(files) when is_map(files), do: map_size(files) > 0
  defp files_present?(files) when is_list(files), do: files != []
  defp files_present?(_), do: false

  defp header_multipart?(headers) do
    case Headers.get_normalized(headers, "content-type") do
      nil -> false
      content_type -> String.contains?(content_type, "multipart/form-data")
    end
  end

  defp prepare_multipart_body(body, headers, files, transform_opts) do
    with {:ok, normalized_files} <- FileTransform.transform_files(files),
         {:ok, form_fields} <- serialize_form_body(body, transform_opts),
         {:ok, multipart_body, content_type} <-
           Encoder.encode_multipart(
             form_fields,
             normalized_files || %{},
             extract_multipart_boundary(headers)
           ) do
      {:ok, Headers.put(headers, "content-type", content_type), multipart_body}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp serialize_form_body(nil, _transform_opts), do: {:ok, %{}}

  defp serialize_form_body(body, _transform_opts) when is_binary(body) do
    {:error, {:invalid_multipart_body, :binary}}
  end

  defp serialize_form_body(body, transform_opts) do
    transformed = Transform.transform(body, transform_opts)

    cond do
      is_nil(transformed) -> {:ok, %{}}
      is_map(transformed) -> {:ok, FormSerializer.serialize_form_fields(transformed)}
      transformed == %{} -> {:ok, %{}}
      true -> {:error, {:invalid_multipart_body, transformed}}
    end
  end

  defp extract_multipart_boundary(headers) do
    case header_multipart?(headers) do
      false ->
        nil

      true ->
        headers
        |> Enum.find_value(fn
          {name, value} ->
            if String.downcase(name) == "content-type" do
              parse_boundary(value)
            end

          _ ->
            nil
        end)
    end
  end

  defp parse_boundary(content_type) do
    segments =
      content_type
      |> String.split(";")
      |> Enum.map(&String.trim/1)

    Enum.find_value(segments, fn segment ->
      if String.starts_with?(String.downcase(segment), "boundary=") do
        [_key, value] = String.split(segment, "=", parts: 2)
        String.trim(value, "\"")
      end
    end)
  end

  defp encode_json_body(body, _transform_opts) when is_binary(body), do: body

  defp encode_json_body(body, transform_opts) do
    body
    |> Transform.transform(transform_opts)
    |> Jason.encode!()
  end
end
