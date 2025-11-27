defmodule Tinkex.Files.AsyncReader do
  @moduledoc """
  Asynchronous wrapper around `Tinkex.Files.Reader`.
  """

  alias Tinkex.Files.{Reader, Types}

  @spec read_file_content_async(Types.file_content()) :: Task.t()
  def read_file_content_async(content) do
    Task.async(fn -> Reader.read_file_content(content) end)
  end
end
