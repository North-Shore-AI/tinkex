defmodule Tinkex.Examples.FileUploadMultipart do
  @moduledoc """
  Demonstrates multipart/form-data encoding capability in Tinkex.

  This example shows how the SDK can build multipart payloads with file uploads,
  matching Python SDK parity. The multipart infrastructure supports:

  - File paths (read and encode automatically)
  - Raw binary content
  - Tuples with metadata: {filename, content}, {filename, content, content_type}
  - Nested form fields with bracket notation (foo[bar]=value)

  NOTE: The Tinker API currently has no endpoints that accept file uploads.
  This example demonstrates the SDK capability for when such endpoints are added,
  or for use with custom endpoints that accept multipart/form-data.
  """

  alias Tinkex.Files.Transform, as: FileTransform
  alias Tinkex.Multipart.{Encoder, FormSerializer}

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    file_path = resolve_file_path()
    note = System.get_env("TINKER_UPLOAD_NOTE", "Multipart demo from Tinkex")

    IO.puts("=" |> String.duplicate(60))
    IO.puts("Tinkex Multipart Encoding Demo")
    IO.puts("=" |> String.duplicate(60))

    # Step 1: Show the input file
    file_size = File.stat!(file_path).size
    IO.puts("\n[1] Input File:")
    IO.puts("    Path: #{file_path}")
    IO.puts("    Size: #{file_size} bytes")

    # Step 2: Transform files (reads path into binary, extracts filename)
    files = %{"file" => file_path}
    {:ok, normalized_files} = FileTransform.transform_files(files)

    IO.puts("\n[2] File Transformation:")
    IO.puts("    Input:  %{\"file\" => \"#{file_path}\"}")

    case normalized_files do
      %{"file" => {filename, content}} ->
        IO.puts("    Output: %{\"file\" => {\"#{filename}\", <<#{byte_size(content)} bytes>>}}")

      %{"file" => content} when is_binary(content) ->
        IO.puts("    Output: %{\"file\" => <<#{byte_size(content)} bytes>>}")

      other ->
        IO.puts("    Output: #{inspect(other)}")
    end

    # Step 3: Serialize form fields (nested maps become bracket notation)
    body = %{note: note, metadata: %{source: "tinkex", version: Tinkex.Version.current()}}
    form_fields = FormSerializer.serialize_form_fields(body)

    IO.puts("\n[3] Form Field Serialization:")
    IO.puts("    Input:  #{inspect(body)}")
    IO.puts("    Output: #{inspect(form_fields)}")

    # Step 4: Encode multipart body
    {:ok, multipart_body, content_type} = Encoder.encode_multipart(form_fields, normalized_files)

    IO.puts("\n[4] Multipart Encoding:")
    IO.puts("    Content-Type: #{content_type}")
    IO.puts("    Body size: #{byte_size(multipart_body)} bytes")

    # Show multipart structure (first 500 chars, redacting binary)
    IO.puts("\n[5] Multipart Body Preview:")
    preview = multipart_body |> String.slice(0, 500) |> String.replace(~r/[^\x20-\x7E\r\n]/, ".")
    IO.puts("    #{String.replace(preview, "\r\n", "\n    ")}")

    if byte_size(multipart_body) > 500 do
      IO.puts("    ... (#{byte_size(multipart_body) - 500} more bytes)")
    end

    # Step 5: Demonstrate API integration (optional, requires API key)
    IO.puts("\n[6] API Integration:")

    case System.get_env("TINKER_API_KEY") do
      nil ->
        IO.puts("    Skipped - TINKER_API_KEY not set")
        IO.puts("    (Set TINKER_API_KEY and TINKER_UPLOAD_ENDPOINT to test live upload)")

      api_key ->
        case System.get_env("TINKER_UPLOAD_ENDPOINT") do
          nil ->
            IO.puts("    API key present but TINKER_UPLOAD_ENDPOINT not set")
            IO.puts("    Note: The Tinker API has no file upload endpoints currently.")
            IO.puts("    Set TINKER_UPLOAD_ENDPOINT to test against a custom endpoint.")

          endpoint ->
            IO.puts("    Attempting POST to #{endpoint}...")

            config =
              Tinkex.Config.new(
                api_key: api_key,
                base_url:
                  System.get_env(
                    "TINKER_BASE_URL",
                    "https://tinker.thinkingmachines.dev/services/tinker-prod"
                  )
              )

            case Tinkex.API.post(endpoint, body, config: config, files: files) do
              {:ok, response} ->
                IO.puts("    Success!")
                IO.inspect(response, label: "    Response")

              {:error, error} ->
                IO.puts("    Failed: #{inspect(error)}")
            end
        end
    end

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Demo complete. Multipart encoding is working correctly.")
    IO.puts(String.duplicate("=", 60))
  end

  defp resolve_file_path do
    env_path = System.get_env("TINKER_UPLOAD_FILE")
    default_path = Path.join(["examples", "uploads", "sample_upload.bin"])

    cond do
      env_path && env_path != "" ->
        if File.exists?(env_path) do
          env_path
        else
          raise "TINKER_UPLOAD_FILE set to #{env_path} but file does not exist"
        end

      File.exists?(default_path) ->
        default_path

      true ->
        raise "Missing upload file; set TINKER_UPLOAD_FILE or ensure #{default_path} exists"
    end
  end
end

Tinkex.Examples.FileUploadMultipart.run()
