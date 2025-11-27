defmodule Tinkex.Multipart.EncoderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Multipart.Encoder

  describe "encode/2" do
    test "encodes single file" do
      files = %{"upload" => "file content"}

      {:ok, body, content_type} = Encoder.encode_multipart(%{}, files)

      assert content_type =~ "multipart/form-data; boundary="
      assert body =~ "Content-Disposition: form-data; name=\"upload\""
      assert body =~ "file content"
    end

    test "encodes file with filename" do
      files = %{"doc" => {"readme.txt", "# README", "text/plain"}}

      {:ok, body, _} = Encoder.encode_multipart(%{}, files)

      assert body =~ "filename=\"readme.txt\""
      assert body =~ "Content-Type: text/plain"
      assert body =~ "# README"
    end

    test "encodes multiple files" do
      files = %{
        "file1" => "content1",
        "file2" => "content2"
      }

      {:ok, body, _} = Encoder.encode_multipart(%{}, files)

      assert body =~ "name=\"file1\""
      assert body =~ "name=\"file2\""
    end

    test "includes form data from body" do
      files = %{"upload" => "file content"}
      body_data = %{description: "A test file"}

      {:ok, body, _} = Encoder.encode_multipart(body_data, files)

      assert body =~ "name=\"description\""
      assert body =~ "A test file"
    end

    test "encodes file with custom headers and content-type" do
      files = %{
        "file" => {"data.bin", <<1, 2, 3>>, "application/octet-stream", %{"x-custom" => "value"}}
      }

      {:ok, body, content_type} = Encoder.encode_multipart(%{}, files)

      assert String.contains?(body, "x-custom: value")
      assert String.contains?(content_type, "boundary=")
    end

    test "properly terminates multipart body" do
      {:ok, body, content_type} = Encoder.encode_multipart(%{"a" => "1"}, %{})

      [_, boundary] = String.split(content_type, "boundary=")
      assert String.ends_with?(body, "--#{boundary}--\r\n")
    end
  end

  describe "generate_boundary/0" do
    test "generates unique boundaries" do
      b1 = Encoder.generate_boundary()
      b2 = Encoder.generate_boundary()

      assert is_binary(b1)
      assert byte_size(b1) >= 16
      assert b1 != b2
    end

    test "generates valid boundary format" do
      boundary = Encoder.generate_boundary()

      assert Regex.match?(~r/^[a-zA-Z0-9_-]+$/, boundary)
    end
  end
end
