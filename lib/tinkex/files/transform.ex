defmodule Tinkex.Files.Transform do
  @moduledoc """
  Normalize user-supplied file inputs into multipart-ready tuples.
  """

  alias Tinkex.Files.{Reader, Types}

  @type transformed_file ::
          binary()
          | {String.t() | nil, binary()}
          | {String.t() | nil, binary(), String.t() | nil}
          | {String.t() | nil, binary(), String.t() | nil, map() | list()}

  @spec transform_file(Types.file_types()) :: {:ok, transformed_file()} | {:error, term()}
  def transform_file(file) do
    cond do
      Types.file_content?(file) ->
        transform_content(file)

      match?({_, _}, file) or match?({_, _, _}, file) or match?({_, _, _, _}, file) ->
        transform_tuple(file)

      true ->
        {:error, {:invalid_file_type, file}}
    end
  end

  @spec transform_files(Types.request_files() | nil) ::
          {:ok, Types.request_files() | nil} | {:error, term()}
  def transform_files(nil), do: {:ok, nil}

  def transform_files(files) when is_map(files) do
    Enum.reduce_while(files, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case transform_file(value) do
        {:ok, transformed} ->
          {:cont, {:ok, Map.put(acc, to_string(key), transformed)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def transform_files(files) when is_list(files) do
    Enum.reduce_while(files, {:ok, []}, fn
      {name, value}, {:ok, acc} ->
        case transform_file(value) do
          {:ok, transformed} ->
            {:cont, {:ok, [{to_string(name), transformed} | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end

      _other, _acc ->
        {:halt, {:error, {:invalid_request_files, files}}}
    end)
    |> maybe_reverse_list()
  end

  def transform_files(files), do: {:error, {:invalid_request_files, files}}

  @spec transform_files_async(Types.request_files() | nil) :: Task.t()
  def transform_files_async(files) do
    Task.async(fn -> transform_files(files) end)
  end

  defp transform_content(content) do
    case Reader.read_file_content(content) do
      {:ok, data} ->
        case Reader.extract_filename(content) do
          nil -> {:ok, data}
          filename -> {:ok, {filename, data}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transform_tuple({filename, content}) do
    with {:ok, data} <- Reader.read_file_content(content) do
      {:ok, {filename, data}}
    end
  end

  defp transform_tuple({filename, content, content_type}) do
    with {:ok, data} <- Reader.read_file_content(content) do
      {:ok, {filename, data, content_type}}
    end
  end

  defp transform_tuple({filename, content, content_type, headers}) do
    with {:ok, data} <- Reader.read_file_content(content) do
      {:ok, {filename, data, content_type, headers}}
    end
  end

  defp transform_tuple(other), do: {:error, {:invalid_file_type, other}}

  defp maybe_reverse_list({:ok, list}), do: {:ok, Enum.reverse(list)}
  defp maybe_reverse_list(other), do: other
end
