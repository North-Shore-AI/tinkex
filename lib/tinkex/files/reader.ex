defmodule Tinkex.Files.Reader do
  @moduledoc """
  Synchronous helpers for reading file inputs and extracting metadata.
  """

  alias Tinkex.Files.Types

  @spec read_file_content(Types.file_content()) ::
          {:ok, binary()} | {:error, File.posix() | :invalid_file_content}
  def read_file_content(%File.Stream{} = stream) do
    try do
      {:ok, stream |> Enum.to_list() |> IO.iodata_to_binary()}
    rescue
      _ -> {:error, :invalid_file_content}
    end
  end

  def read_file_content(content) when is_binary(content) do
    if file_path_candidate?(content) do
      read_path(content)
    else
      {:ok, content}
    end
  end

  def read_file_content(content) when is_list(content) do
    try do
      {:ok, IO.iodata_to_binary(content)}
    rescue
      _ -> {:error, :invalid_file_content}
    end
  end

  def read_file_content(_other), do: {:error, :invalid_file_content}

  @spec read_file_content!(Types.file_content()) :: binary() | no_return()
  def read_file_content!(content) do
    case read_file_content(content) do
      {:ok, data} -> data
      {:error, reason} -> raise "Failed to read file content: #{inspect(reason)}"
    end
  end

  @spec extract_filename(Types.file_content()) :: String.t() | nil
  def extract_filename({filename, _content}) when is_binary(filename) or is_nil(filename),
    do: filename

  def extract_filename({filename, _content, _content_type})
      when is_binary(filename) or is_nil(filename),
      do: filename

  def extract_filename({filename, _content, _content_type, _headers})
      when is_binary(filename) or is_nil(filename),
      do: filename

  def extract_filename(content) when is_binary(content) do
    if file_path_candidate?(content) do
      Path.basename(content)
    else
      nil
    end
  end

  def extract_filename(_), do: nil

  defp read_path(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        {:error, :eisdir}

      {:ok, %File.Stat{type: :regular}} ->
        File.read(path)

      {:ok, %File.Stat{}} ->
        File.read(path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp file_path_candidate?(content) when is_binary(content) do
    File.exists?(content) or
      String.contains?(content, "/") or
      String.contains?(content, "\\") or
      String.starts_with?(content, ".") or
      String.starts_with?(content, "~")
  end
end
