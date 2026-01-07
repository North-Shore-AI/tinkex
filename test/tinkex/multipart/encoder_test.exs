defmodule Tinkex.Multipart.EncoderTest do
  use ExUnit.Case, async: true

  alias Multipart
  alias Multipart.{Boundary, Encoder, Form}

  @form_opts [strategy: :bracket, list_format: :repeat, nil: :empty]

  defp encode(form_fields, files, boundary \\ nil) do
    form_parts = Form.to_parts(form_fields, @form_opts)
    file_parts = Form.to_parts(files, @form_opts)
    multipart = Multipart.new(form_parts ++ file_parts, boundary: boundary)

    {content_type, body} = Encoder.encode(multipart)

    body =
      body
      |> Encoder.to_stream()
      |> Enum.to_list()
      |> IO.iodata_to_binary()

    {content_type, body}
  end

  describe "encode/1" do
    test "encodes single file" do
      files = %{"upload" => "file content"}

      {content_type, body} = encode(%{}, files)

      assert content_type =~ "multipart/form-data; boundary="
      assert body =~ "Content-Disposition: form-data; name=\"upload\""
      assert body =~ "file content"
    end

    test "encodes file with filename" do
      files = %{"doc" => {"readme.txt", "# README", "text/plain"}}

      {_content_type, body} = encode(%{}, files)

      assert body =~ "filename=\"readme.txt\""
      assert body =~ "Content-Type: text/plain"
      assert body =~ "# README"
    end

    test "encodes multiple files" do
      files = %{
        "file1" => "content1",
        "file2" => "content2"
      }

      {_content_type, body} = encode(%{}, files)

      assert body =~ "name=\"file1\""
      assert body =~ "name=\"file2\""
    end

    test "includes form data from body" do
      files = %{"upload" => "file content"}
      body_data = %{description: "A test file"}

      {_content_type, body} = encode(body_data, files)

      assert body =~ "name=\"description\""
      assert body =~ "A test file"
    end

    test "encodes file with custom headers and content-type" do
      files = %{
        "file" => {"data.bin", <<1, 2, 3>>, "application/octet-stream", %{"x-custom" => "value"}}
      }

      {content_type, body} = encode(%{}, files)

      assert String.contains?(body, "x-custom: value")
      assert String.contains?(content_type, "boundary=")
    end

    test "properly terminates multipart body" do
      {content_type, body} = encode(%{"a" => "1"}, %{})

      [_, boundary] = String.split(content_type, "boundary=")
      assert String.ends_with?(body, "--#{boundary}--\r\n")
    end
  end

  describe "boundary generation" do
    test "generates unique boundaries" do
      b1 = Boundary.generate()
      b2 = Boundary.generate()

      assert is_binary(b1)
      assert byte_size(b1) >= 16
      assert b1 != b2
    end

    test "generates valid boundary format" do
      boundary = Boundary.generate()

      assert Regex.match?(~r/^multipart_ex-[0-9a-f]+$/, boundary)
    end
  end
end
