defmodule Tinkex.Files.TransformTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Transform

  @fixture_dir "test/fixtures/transform"

  setup do
    File.mkdir_p!(@fixture_dir)
    on_exit(fn -> File.rm_rf!(@fixture_dir) end)
    :ok
  end

  describe "transform_file/1 (sync)" do
    test "passes through binary" do
      content = <<1, 2, 3>>
      assert {:ok, ^content} = Transform.transform_file(content)
    end

    test "reads file from path and extracts filename" do
      path = Path.join(@fixture_dir, "document.txt")
      File.write!(path, "File content")

      assert {:ok, {"document.txt", "File content"}} = Transform.transform_file(path)
    end

    test "processes tuple (filename, content)" do
      assert {:ok, {"custom.txt", "data"}} = Transform.transform_file({"custom.txt", "data"})
    end

    test "processes tuple (filename, path)" do
      path = Path.join(@fixture_dir, "data.bin")
      File.write!(path, <<0xFF, 0xFE>>)

      assert {:ok, {"custom_name.bin", <<0xFF, 0xFE>>}} =
               Transform.transform_file({"custom_name.bin", path})
    end

    test "processes tuple (filename, content, content_type)" do
      assert {:ok, {"file.json", "{}", "application/json"}} =
               Transform.transform_file({"file.json", "{}", "application/json"})
    end

    test "processes tuple (filename, content, content_type, headers)" do
      headers = %{"x-custom" => "value"}

      assert {:ok, {"file.txt", "text", "text/plain", ^headers}} =
               Transform.transform_file({"file.txt", "text", "text/plain", headers})
    end
  end

  describe "transform_files/1 (sync)" do
    test "transforms map of files" do
      path = Path.join(@fixture_dir, "test.txt")
      File.write!(path, "content")

      files = %{
        "file1" => <<1, 2, 3>>,
        "file2" => path,
        "file3" => {"custom.txt", "data"}
      }

      assert {:ok, transformed} = Transform.transform_files(files)
      assert is_map(transformed)
      assert transformed["file1"] == <<1, 2, 3>>
      assert transformed["file2"] == {"test.txt", "content"}
      assert transformed["file3"] == {"custom.txt", "data"}
    end

    test "transforms list of {name, file} tuples" do
      files = [
        {"field1", <<1, 2>>},
        {"field2", {"name.txt", "data"}}
      ]

      assert {:ok, [{"field1", <<1, 2>>}, {"field2", {"name.txt", "data"}}]} =
               Transform.transform_files(files)
    end

    test "returns error for invalid structure" do
      assert {:error, _} = Transform.transform_files("not a valid structure")
    end
  end
end
