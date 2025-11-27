defmodule Tinkex.Files.AsyncReaderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.AsyncReader

  @fixture_dir "test/fixtures/async_files"

  setup do
    File.mkdir_p!(@fixture_dir)
    on_exit(fn -> File.rm_rf!(@fixture_dir) end)
    :ok
  end

  describe "read_file_content_async/1" do
    test "reads binary as-is in Task" do
      content = <<1, 2, 3, 4>>
      task = AsyncReader.read_file_content_async(content)
      assert {:ok, ^content} = Task.await(task)
    end

    test "reads from file path asynchronously" do
      path = Path.join(@fixture_dir, "async.txt")
      File.write!(path, "Async content")

      task = AsyncReader.read_file_content_async(path)
      assert {:ok, "Async content"} = Task.await(task)
    end

    test "handles multiple concurrent reads" do
      paths =
        Enum.map(1..5, fn i ->
          path = Path.join(@fixture_dir, "file_#{i}.txt")
          File.write!(path, "Content #{i}")
          path
        end)

      tasks = Enum.map(paths, &AsyncReader.read_file_content_async/1)
      results = Task.await_many(tasks)

      assert length(results) == 5
      assert Enum.all?(results, fn {:ok, content} -> String.starts_with?(content, "Content ") end)
    end
  end
end
