defmodule Tinkex.Files.TypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Types

  describe "file_content?/1" do
    test "returns true for binary" do
      assert Types.file_content?("raw bytes")
      assert Types.file_content?(<<1, 2, 3>>)
    end

    test "returns true for Path struct" do
      assert Types.file_content?(Path.expand("./mix.exs"))
    end

    test "returns false for other types" do
      refute Types.file_content?(%{})
      refute Types.file_content?([1, 2, 3, %{a: 1}])
      refute Types.file_content?(123)
    end
  end

  describe "file_types?/1" do
    test "returns true for file_content" do
      assert Types.file_types?("bytes")
    end

    test "returns true for tuple with filename" do
      assert Types.file_types?({"name.txt", "content"})
    end

    test "returns true for tuple with content-type" do
      assert Types.file_types?({"name.txt", "content", "text/plain"})
    end

    test "returns true for tuple with headers" do
      assert Types.file_types?({"name.txt", "content", "text/plain", [{"x-custom", "val"}]})
    end
  end
end
