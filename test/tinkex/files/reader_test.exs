defmodule Tinkex.Files.ReaderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Reader

  @fixture_dir "test/fixtures/reader"

  setup do
    File.mkdir_p!(@fixture_dir)
    on_exit(fn -> File.rm_rf!(@fixture_dir) end)
    :ok
  end

  describe "read_file_content/1" do
    test "passes through binary" do
      assert {:ok, "hello"} = Reader.read_file_content("hello")
      assert {:ok, <<1, 2, 3>>} = Reader.read_file_content(<<1, 2, 3>>)
    end

    test "reads file from path" do
      path = Path.join(@fixture_dir, "test_#{:rand.uniform(10_000)}.txt")
      File.write!(path, "test content")

      assert {:ok, "test content"} = Reader.read_file_content(path)
    end

    test "reads from File.Stream" do
      path = Path.join(@fixture_dir, "stream.txt")
      File.write!(path, "Line 1\nLine 2")

      stream = File.stream!(path)
      assert {:ok, "Line 1\nLine 2"} = Reader.read_file_content(stream)
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Reader.read_file_content("/nonexistent/path.txt")
    end

    test "returns error for directory path" do
      assert {:error, :eisdir} = Reader.read_file_content(@fixture_dir)
    end
  end

  describe "extract_filename/1" do
    test "extracts basename from path" do
      assert "file.txt" = Reader.extract_filename("/path/to/file.txt")
      assert "document.pdf" = Reader.extract_filename("docs/document.pdf")
    end

    test "extracts from tuple" do
      assert "custom.txt" = Reader.extract_filename({"custom.txt", "content"})
    end

    test "returns nil for binary content" do
      assert nil == Reader.extract_filename("raw bytes")
      assert nil == Reader.extract_filename(<<1, 2, 3>>)
    end
  end
end
