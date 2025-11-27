# Multipart File Uploads

Tinkex can now build multipart/form-data requests without any external helpers. Pass a `:files` option to Tinkex.API.post/3 and the SDK will:

- Normalize file inputs (binaries, iodata, `File.Stream`, or file paths) and read paths into memory
- Flatten the request body into form fields using bracket notation (e.g., `%{foo: %{bar: 1}}` → `"foo[bar]" => "1"`)
- Generate multipart boundaries and set `Content-Type` automatically (respects a caller-provided `boundary` if present)
- Preserve tuple metadata `(filename, content, content_type, headers)` per Python SDK parity

> Requires only `TINKER_API_KEY` and works against any Tinker endpoint that expects multipart bodies.

## Supported file inputs

You can supply files as a map or list (mirrors Python’s `files` API):

- Raw binaries or iodata: `%{"upload" => "hello"}`, `%{"upload" => <<1, 2, 3>>}`
- File paths: `%{"upload" => "/tmp/file.txt"}` (Tinkex reads the file and uses the basename as filename)
- Tuples with metadata:
  - `{filename, content}`
  - `{filename, content, content_type}`
  - `{filename, content, content_type, headers}` (headers can be a map or list of `{key, value}`)

## Quickstart

```elixir
{:ok, _} = Application.ensure_all_started(:tinkex)

config = Tinkex.Config.new(
  api_key: System.fetch_env!("TINKER_API_KEY"),
  base_url: System.get_env("TINKER_BASE_URL", "https://tinker.thinkingmachines.dev/services/tinker-prod")
)

files = %{
  "file" =>
    System.get_env("TINKER_UPLOAD_FILE") ||
      "examples/uploads/sample_upload.bin"
}

body = %{note: "multipart demo"}

upload_path = "/"

case Tinkex.API.post(upload_path, body, config: config, files: files) do
  {:ok, response} -> IO.inspect(response, label: "upload response")
  {:error, error} -> IO.puts("Upload failed: #{inspect(error)}")
end
```

If you need to preview what will be sent, you can use the lower-level helpers directly:

```elixir
{:ok, normalized} = Tinkex.Files.Transform.transform_files(files)
form_fields = Tinkex.Multipart.FormSerializer.serialize_form_fields(body)
{:ok, _body, content_type} = Tinkex.Multipart.Encoder.encode_multipart(form_fields, normalized)
IO.puts("Multipart Content-Type: #{content_type}")
```

## Header behavior

- If `:files` are provided (or you set `content-type: multipart/form-data`), Tinkex switches to multipart encoding and replaces the Content-Type header with one that includes the boundary (unless you already set a boundary).
- If no files are provided, JSON encoding is preserved exactly as before.

## Troubleshooting

- 415/422 responses usually mean the endpoint rejected the payload; check that the path expects multipart and that filenames/content-types match what the API requires.
- Paths are read eagerly into memory to match the Python SDK; for large payloads consider chunked uploads via a dedicated endpoint when available.
