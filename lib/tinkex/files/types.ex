defmodule Tinkex.Files.Types do
  @moduledoc """
  Type helpers and guards for file upload inputs.
  """

  @type header_kv :: {binary(), binary()}
  @type headers :: %{optional(binary()) => binary()} | [header_kv()]
  @type file_content :: binary() | Path.t() | File.Stream.t() | iodata()

  @type file_tuple ::
          {String.t() | nil, file_content()}
          | {String.t() | nil, file_content(), String.t() | nil}
          | {String.t() | nil, file_content(), String.t() | nil, headers()}

  @type file_types :: file_content | file_tuple

  @type request_files ::
          %{optional(String.t()) => file_types()}
          | [{String.t(), file_types()}]

  @spec file_content?(term()) :: boolean()
  def file_content?(%File.Stream{}), do: true

  def file_content?(content) when is_binary(content), do: true

  def file_content?(content) when is_list(content) do
    try do
      :erlang.iolist_size(content)
      true
    rescue
      _ -> false
    end
  end

  def file_content?(_), do: false

  @spec file_types?(term()) :: boolean()
  def file_types?(value) do
    cond do
      file_content?(value) ->
        true

      match?({_, _}, value) ->
        match_tuple?(value)

      match?({_, _, _}, value) ->
        match_tuple?(value)

      match?({_, _, _, _}, value) ->
        match_tuple?(value)

      true ->
        false
    end
  end

  defp match_tuple?({filename, content}) do
    (is_binary(filename) or is_nil(filename)) and file_content?(content)
  end

  defp match_tuple?({filename, content, content_type}) do
    (is_binary(filename) or is_nil(filename)) and
      (is_binary(content_type) or is_nil(content_type)) and file_content?(content)
  end

  defp match_tuple?({filename, content, content_type, headers}) do
    (is_binary(filename) or is_nil(filename)) and
      (is_binary(content_type) or is_nil(content_type)) and
      (is_map(headers) or is_list(headers)) and file_content?(content)
  end

  defp match_tuple?(_), do: false
end
