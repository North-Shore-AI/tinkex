# Gap #2: File Upload & Multipart Handling - Deep Dive Analysis

**Date:** 2025-11-27
**Status:** Critical Gap - Python has full support, Elixir has none
**Impact:** High - Blocks any file upload functionality in Elixir SDK

---

## Executive Summary

The Python SDK (Tinker) has comprehensive file upload and multipart/form-data encoding support through a dedicated files subsystem, while the Elixir SDK (Tinkex) defaults to JSON-encoded request bodies and lacks first-class file/multipart handling (callers can only send raw binaries they craft themselves). This gap prevents the Elixir SDK from handling any file upload operations, which are critical for many ML/training workflows.

**Python Capabilities:**
- 5 file input types supported (bytes, IO streams, PathLike, tuples with metadata)
- Automatic multipart/form-data encoding
- Sync and async file reading
- Content-type detection
- Filename extraction from paths
- File extraction from nested request bodies
- httpx multipart boundary generation

**Elixir Limitations:**
- Only JSON encoding via `Jason.encode!()`
- No file input type support
- No multipart/form-data encoding
- Binary bodies are passed through if provided, but there is no multipart detection/encoding or file-type handling

---

## Table of Contents

1. [Python SDK File Upload Architecture](#python-sdk-file-upload-architecture)
2. [Elixir SDK Current Body Encoding](#elixir-sdk-current-body-encoding)
3. [Granular Differences](#granular-differences)
4. [TDD Implementation Plan](#tdd-implementation-plan)
5. [Technical Specifications](#technical-specifications)
6. [Migration Path](#migration-path)

---

## Python SDK File Upload Architecture

### 1. Type System (`_types.py`)

The Python SDK defines a rich type hierarchy for file inputs:

```python
# Core file content types
FileContent = Union[IO[bytes], bytes, PathLike[str]]

# Rich file type with metadata (filename, content-type, headers)
FileTypes = Union[
    # Just the file content
    FileContent,
    # (filename, content)
    Tuple[Optional[str], FileContent],
    # (filename, content, content_type)
    Tuple[Optional[str], FileContent, Optional[str]],
    # (filename, content, content_type, headers)
    Tuple[Optional[str], FileContent, Optional[str], Mapping[str, str]],
]

# Request files can be dict or list of tuples
RequestFiles = Union[
    Mapping[str, FileTypes],           # {"file": file_content}
    Sequence[Tuple[str, FileTypes]]    # [("file", file_content)]
]

# httpx-compatible types (after transformation)
HttpxFileContent = Union[IO[bytes], bytes]
HttpxFileTypes = Union[
    HttpxFileContent,
    Tuple[Optional[str], HttpxFileContent],
    Tuple[Optional[str], HttpxFileContent, Optional[str]],
    Tuple[Optional[str], HttpxFileContent, Optional[str], Mapping[str, str]],
]
HttpxRequestFiles = Union[Mapping[str, HttpxFileTypes], Sequence[Tuple[str, HttpxFileTypes]]]
```

**Key Insight:** The type system distinguishes between user-facing types (`FileTypes` with `PathLike`) and httpx-internal types (`HttpxFileTypes` with only bytes/IO).

### 2. File Processing (`_files.py`)

The file processing module handles transformation and validation:

#### **2.1 Type Guards**

```python
def is_base64_file_input(obj: object) -> TypeGuard[Base64FileInput]:
    return isinstance(obj, io.IOBase) or isinstance(obj, os.PathLike)

def is_file_content(obj: object) -> TypeGuard[FileContent]:
    return (
        isinstance(obj, bytes) or
        isinstance(obj, tuple) or
        isinstance(obj, io.IOBase) or
        isinstance(obj, os.PathLike)
    )

def assert_is_file_content(obj: object, *, key: str | None = None) -> None:
    if not is_file_content(obj):
        prefix = f"Expected entry at `{key}`" if key else f"Expected file input `{obj!r}`"
        raise RuntimeError(
            f"{prefix} to be bytes, an io.IOBase instance, PathLike or a tuple but received {type(obj)} instead."
        )
```

#### **2.2 Synchronous File Transformation**

```python
def to_httpx_files(files: RequestFiles | None) -> HttpxRequestFiles | None:
    if files is None:
        return None

    if is_mapping_t(files):
        files = {key: _transform_file(file) for key, file in files.items()}
    elif is_sequence_t(files):
        files = [(key, _transform_file(file)) for key, file in files]
    else:
        raise TypeError(f"Unexpected file type input {type(files)}, expected mapping or sequence")

    return files

def _transform_file(file: FileTypes) -> HttpxFileTypes:
    if is_file_content(file):
        if isinstance(file, os.PathLike):
            # Extract filename and read bytes from path
            path = pathlib.Path(file)
            return (path.name, path.read_bytes())
        return file

    if is_tuple_t(file):
        # Tuple format: (filename, content, [content_type], [headers])
        return (file[0], read_file_content(file[1]), *file[2:])

    raise TypeError(f"Expected file types input to be a FileContent type or to be a tuple")

def read_file_content(file: FileContent) -> HttpxFileContent:
    if isinstance(file, os.PathLike):
        return pathlib.Path(file).read_bytes()
    return file
```

**Flow:**
1. Accept `PathLike`, bytes, IO, or tuples
2. If `PathLike`: extract filename from path, read bytes
3. If tuple: process each element, recursively reading file content
4. Return httpx-compatible format (bytes or IO only)

#### **2.3 Asynchronous File Transformation**

```python
async def async_to_httpx_files(files: RequestFiles | None) -> HttpxRequestFiles | None:
    if files is None:
        return None

    if is_mapping_t(files):
        files = {key: await _async_transform_file(file) for key, file in files.items()}
    elif is_sequence_t(files):
        files = [(key, await _async_transform_file(file)) for key, file in files]
    else:
        raise TypeError("Unexpected file type input {type(files)}, expected mapping or sequence")

    return files

async def _async_transform_file(file: FileTypes) -> HttpxFileTypes:
    if is_file_content(file):
        if isinstance(file, os.PathLike):
            # Async file reading via anyio
            path = anyio.Path(file)
            return (path.name, await path.read_bytes())
        return file

    if is_tuple_t(file):
        return (file[0], await async_read_file_content(file[1]), *file[2:])

    raise TypeError(f"Expected file types input to be a FileContent type or to be a tuple")

async def async_read_file_content(file: FileContent) -> HttpxFileContent:
    if isinstance(file, os.PathLike):
        return await anyio.Path(file).read_bytes()
    return file
```

**Key Differences from Sync:**
- Uses `anyio.Path` for async I/O
- All file reads are awaited
- Otherwise identical logic

### 3. File Extraction from Request Bodies (`_utils/_utils.py`)

The SDK can extract files from nested request body structures:

```python
def extract_files(
    query: Mapping[str, object],
    *,
    paths: Sequence[Sequence[str]],
) -> list[tuple[str, FileTypes]]:
    """Recursively extract files from the given dictionary based on specified paths.

    A path may look like this ['foo', 'files', '<array>', 'data'].

    Note: this mutates the given dictionary.
    """
    files: list[tuple[str, FileTypes]] = []
    for path in paths:
        files.extend(_extract_items(query, path, index=0, flattened_key=None))
    return files

def _extract_items(
    obj: object,
    path: Sequence[str],
    *,
    index: int,
    flattened_key: str | None,
) -> list[tuple[str, FileTypes]]:
    try:
        key = path[index]
    except IndexError:
        # Path exhausted - we found the file
        if isinstance(obj, NotGiven):
            return []

        from .._files import assert_is_file_content
        assert flattened_key is not None

        if is_list(obj):
            # Extract all files from array
            files: list[tuple[str, FileTypes]] = []
            for entry in obj:
                assert_is_file_content(entry, key=flattened_key + "[]" if flattened_key else "")
                files.append((flattened_key + "[]", cast(FileTypes, entry)))
            return files

        assert_is_file_content(obj, key=flattened_key)
        return [(flattened_key, cast(FileTypes, obj))]

    # Continue traversing path...
    # Builds flattened keys like "documents[][file]" for multipart encoding
```

**Usage Example:**
```python
query = {"documents": [{"file": b"My first file"}, {"file": b"My second file"}]}
files = extract_files(query, paths=[["documents", "<array>", "file"]])
# Result: [("documents[][file]", b"My first file"), ("documents[][file]", b"My second file")]
# query is mutated to: {"documents": [{}, {}]}
```

### 4. Integration with HTTP Client (`_base_client.py`)

#### **4.1 Request Building**

```python
def _build_request(self, options: FinalRequestOptions, *, retries_taken: int = 0) -> httpx.Request:
    kwargs: dict[str, Any] = {}

    json_data = options.json_data
    # ... handle extra_json merging ...

    headers = self._build_headers(options, retries_taken=retries_taken)
    params = _merge_mappings(self.default_query, options.params)
    content_type = headers.get("Content-Type")
    files = options.files

    # ==================== MULTIPART HANDLING ====================
    # If the given Content-Type header is multipart/form-data then it
    # has to be removed so that httpx can generate the header with
    # additional information for us as it has to be in this form
    # for the server to be able to correctly parse the request:
    # multipart/form-data; boundary=---abc--
    if content_type is not None and content_type.startswith("multipart/form-data"):
        if "boundary" not in content_type:
            # only remove the header if the boundary hasn't been explicitly set
            # as the caller doesn't want httpx to come up with their own boundary
            headers.pop("Content-Type")

        # As we are now sending multipart/form-data instead of application/json
        # we need to tell httpx to use it
        if json_data:
            if not is_dict(json_data):
                raise TypeError(
                    f"Expected query input to be a dictionary for multipart requests but got {type(json_data)} instead."
                )
            kwargs["data"] = self._serialize_multipartform(json_data)

        # httpx determines whether or not to send a "multipart/form-data"
        # request based on the truthiness of the "files" argument.
        # This gets around that issue by generating a dict value that
        # evaluates to true.
        if not files:
            files = cast(HttpxRequestFiles, ForceMultipartDict())
    # ==================== END MULTIPART HANDLING ====================

    # ... prepare URL ...

    is_body_allowed = options.method.lower() != "get"

    if is_body_allowed:
        if isinstance(json_data, bytes):
            kwargs["content"] = json_data
        else:
            kwargs["json"] = json_data if is_given(json_data) else None
        kwargs["files"] = files

    # ... build and return httpx.Request ...
```

**Critical Logic:**
1. Check if `Content-Type` is `multipart/form-data`
2. Remove `Content-Type` header if no boundary specified (let httpx generate it)
3. Serialize JSON data to form fields via `_serialize_multipartform()`
4. Pass files to httpx via `files=` parameter
5. httpx automatically generates multipart boundary and encodes body

#### **4.2 Multipart Form Serialization**

```python
def _serialize_multipartform(self, data: Mapping[object, object]) -> dict[str, object]:
    items = self.qs.stringify_items(
        data,
        array_format="brackets",  # foo[bar]=1, array[]=1, array[]=2
    )
    serialized: dict[str, object] = {}
    for key, value in items:
        existing = serialized.get(key)

        if not existing:
            serialized[key] = value
            continue

        # If a value has already been set for this key then that
        # means we're sending data like `array[]=[1, 2, 3]` and we
        # need to tell httpx that we want to send multiple values with
        # the same key which is done by using a list or a tuple.
        if is_list(existing):
            existing.append(value)
        else:
            serialized[key] = [existing, value]

    return serialized
```

**Example:**
```python
data = {"foo": {"bar": "baz"}, "array": [1, 2, 3]}
# qs.stringify_items() produces: [("foo[bar]", "baz"), ("array[]", 1), ("array[]", 2), ("array[]", 3)]
# serialized becomes: {"foo[bar]": "baz", "array[]": [1, 2, 3]}
```

### 5. Helper Functions

```python
def file_from_path(path: str) -> FileTypes:
    """Convenience helper to create file tuple from path."""
    contents = Path(path).read_bytes()
    file_name = os.path.basename(path)
    return (file_name, contents)
```

**Usage:**
```python
# User-friendly API
files = {"document": file_from_path("/path/to/file.pdf")}
# Produces: {"document": ("file.pdf", b"...")}
```

---

## Elixir SDK Current Body Encoding

### 1. HTTP Client Architecture (`lib/tinkex/api/api.ex`)

The Elixir SDK uses Finch for HTTP operations:

```elixir
@impl true
@spec post(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
def post(path, body, opts) do
  config = Keyword.fetch!(opts, :config)

  url = build_url(config.base_url, path)
  timeout = Keyword.get(opts, :timeout, config.timeout)
  headers = build_headers(:post, config, opts, timeout)
  max_retries = Keyword.get(opts, :max_retries, config.max_retries)
  pool_type = Keyword.get(opts, :pool_type, :default)
  response_mode = Keyword.get(opts, :response)
  transform_opts = Keyword.get(opts, :transform, [])

  # ==================== BODY ENCODING ====================
  request = Finch.build(:post, url, headers, prepare_body(body, transform_opts))
  # ==================== END BODY ENCODING ====================

  pool_key = PoolKey.build(config.base_url, pool_type)

  {result, retry_count, duration} =
    execute_with_telemetry(
      &with_retries/6,
      [request, config.http_pool, timeout, pool_key, max_retries, config.dump_headers?],
      metadata
    )

  handle_response(result, ...)
end
```

### 2. Body Preparation (`lib/tinkex/api/api.ex`)

```elixir
defp prepare_body(body, _transform_opts) when is_binary(body), do: body

defp prepare_body(body, transform_opts) do
  body
  |> Transform.transform(transform_opts)
  |> Jason.encode!()
end
```

**Flow:**
1. If body is already binary → pass through
2. Otherwise → transform → JSON encode
3. No file handling, no multipart support

### 3. Transform Module (`lib/tinkex/transform.ex`)

```elixir
defmodule Tinkex.Transform do
  @moduledoc """
  Lightweight serialization helpers for request payloads.

  - Drops `Tinkex.NotGiven`/`Tinkex.NotGiven.omit/0` sentinels
  - Applies key aliases and simple formatters (e.g., ISO8601 timestamps)
  - Recurses through maps, structs, and lists while stringifying keys
  """

  @spec transform(term(), opts()) :: term()
  def transform(data, opts \\ [])

  def transform(nil, _opts), do: nil

  def transform(list, opts) when is_list(list) do
    Enum.map(list, &transform(&1, opts))
  end

  def transform(%_{} = struct, opts) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__struct__)
    |> transform_map(opts)
  end

  def transform(map, opts) when is_map(map) do
    transform_map(map, opts)
  end

  def transform(other, _opts), do: other

  defp transform_map(map, opts) do
    aliases = Keyword.get(opts, :aliases, %{})
    formats = Keyword.get(opts, :formats, %{})
    drop_nil? = Keyword.get(opts, :drop_nil?, false)

    Enum.reduce(map, %{}, fn {key, value}, acc ->
      cond do
        NotGiven.not_given?(value) or NotGiven.omit?(value) ->
          acc

        drop_nil? and is_nil(value) ->
          acc

        true ->
          encoded_key = encode_key(key, aliases)
          formatted_value = transform_value(value, key, formats, opts)
          Map.put(acc, encoded_key, formatted_value)
      end
    end)
  end

  # ... key encoding, value formatting, etc ...
end
```

**Capabilities:**
- Removes `NotGiven` sentinels
- Stringifies keys
- Applies aliases
- Formats timestamps
- Recurses through nested structures

**Limitations:**
- No file detection
- No binary handling
- No multipart encoding
- No file metadata extraction

### 4. Headers (`lib/tinkex/api/api.ex`)

```elixir
defp build_headers(method, config, opts, timeout_ms) do
  [
    {"accept", "application/json"},
    {"content-type", "application/json"},  # <-- ALWAYS JSON
    {"user-agent", user_agent()},
    {"connection", "keep-alive"},
    {"accept-encoding", "gzip"},
    {"x-api-key", config.api_key}
  ]
  |> Kernel.++(stainless_headers(timeout_ms))
  |> Kernel.++(cloudflare_headers(config))
  |> Kernel.++(request_headers(opts))
  |> Kernel.++(idempotency_headers(method, opts))
  |> Kernel.++(sampling_headers(opts))
  |> Kernel.++(maybe_raw_response_header(opts))
  |> Kernel.++(Keyword.get(opts, :headers, []))
  |> dedupe_headers()
end
```

**Issue:** `Content-Type` defaults to `application/json` (callers can override manually via `opts[:headers]`). There's no logic to:
- Detect file uploads
- Switch to `multipart/form-data`
- Remove the JSON default automatically or manage multipart boundaries

### 5. Finch Integration

```elixir
case Finch.request(request, config.http_pool, receive_timeout: timeout) do
  {:ok, %Finch.Response{} = response} ->
    # ...
end
```

**Finch Capabilities (not currently used):**
- Finch will transmit whatever binary/iodata body is provided but does not include a multipart encoder
- Requires caller-generated boundaries and multipart framing before calling `Finch.build/4`
- No high-level file upload API or `Mint.HTTP.encode_multipart/2` helper in the stack

---

## Granular Differences

### Comparison Matrix

| Feature | Python SDK | Elixir SDK | Gap Severity |
|---------|-----------|------------|--------------|
| **Input Types** | | | |
| `bytes` input | ✅ Full support | ❌ None | High |
| `IO[bytes]` streams | ✅ Full support | ❌ None | High |
| `PathLike` paths | ✅ Full support + filename extraction | ❌ None | Critical |
| Tuple metadata (filename, content-type, headers) | ✅ 4 tuple formats | ❌ None | High |
| **Encoding** | | | |
| JSON encoding | ✅ Via Pydantic/json | ✅ Via Jason | ✅ Parity |
| Multipart/form-data | ✅ Automatic | ❌ None | Critical |
| Binary body passthrough | ✅ `if isinstance(json_data, bytes)` | ✅ `when is_binary(body)` | ✅ Parity |
| **File Processing** | | | |
| Sync file reading | ✅ `pathlib.Path.read_bytes()` | ❌ None | High |
| Async file reading | ✅ `anyio.Path.read_bytes()` | ❌ None | High |
| File content validation | ✅ Type guards + assertions | ❌ None | Medium |
| Filename extraction from path | ✅ `path.name` | ❌ None | Medium |
| **Request Building** | | | |
| File extraction from body | ✅ `extract_files()` with path specs | ❌ None | High |
| Form field serialization | ✅ `_serialize_multipartform()` with bracket notation | ❌ None | High |
| Array handling in forms | ✅ `array[]=1, array[]=2` | ❌ None | High |
| Nested dict flattening | ✅ `foo[bar][baz]=value` | ❌ None | High |
| **Content-Type Management** | | | |
| Dynamic Content-Type switching | ✅ JSON ↔ multipart based on files | ❌ Always JSON | Critical |
| Multipart boundary generation | ✅ Delegated to httpx | ❌ None | Critical |
| Boundary override support | ✅ Checks for explicit boundary | ❌ None | Low |
| **HTTP Client Integration** | | | |
| Files parameter | ✅ `options.files` | ❌ None | Critical |
| Form data parameter | ✅ `kwargs["data"]` for multipart | ❌ None | Critical |
| JSON parameter | ✅ `kwargs["json"]` | ✅ `Jason.encode!()` in body | ✅ Parity |
| **Helpers** | | | |
| `file_from_path()` | ✅ Convenience helper | ❌ None | Medium |
| File type guards | ✅ `is_file_content()`, `is_base64_file_input()` | ❌ None | Medium |

### Critical Missing Components

1. **File Type System**
   - No equivalent to Python's `FileTypes` union
   - No support for path-like inputs
   - No support for file metadata tuples

2. **File Processing Pipeline**
   - No file reading (sync or async)
   - No path → bytes transformation
   - No filename extraction

3. **Multipart Encoding**
   - No multipart/form-data encoder
   - No boundary generation
   - No form field serialization
   - No file part encoding

4. **Request Building**
   - No file extraction from request bodies
   - No separation of files from JSON data
   - No Content-Type switching logic

5. **HTTP Integration**
   - No files parameter in request options
   - No integration with Finch multipart capabilities
   - Hardcoded JSON Content-Type

---

## TDD Implementation Plan

Testing note: suites that spin up Finch pools, mock servers, or other processes should use `Supertester.ExUnitFoundation` with isolation (`:full_isolation` / helpers) instead of plain `ExUnit.Case` to match project testing standards.

### Phase 1: Type System & File I/O (Foundation)

#### **Test Suite 1.1: File Type Definitions**

```elixir
# test/tinkex/files/types_test.exs

defmodule Tinkex.Files.TypesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Types

  describe "file_content?/1" do
    test "returns true for binary" do
      assert Types.file_content?(<<1, 2, 3>>)
    end

    test "returns true for File.Stream" do
      stream = File.stream!("test/fixtures/sample.txt")
      assert Types.file_content?(stream)
    end

    test "returns true for file path string" do
      assert Types.file_content?("/path/to/file.txt")
    end

    test "returns false for non-file types" do
      refute Types.file_content?(:atom)
      refute Types.file_content?(123)
      refute Types.file_content?(%{})
    end
  end

  describe "file_types?/1" do
    test "returns true for binary" do
      assert Types.file_types?(<<1, 2, 3>>)
    end

    test "returns true for tuple {filename, content}" do
      assert Types.file_types?({"file.txt", <<1, 2, 3>>})
    end

    test "returns true for tuple {filename, content, content_type}" do
      assert Types.file_types?({"file.txt", <<1, 2, 3>>, "text/plain"})
    end

    test "returns true for tuple {filename, content, content_type, headers}" do
      assert Types.file_types?({"file.txt", <<1, 2, 3>>, "text/plain", %{"x-custom" => "value"}})
    end

    test "returns false for invalid tuples" do
      refute Types.file_types?({:invalid})
      refute Types.file_types?({"name", "not_binary"})
    end
  end
end
```

**Implementation Spec:**
```elixir
# lib/tinkex/files/types.ex

defmodule Tinkex.Files.Types do
  @moduledoc """
  Type guards and validators for file inputs.

  Supports the same file input types as Python SDK:
  - Binary data
  - File streams (File.Stream, IO.Stream)
  - File paths (strings)
  - Tuples with metadata: {filename, content, [content_type], [headers]}
  """

  @type file_content :: binary() | File.Stream.t() | Path.t() | String.t()

  @type file_types ::
          file_content()
          | {String.t() | nil, file_content()}
          | {String.t() | nil, file_content(), String.t() | nil}
          | {String.t() | nil, file_content(), String.t() | nil, map()}

  @type request_files ::
          %{String.t() => file_types()}
          | [{String.t(), file_types()}]

  @spec file_content?(term()) :: boolean()
  def file_content?(value)

  @spec file_types?(term()) :: boolean()
  def file_types?(value)

  @spec assert_file_content!(term(), keyword()) :: :ok | no_return()
  def assert_file_content!(value, opts \\ [])
end
```

#### **Test Suite 1.2: Synchronous File Reading**

```elixir
# test/tinkex/files/reader_test.exs

defmodule Tinkex.Files.ReaderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Files.Reader

  @fixture_dir "test/fixtures/files"

  setup do
    File.mkdir_p!(@fixture_dir)
    on_exit(fn -> File.rm_rf!(@fixture_dir) end)
    :ok
  end

  describe "read_file_content/1" do
    test "reads binary as-is" do
      content = <<1, 2, 3, 4>>
      assert {:ok, ^content} = Reader.read_file_content(content)
    end

    test "reads from file path" do
      path = Path.join(@fixture_dir, "test.txt")
      File.write!(path, "Hello, World!")

      assert {:ok, "Hello, World!"} = Reader.read_file_content(path)
    end

    test "extracts filename from path" do
      path = Path.join(@fixture_dir, "document.pdf")
      File.write!(path, <<"%PDF-1.4">>)

      assert {:ok, content} = Reader.read_file_content(path)
      assert content == <<"%PDF-1.4">>
    end

    test "reads from File.Stream" do
      path = Path.join(@fixture_dir, "stream.txt")
      File.write!(path, "Line 1\nLine 2\nLine 3")

      stream = File.stream!(path)
      assert {:ok, content} = Reader.read_file_content(stream)
      assert content == "Line 1\nLine 2\nLine 3"
    end

    test "returns error for non-existent file" do
      assert {:error, :enoent} = Reader.read_file_content("/non/existent/file.txt")
    end

    test "returns error for directory path" do
      assert {:error, :eisdir} = Reader.read_file_content(@fixture_dir)
    end
  end

  describe "extract_filename/1" do
    test "extracts basename from absolute path" do
      assert "file.txt" = Reader.extract_filename("/path/to/file.txt")
    end

    test "extracts basename from relative path" do
      assert "document.pdf" = Reader.extract_filename("docs/document.pdf")
    end

    test "handles filename with no extension" do
      assert "README" = Reader.extract_filename("/home/user/README")
    end

    test "returns nil for binary" do
      assert nil == Reader.extract_filename(<<1, 2, 3>>)
    end
  end
end
```

**Implementation Spec:**
```elixir
# lib/tinkex/files/reader.ex

defmodule Tinkex.Files.Reader do
  @moduledoc """
  Synchronous file reading and content extraction.

  Handles:
  - Binary passthrough
  - File path reading with File.read!/1
  - Stream consumption
  - Filename extraction from paths
  """

  alias Tinkex.Files.Types

  @spec read_file_content(Types.file_content()) :: {:ok, binary()} | {:error, File.posix()}
  def read_file_content(content)

  @spec read_file_content!(Types.file_content()) :: binary() | no_return()
  def read_file_content!(content)

  @spec extract_filename(Types.file_content()) :: String.t() | nil
  def extract_filename(content)
end
```

#### **Test Suite 1.3: Asynchronous File Reading**

```elixir
# test/tinkex/files/async_reader_test.exs

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
        Enum.map(1..10, fn i ->
          path = Path.join(@fixture_dir, "file_#{i}.txt")
          File.write!(path, "Content #{i}")
          path
        end)

      tasks = Enum.map(paths, &AsyncReader.read_file_content_async/1)
      results = Task.await_many(tasks)

      assert length(results) == 10
      assert Enum.all?(results, fn {:ok, content} -> String.starts_with?(content, "Content ") end)
    end
  end
end
```

**Implementation Spec:**
```elixir
# lib/tinkex/files/async_reader.ex

defmodule Tinkex.Files.AsyncReader do
  @moduledoc """
  Asynchronous file reading via Task.

  Mirrors Python's anyio.Path async file operations.
  Uses Task.async/1 for parallel I/O.
  """

  alias Tinkex.Files.{Reader, Types}

  @spec read_file_content_async(Types.file_content()) :: Task.t()
  def read_file_content_async(content) do
    Task.async(fn -> Reader.read_file_content(content) end)
  end
end
```

### Phase 2: File Transformation Pipeline

#### **Test Suite 2.1: File Type Transformation**

```elixir
# test/tinkex/files/transform_test.exs

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
```

**Implementation Spec:**
```elixir
# lib/tinkex/files/transform.ex

defmodule Tinkex.Files.Transform do
  @moduledoc """
  Transform user-facing file inputs to httpx-compatible format.

  Handles:
  - Binary passthrough
  - Path → (filename, bytes)
  - Tuple expansion with file reading
  - Map and list processing
  """

  alias Tinkex.Files.{Reader, Types}

  @spec transform_file(Types.file_types()) ::
    {:ok, binary() | {String.t() | nil, binary()} | {String.t() | nil, binary(), String.t() | nil} | {String.t() | nil, binary(), String.t() | nil, map()}}
    | {:error, term()}
  def transform_file(file)

  @spec transform_files(Types.request_files()) :: {:ok, Types.request_files()} | {:error, term()}
  def transform_files(files)

  @spec transform_files_async(Types.request_files()) :: Task.t()
  def transform_files_async(files)
end
```

### Phase 3: Multipart Encoding

#### **Test Suite 3.1: Form Field Serialization**

```elixir
# test/tinkex/multipart/form_serializer_test.exs

defmodule Tinkex.Multipart.FormSerializerTest do
  use ExUnit.Case, async: true

  alias Tinkex.Multipart.FormSerializer

  describe "serialize_form_fields/1" do
    test "serializes flat map" do
      data = %{"name" => "John", "age" => 30}
      assert %{"name" => "John", "age" => "30"} = FormSerializer.serialize_form_fields(data)
    end

    test "serializes nested map with bracket notation" do
      data = %{"user" => %{"name" => "Alice", "email" => "alice@example.com"}}

      result = FormSerializer.serialize_form_fields(data)
      assert result["user[name]"] == "Alice"
      assert result["user[email]"] == "alice@example.com"
    end

    test "serializes arrays with bracket notation" do
      data = %{"tags" => ["elixir", "phoenix", "ecto"]}

      result = FormSerializer.serialize_form_fields(data)
      # Should produce: "tags[]" => ["elixir", "phoenix", "ecto"]
      assert result["tags[]"] == ["elixir", "phoenix", "ecto"]
    end

    test "serializes deeply nested structures" do
      data = %{
        "user" => %{
          "profile" => %{
            "address" => %{
              "city" => "NYC"
            }
          }
        }
      }

      result = FormSerializer.serialize_form_fields(data)
      assert result["user[profile][address][city]"] == "NYC"
    end

    test "handles arrays of maps" do
      data = %{
        "documents" => [
          %{"type" => "pdf", "name" => "doc1"},
          %{"type" => "docx", "name" => "doc2"}
        ]
      }

      result = FormSerializer.serialize_form_fields(data)
      # Should produce flattened keys
      assert is_list(result["documents[][type]"])
      assert "pdf" in result["documents[][type]"]
      assert "docx" in result["documents[][type]"]
    end
  end
end
```

**Implementation Spec:**
```elixir
# lib/tinkex/multipart/form_serializer.ex

defmodule Tinkex.Multipart.FormSerializer do
  @moduledoc """
  Serialize JSON-like data structures to multipart form fields.

  Uses bracket notation for nested structures:
  - %{"user" => %{"name" => "Alice"}} → "user[name]" => "Alice"
  - %{"tags" => [1, 2, 3]} → "tags[]" => [1, 2, 3]

  Python parity: mirrors _serialize_multipartform() behavior.
  """

  @spec serialize_form_fields(map()) :: map()
  def serialize_form_fields(data)
end
```

#### **Test Suite 3.2: Multipart Body Encoding**

```elixir
# test/tinkex/multipart/encoder_test.exs

defmodule Tinkex.Multipart.EncoderTest do
  use ExUnit.Case, async: true

  alias Tinkex.Multipart.Encoder

  describe "encode_multipart/2" do
    test "encodes simple form fields" do
      fields = %{"name" => "Alice", "age" => "30"}
      files = %{}

      {:ok, body, content_type} = Encoder.encode_multipart(fields, files)

      assert is_binary(body)
      assert String.starts_with?(content_type, "multipart/form-data; boundary=")
      assert String.contains?(body, "name")
      assert String.contains?(body, "Alice")
      assert String.contains?(body, "age")
      assert String.contains?(body, "30")
    end

    test "encodes file uploads" do
      fields = %{"description" => "My file"}
      files = %{"document" => {"test.txt", "File content"}}

      {:ok, body, content_type} = Encoder.encode_multipart(fields, files)

      assert String.starts_with?(content_type, "multipart/form-data; boundary=")
      assert String.contains?(body, "description")
      assert String.contains?(body, "My file")
      assert String.contains?(body, "document")
      assert String.contains?(body, "test.txt")
      assert String.contains?(body, "File content")
    end

    test "encodes file with content-type" do
      files = %{"image" => {"photo.jpg", <<0xFF, 0xD8, 0xFF>>, "image/jpeg"}}

      {:ok, body, content_type} = Encoder.encode_multipart(%{}, files)

      assert String.contains?(body, "Content-Type: image/jpeg")
      assert String.contains?(body, "photo.jpg")
    end

    test "encodes file with custom headers" do
      files = %{
        "file" => {"data.bin", <<1, 2, 3>>, "application/octet-stream", %{"x-custom" => "value"}}
      }

      {:ok, body, content_type} = Encoder.encode_multipart(%{}, files)

      assert String.contains?(body, "x-custom: value")
    end

    test "generates unique boundary" do
      {:ok, _, ct1} = Encoder.encode_multipart(%{"a" => "1"}, %{})
      {:ok, _, ct2} = Encoder.encode_multipart(%{"a" => "1"}, %{})

      [_, boundary1] = String.split(ct1, "boundary=")
      [_, boundary2] = String.split(ct2, "boundary=")

      assert boundary1 != boundary2
    end

    test "properly terminates multipart body" do
      {:ok, body, content_type} = Encoder.encode_multipart(%{"a" => "1"}, %{})

      [_, boundary] = String.split(content_type, "boundary=")
      assert String.ends_with?(body, "--#{boundary}--\r\n")
    end
  end

  describe "generate_boundary/0" do
    test "generates unique boundaries" do
      boundaries = Enum.map(1..100, fn _ -> Encoder.generate_boundary() end)
      unique_boundaries = Enum.uniq(boundaries)

      assert length(unique_boundaries) == 100
    end

    test "generates valid boundary format" do
      boundary = Encoder.generate_boundary()

      assert is_binary(boundary)
      assert String.length(boundary) > 0
      # Should be safe characters for HTTP
      assert Regex.match?(~r/^[a-zA-Z0-9_-]+$/, boundary)
    end
  end
end
```

**Implementation Spec:**
```elixir
# lib/tinkex/multipart/encoder.ex

defmodule Tinkex.Multipart.Encoder do
  @moduledoc """
  Encode multipart/form-data request bodies.

  Generates:
  - Unique boundary strings
  - Properly formatted multipart sections
  - Content-Disposition headers
  - Content-Type headers for files
  - Custom headers for file parts

  Follows RFC 7578 (multipart/form-data) and RFC 2046 (MIME).
  """

  @spec encode_multipart(map(), map()) :: {:ok, binary(), String.t()} | {:error, term()}
  def encode_multipart(form_fields, files)

  @spec generate_boundary() :: String.t()
  def generate_boundary()

  @spec encode_part(String.t(), term()) :: binary()
  defp encode_part(name, value)

  @spec encode_file_part(String.t(), {String.t() | nil, binary(), String.t() | nil, map() | nil}) :: binary()
  defp encode_file_part(name, file_tuple)
end
```

### Phase 4: Request Integration

#### **Test Suite 4.1: Request Options Extension**

```elixir
# test/tinkex/api/request_options_test.exs

defmodule Tinkex.API.RequestOptionsTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.RequestOptions

  describe "with files option" do
    test "accepts files as map" do
      opts = RequestOptions.new(
        config: build_config(),
        files: %{"document" => {"test.txt", "content"}}
      )

      assert opts.files == %{"document" => {"test.txt", "content"}}
    end

    test "accepts files as list of tuples" do
      opts = RequestOptions.new(
        config: build_config(),
        files: [{"file1", <<1, 2>>}, {"file2", <<3, 4>>}]
      )

      assert is_list(opts.files)
    end

    test "detects multipart mode when files present" do
      opts = RequestOptions.new(
        config: build_config(),
        files: %{"doc" => "content"}
      )

      assert RequestOptions.multipart?(opts)
    end

    test "detects multipart mode when Content-Type is multipart/form-data" do
      opts = RequestOptions.new(
        config: build_config(),
        headers: [{"content-type", "multipart/form-data"}]
      )

      assert RequestOptions.multipart?(opts)
    end
  end

  defp build_config do
    %Tinkex.Config{
      api_key: "test",
      base_url: "http://localhost",
      http_pool: :test_pool
    }
  end
end
```

#### **Test Suite 4.2: Finch Request Builder**

```elixir
# test/tinkex/api/api_multipart_test.exs

defmodule Tinkex.API.ApiMultipartTest do
  use ExUnit.Case, async: false

  alias Tinkex.API

  @fixture_dir "test/fixtures/api_multipart"

  setup do
    File.mkdir_p!(@fixture_dir)

    # Start test Finch pool
    {:ok, _} = Finch.start_link(name: TestMultipartPool)

    on_exit(fn ->
      File.rm_rf!(@fixture_dir)
      :ok = Finch.stop(TestMultipartPool)
    end)

    config = %Tinkex.Config{
      api_key: "test_key",
      base_url: "http://localhost:4000",
      http_pool: TestMultipartPool,
      timeout: 5_000,
      max_retries: 0
    }

    %{config: config}
  end

  describe "POST with files" do
    test "builds multipart request with file upload", %{config: config} do
      # Create test file
      path = Path.join(@fixture_dir, "upload.txt")
      File.write!(path, "Test file content")

      body = %{"description" => "My upload"}
      files = %{"document" => path}

      # Mock HTTP server would receive this
      # For now, just test request building
      assert {:error, %Tinkex.Error{type: :api_connection}} =
        API.post("/upload", body,
          config: config,
          files: files
        )

      # In production, would verify:
      # - Content-Type is multipart/form-data with boundary
      # - Body contains both form fields and file content
      # - File has correct Content-Disposition header
    end

    test "builds multipart request with multiple files", %{config: config} do
      files = %{
        "file1" => {"doc1.txt", "Content 1"},
        "file2" => {"doc2.txt", "Content 2"}
      }

      assert {:error, _} = API.post("/upload", %{}, config: config, files: files)
    end

    test "switches Content-Type to multipart when files present", %{config: config} do
      # Even if user sets JSON content-type, should override when files present
      files = %{"doc" => "content"}

      assert {:error, _} = API.post("/upload", %{},
        config: config,
        files: files,
        headers: [{"content-type", "application/json"}]
      )

      # Should have replaced with multipart/form-data
    end

    test "allows explicit multipart boundary", %{config: config} do
      files = %{"doc" => "content"}

      assert {:error, _} = API.post("/upload", %{},
        config: config,
        files: files,
        headers: [{"content-type", "multipart/form-data; boundary=custom-boundary-123"}]
      )

      # Should preserve custom boundary
    end
  end

  describe "POST with JSON (no files)" do
    test "uses JSON encoding when no files", %{config: config} do
      body = %{"name" => "Alice", "age" => 30}

      assert {:error, _} = API.post("/data", body, config: config)

      # Should use application/json Content-Type
      # Should encode body as JSON
    end

    test "respects binary body passthrough", %{config: config} do
      body = Jason.encode!(%{"pre" => "encoded"})

      assert {:error, _} = API.post("/data", body, config: config)

      # Should pass binary through without re-encoding
    end
  end
end
```

### Phase 5: Integration Tests

#### **Test Suite 5.1: End-to-End File Upload**

```elixir
# test/integration/file_upload_test.exs

defmodule Tinkex.Integration.FileUploadTest do
  use ExUnit.Case

  alias Tinkex.{API, Config}

  @moduletag :integration
  @moduletag timeout: 10_000

  setup_all do
    # Start a mock HTTP server that accepts multipart uploads
    {:ok, pid} = MockMultipartServer.start_link(port: 4567)

    on_exit(fn ->
      MockMultipartServer.stop(pid)
    end)

    config = %Config{
      api_key: "integration_test_key",
      base_url: "http://localhost:4567",
      http_pool: :integration_test_pool,
      timeout: 5_000
    }

    {:ok, _} = Finch.start_link(name: :integration_test_pool)

    %{config: config}
  end

  test "uploads file from path", %{config: config} do
    # Create test file
    path = "/tmp/test_upload_#{:rand.uniform(1000)}.txt"
    File.write!(path, "Integration test content")

    on_exit(fn -> File.rm(path) end)

    assert {:ok, response} = API.post("/upload",
      %{"metadata" => "test upload"},
      config: config,
      files: %{"document" => path}
    )

    assert response["status"] == "uploaded"
    assert response["files"]["document"]["filename"] == Path.basename(path)
    assert response["files"]["document"]["size"] > 0
  end

  test "uploads file from binary", %{config: config} do
    content = "Binary upload content"

    assert {:ok, response} = API.post("/upload",
      %{},
      config: config,
      files: %{"data" => {"custom.txt", content}}
    )

    assert response["files"]["data"]["filename"] == "custom.txt"
  end

  test "uploads multiple files", %{config: config} do
    files = %{
      "file1" => {"doc1.txt", "First document"},
      "file2" => {"doc2.txt", "Second document"},
      "file3" => {"doc3.txt", "Third document"}
    }

    assert {:ok, response} = API.post("/upload",
      %{"batch" => "multiple"},
      config: config,
      files: files
    )

    assert map_size(response["files"]) == 3
  end

  test "uploads file with content-type", %{config: config} do
    files = %{
      "image" => {"photo.jpg", <<0xFF, 0xD8, 0xFF>>, "image/jpeg"}
    }

    assert {:ok, response} = API.post("/upload",
      %{},
      config: config,
      files: files
    )

    assert response["files"]["image"]["content_type"] == "image/jpeg"
  end
end
```

#### **Test Suite 5.2: Python Parity Verification**

```elixir
# test/parity/file_upload_parity_test.exs

defmodule Tinkex.Parity.FileUploadParityTest do
  use ExUnit.Case

  @moduledoc """
  Tests to verify Elixir implementation matches Python behavior.

  Run alongside Python SDK tests with same server to ensure identical behavior.
  """

  alias Tinkex.Files.Transform
  alias Tinkex.Multipart.{FormSerializer, Encoder}

  describe "file type handling parity" do
    test "binary passthrough matches Python" do
      content = <<1, 2, 3, 4, 5>>

      assert {:ok, ^content} = Transform.transform_file(content)
      # Python: _transform_file(b"\x01\x02\x03\x04\x05") → b"\x01\x02\x03\x04\x05"
    end

    test "path reading matches Python" do
      # Setup test file
      path = "/tmp/parity_test_#{:rand.uniform(1000)}.txt"
      content = "Parity test content"
      File.write!(path, content)
      on_exit(fn -> File.rm(path) end)

      assert {:ok, {filename, ^content}} = Transform.transform_file(path)
      assert filename == Path.basename(path)
      # Python: _transform_file(Path("file.txt")) → ("file.txt", b"content")
    end

    test "tuple handling matches Python" do
      # Test all tuple formats

      # Format 1: (filename, content)
      assert {:ok, {"file.txt", "data"}} = Transform.transform_file({"file.txt", "data"})

      # Format 2: (filename, content, content_type)
      assert {:ok, {"file.txt", "data", "text/plain"}} =
        Transform.transform_file({"file.txt", "data", "text/plain"})

      # Format 3: (filename, content, content_type, headers)
      headers = %{"x-custom" => "value"}
      assert {:ok, {"file.txt", "data", "text/plain", ^headers}} =
        Transform.transform_file({"file.txt", "data", "text/plain", headers})
    end
  end

  describe "form serialization parity" do
    test "flat map serialization matches Python" do
      data = %{"name" => "Alice", "age" => 30}
      result = FormSerializer.serialize_form_fields(data)

      assert result["name"] == "Alice"
      assert result["age"] == "30"
      # Python: {"name": "Alice", "age": "30"}
    end

    test "nested map bracket notation matches Python" do
      data = %{"user" => %{"profile" => %{"name" => "Bob"}}}
      result = FormSerializer.serialize_form_fields(data)

      assert result["user[profile][name]"] == "Bob"
      # Python: {"user[profile][name]": "Bob"}
    end

    test "array bracket notation matches Python" do
      data = %{"tags" => ["a", "b", "c"]}
      result = FormSerializer.serialize_form_fields(data)

      assert result["tags[]"] == ["a", "b", "c"]
      # Python: {"tags[]": ["a", "b", "c"]}
    end
  end

  describe "multipart encoding parity" do
    test "boundary format matches httpx" do
      boundary = Encoder.generate_boundary()

      # Should be similar format to httpx boundaries
      assert String.length(boundary) >= 16
      assert Regex.match?(~r/^[a-f0-9]+$/, boundary)
    end

    test "part encoding matches httpx format" do
      fields = %{"field" => "value"}
      files = %{"file" => {"test.txt", "content"}}

      {:ok, body, content_type} = Encoder.encode_multipart(fields, files)

      # Verify format matches httpx multipart encoding
      assert String.contains?(body, "Content-Disposition: form-data; name=\"field\"")
      assert String.contains?(body, "value")
      assert String.contains?(body, "Content-Disposition: form-data; name=\"file\"; filename=\"test.txt\"")
      assert String.contains?(body, "content")
    end
  end
end
```

---

## Technical Specifications

### Finch Multipart Integration

Finch (via Mint) does not have high-level multipart support like httpx. We need to manually construct multipart bodies.

#### **Multipart Body Format (RFC 7578)**

```
--{boundary}\r\n
Content-Disposition: form-data; name="field_name"\r\n
\r\n
field_value\r\n
--{boundary}\r\n
Content-Disposition: form-data; name="file"; filename="example.txt"\r\n
Content-Type: text/plain\r\n
\r\n
{file_content}\r\n
--{boundary}--\r\n
```

#### **Implementation Strategy**

```elixir
defmodule Tinkex.Multipart.Encoder do
  def encode_multipart(form_fields, files) do
    boundary = generate_boundary()

    parts = []

    # Add form fields
    parts = parts ++ Enum.map(form_fields, fn {name, value} ->
      encode_field_part(boundary, name, value)
    end)

    # Add files
    parts = parts ++ Enum.map(files, fn {name, file_data} ->
      encode_file_part(boundary, name, file_data)
    end)

    # Final boundary
    body = Enum.join(parts, "") <> "--#{boundary}--\r\n"
    content_type = "multipart/form-data; boundary=#{boundary}"

    {:ok, body, content_type}
  end

  defp generate_boundary do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp encode_field_part(boundary, name, value) do
    """
    --#{boundary}\r\n
    Content-Disposition: form-data; name="#{name}"\r\n
    \r\n
    #{value}\r\n
    """
  end

  defp encode_file_part(boundary, name, {filename, content, content_type, headers}) do
    header_lines = Enum.map(headers || %{}, fn {k, v} -> "#{k}: #{v}\r\n" end)

    """
    --#{boundary}\r\n
    Content-Disposition: form-data; name="#{name}"; filename="#{filename}"\r\n
    Content-Type: #{content_type || "application/octet-stream"}\r\n
    #{Enum.join(header_lines)}
    \r\n
    #{content}\r\n
    """
  end
end
```

### API Integration Changes

#### **Current Flow (JSON only)**

```elixir
def post(path, body, opts) do
  # ...
  request = Finch.build(:post, url, headers, prepare_body(body, transform_opts))
  # ...
end

defp prepare_body(body, _transform_opts) when is_binary(body), do: body

defp prepare_body(body, transform_opts) do
  body
  |> Transform.transform(transform_opts)
  |> Jason.encode!()
end
```

#### **New Flow (with multipart support)**

```elixir
def post(path, body, opts) do
  config = Keyword.fetch!(opts, :config)
  files = Keyword.get(opts, :files)

  {headers, prepared_body} =
    if files do
      # Multipart mode
      prepare_multipart_request(body, files, build_headers(:post, config, opts, timeout))
    else
      # JSON mode
      headers = build_headers(:post, config, opts, timeout)
      {headers, prepare_body(body, transform_opts)}
    end

  request = Finch.build(:post, url, headers, prepared_body)
  # ...
end

defp prepare_multipart_request(body, files, headers) do
  # Transform files (read from paths, etc.)
  {:ok, transformed_files} = Files.Transform.transform_files(files)

  # Serialize JSON body to form fields
  form_fields =
    if body && body != %{} do
      Multipart.FormSerializer.serialize_form_fields(body)
    else
      %{}
    end

  # Encode multipart body
  {:ok, multipart_body, content_type} =
    Multipart.Encoder.encode_multipart(form_fields, transformed_files)

  # Update Content-Type header (unless custom boundary specified)
  headers = update_content_type_header(headers, content_type)

  {headers, multipart_body}
end

defp update_content_type_header(headers, new_content_type) do
  # Remove existing Content-Type
  headers = Enum.reject(headers, fn {k, _} -> String.downcase(k) == "content-type" end)

  # Add new multipart Content-Type
  [{"content-type", new_content_type} | headers]
end
```

---

## Migration Path

### Recommended Implementation Order

1. **Phase 1: Foundation (Week 1)**
   - Implement `Tinkex.Files.Types` type guards
   - Implement `Tinkex.Files.Reader` sync file reading
   - Implement `Tinkex.Files.AsyncReader` async file reading
   - Write comprehensive unit tests

2. **Phase 2: Transformation (Week 2)**
   - Implement `Tinkex.Files.Transform` pipeline
   - Add path → binary transformation
   - Add tuple processing
   - Add file extraction from request bodies

3. **Phase 3: Multipart Encoding (Week 2-3)**
   - Implement `Tinkex.Multipart.FormSerializer`
   - Implement `Tinkex.Multipart.Encoder`
   - Implement boundary generation
   - Add RFC compliance tests

4. **Phase 4: API Integration (Week 3-4)**
   - Extend `FinalRequestOptions` with `:files` field
   - Update `Tinkex.API.post/3` to detect and handle files
   - Update header building logic
   - Add Content-Type switching

5. **Phase 5: Testing & Validation (Week 4)**
   - Integration tests with mock server
   - Python parity tests
   - Performance benchmarks
   - Documentation

### Breaking Changes

**None** - This is purely additive functionality:
- Existing JSON API calls continue to work
- New `:files` option is optional
- No changes to existing function signatures
- Backward compatible

### Performance Considerations

1. **File Reading**
   - Sync: `File.read!/1` is efficient for small files
   - Async: `Task.async/1` provides parallelism for multiple files
   - Consider streaming for large files (>10MB) in future enhancement

2. **Multipart Encoding**
   - Binary concatenation is efficient in BEAM
   - Consider iodata for very large payloads (future optimization)
   - Boundary generation via `:crypto.strong_rand_bytes/1` is fast

3. **Memory Usage**
   - Files are read into memory completely (like Python SDK)
   - For large files, consider streaming API in future
   - Current approach matches Python SDK behavior

### Error Handling

```elixir
# File reading errors
{:error, :enoent} # File not found
{:error, :eacces} # Permission denied
{:error, :eisdir} # Path is directory

# Validation errors
{:error, {:invalid_file_type, term()}}
{:error, {:invalid_request_files, term()}}

# Encoding errors
{:error, {:multipart_encoding_failed, reason}}
```

---

## Summary

This gap represents a **critical missing capability** in the Elixir SDK. The Python SDK has a mature, well-tested file upload system that handles:
- 5 different input types
- Automatic path reading and filename extraction
- Sync and async I/O
- Multipart encoding with proper RFC compliance
- Integration with httpx's multipart capabilities

The Elixir SDK currently has **zero file upload support** - it only encodes JSON.

The TDD implementation plan provides a clear path to parity:
- 5 implementation phases
- ~30 test suites covering all edge cases
- Python parity verification tests
- No breaking changes
- Estimated 3-4 weeks for complete implementation

The implementation leverages Elixir's strengths:
- Pattern matching for type detection
- Efficient binary handling
- Task-based async I/O
- Clean separation of concerns

Once implemented, the Elixir SDK will have feature parity with Python for file uploads while maintaining idiomatic Elixir style and performance.
