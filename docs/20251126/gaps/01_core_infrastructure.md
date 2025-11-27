# Core Infrastructure Gap Analysis: Python tinker → Elixir tinkex

**Analysis Date:** November 26, 2025
**Domain:** Core Infrastructure (HTTP Client, Base Client, Response Handling, Types, Files)
**Status:** COMPREHENSIVE

---

## 1. Executive Summary

### Overall Completeness: ~35%

The Elixir tinkex port has implemented basic HTTP functionality but is missing the majority of Python tinker's sophisticated core infrastructure features. The implementation is significantly incomplete.

### Gap Counts

- **Critical Gaps:** 28
- **High Priority Gaps:** 35
- **Medium Priority Gaps:** 18
- **Low Priority Gaps:** 12
- **Total Gaps:** 93

### Summary Assessment

The Elixir implementation provides basic REST API functionality with retry logic and error handling, but lacks:
- Complete base client abstraction (sync/async patterns)
- Sophisticated response parsing and type construction
- File upload/multipart handling
- Pagination infrastructure
- Streaming (SSE) support
- Advanced request options (custom headers, query params merging)
- Pydantic-style validation and type coercion
- Platform detection and user-agent construction
- Connection pooling configuration (partial - uses Finch)

---

## 2. Feature-by-Feature Comparison

| Feature | Python Implementation | Elixir Implementation | Gap Status |
|---------|----------------------|----------------------|------------|
| **Base Client Architecture** | | | |
| BaseClient class | Abstract base with sync/async variants | Tinkex.API (single implementation) | ❌ Missing |
| AsyncAPIClient | Full async implementation | N/A (BEAM is async by default) | ⚠️ Partial |
| HTTP/2 support | Via httpx with http2=True | Via Finch (supports HTTP/2) | ✅ Complete |
| Custom HTTP client injection | Supported via http_client param | Not supported | ❌ Missing |
| Connection pooling | DEFAULT_CONNECTION_LIMITS | Finch pools configured in Application | ⚠️ Partial |
| Timeout configuration | float \| Timeout \| None | pos_integer (ms only) | ⚠️ Partial |
| Max retries configuration | DEFAULT_MAX_RETRIES=2 | max_retries in Config | ✅ Complete |
| Base URL enforcement | Trailing slash enforcement | Basic normalization | ⚠️ Partial |
| Custom headers/query | Merged with defaults | Supported via opts | ✅ Complete |
| | | | |
| **Request Building** | | | |
| _build_request() | Comprehensive request builder | Basic Finch.build() calls | ⚠️ Partial |
| _prepare_url() | Sophisticated URL merging | build_url() with basic merging | ⚠️ Partial |
| _build_headers() | Full header construction | build_headers() with basics | ⚠️ Partial |
| Idempotency key generation | UUID-based, automatic | Crypto-based, automatic | ✅ Complete |
| Idempotency header | Optional, configurable | X-Idempotency-Key | ✅ Complete |
| Platform headers | X-Stainless-* headers | X-Stainless-* headers | ✅ Complete |
| Custom auth support | Via custom_auth property | Not supported | ❌ Missing |
| Query string serialization | Querystring class with array formats | Basic query params | ⚠️ Partial |
| Multipart/form-data | Full support with file handling | Not implemented | ❌ Missing |
| File uploads | HttpxRequestFiles with PathLike | Not implemented | ❌ Missing |
| Content-Type override | Automatic for multipart | Basic JSON only | ❌ Missing |
| | | | |
| **Retry Logic** | | | |
| _should_retry() | Status-based with x-should-retry | Status-based with x-should-retry | ✅ Complete |
| _calculate_retry_timeout() | Exponential backoff with jitter | Exponential backoff with jitter | ✅ Complete |
| Retry-After header parsing | Seconds, milliseconds, HTTP-date | Seconds, milliseconds | ⚠️ Partial |
| Max retry duration | Implicit via retries | 30s hardcoded | ⚠️ Partial |
| Retry count header | x-stainless-retry-count | x-stainless-retry-count | ✅ Complete |
| Timeout on retry | 408, 429, 500+ | 408, 429, 500+ | ✅ Complete |
| Lock timeout retry | 409 status | Not explicitly handled | ❌ Missing |
| | | | |
| **Response Handling** | | | |
| BaseAPIResponse | Generic response wrapper | Not implemented | ❌ Missing |
| APIResponse (sync) | Full sync response | Not implemented | ❌ Missing |
| AsyncAPIResponse | Full async response | Not implemented | ❌ Missing |
| Response.parse() | Type-safe parsing with validation | Basic Jason.decode | ❌ Missing |
| Response.read() | Binary content reading | Not implemented | ❌ Missing |
| Response.text() | Text decoding | Not implemented | ❌ Missing |
| Response.json() | JSON parsing | Implicit only | ⚠️ Partial |
| Response metadata | status_code, headers, url, etc. | Not exposed | ❌ Missing |
| Response streaming | iter_bytes, iter_text, iter_lines | Not implemented | ❌ Missing |
| BinaryAPIResponse | Binary response helpers | Not implemented | ❌ Missing |
| write_to_file() | Direct file writing | Not implemented | ❌ Missing |
| stream_to_file() | Streaming file writes | Not implemented | ❌ Missing |
| Raw response access | Via RAW_RESPONSE_HEADER | Via :raw_response? opt | ⚠️ Partial |
| Streaming response wrapper | with_streaming_response | Not implemented | ❌ Missing |
| Response context managers | ResponseContextManager | Not implemented | ❌ Missing |
| | | | |
| **Type System** | | | |
| NotGiven sentinel | NotGiven class | Not implemented | ❌ Missing |
| Omit for header removal | Omit class | Not implemented | ❌ Missing |
| ResponseT type variance | Complex TypeVar bounds | Basic types | ⚠️ Partial |
| RequestOptions TypedDict | Comprehensive options | keyword() lists | ⚠️ Partial |
| FileTypes unions | Complex file type support | Not implemented | ❌ Missing |
| ProxiesTypes | Proxy configuration types | Not implemented | ❌ Missing |
| Transport types | BaseTransport/AsyncBaseTransport | Not applicable (uses Finch) | N/A |
| Headers type | Mapping with Omit support | Basic keyword list | ⚠️ Partial |
| ModelBuilderProtocol | Custom model construction | Not implemented | ❌ Missing |
| NoneType support | Type[None] for cast_to | Not needed | N/A |
| | | | |
| **Data Processing** | | | |
| _process_response_data() | Pydantic validation/construction | Basic data passthrough | ❌ Missing |
| Type construction | construct_type() from _models | Not implemented | ❌ Missing |
| Type validation | validate_type() with strict mode | Not implemented | ❌ Missing |
| Custom type casting | cast_to parameter | Not implemented | ❌ Missing |
| Stream type extraction | extract_stream_chunk_type() | Not implemented | ❌ Missing |
| BaseModel subclass check | issubclass validation | Not implemented | ❌ Missing |
| Content-Type validation | Strict mode validation | Basic JSON check | ⚠️ Partial |
| JSON parsing errors | APIResponseValidationError | Generic error | ⚠️ Partial |
| | | | |
| **Pagination** | | | |
| PageInfo | url/params/json next page info | Not implemented | ❌ Missing |
| BasePage | Generic pagination base | Not implemented | ❌ Missing |
| AsyncPaginator | Async pagination iterator | Not implemented | ❌ Missing |
| BaseAsyncPage | Async page implementation | Not implemented | ❌ Missing |
| has_next_page() | Check for next page | Not implemented | ❌ Missing |
| next_page_info() | Get next page info | Not implemented | ❌ Missing |
| get_next_page() | Fetch next page | Not implemented | ❌ Missing |
| iter_pages() | Page iteration | Not implemented | ❌ Missing |
| _get_page_items() | Extract page items | Not implemented | ❌ Missing |
| _params_from_url() | Parse URL params | Not implemented | ❌ Missing |
| _request_api_list() | List request helper | Not implemented | ❌ Missing |
| get_api_list() | Public API list method | Not implemented | ❌ Missing |
| | | | |
| **Streaming (SSE)** | | | |
| Stream class | Sync SSE stream | Not implemented | ❌ Missing |
| AsyncStream class | Async SSE stream | Not implemented | ❌ Missing |
| SSEDecoder | Server-Sent Events decoder | Not implemented | ❌ Missing |
| SSEBytesDecoder | Binary SSE decoder | Not implemented | ❌ Missing |
| _make_sse_decoder() | Decoder factory | Not implemented | ❌ Missing |
| _should_stream_response_body() | Stream detection | Not implemented | ❌ Missing |
| _default_stream_cls | Default stream class | Not implemented | ❌ Missing |
| is_stream_class_type() | Type checking | Not implemented | ❌ Missing |
| | | | |
| **File Handling** | | | |
| to_httpx_files() | File transformation | Not implemented | ❌ Missing |
| async_to_httpx_files() | Async file transformation | Not implemented | ❌ Missing |
| _transform_file() | Single file transform | Not implemented | ❌ Missing |
| read_file_content() | Sync file reading | Not implemented | ❌ Missing |
| async_read_file_content() | Async file reading | Not implemented | ❌ Missing |
| is_file_content() | Type guard | Not implemented | ❌ Missing |
| is_base64_file_input() | Base64 detection | Not implemented | ❌ Missing |
| PathLike support | os.PathLike handling | Not implemented | ❌ Missing |
| File tuple formats | 4 different tuple formats | Not implemented | ❌ Missing |
| | | | |
| **Error Handling** | | | |
| APIStatusError | HTTP status errors | Tinkex.Error with status | ⚠️ Partial |
| APIConnectionError | Connection errors | Error type :api_connection | ✅ Complete |
| APITimeoutError | Timeout errors | Error type :api_timeout | ✅ Complete |
| APIResponseValidationError | Validation errors | Error type :validation | ✅ Complete |
| TinkerError base | Base error class | Tinkex.Error struct | ⚠️ Partial |
| _make_status_error() | Abstract status error factory | _make_status_error() implemented | ✅ Complete |
| _make_status_error_from_response() | Response error construction | from_response() | ✅ Complete |
| Error categorization | user/server/unknown | RequestErrorCategory | ✅ Complete |
| Specific status errors | 400, 401, 403, 404, 409, 422, 429, 500+ | Via _make_status_error | ✅ Complete |
| Error body parsing | JSON error bodies | decode_error_body() | ✅ Complete |
| retry_after_ms in error | Retry delay in error | retry_after_ms field | ✅ Complete |
| | | | |
| **Client Configuration** | | | |
| api_key | Required, env fallback | Required, env fallback | ✅ Complete |
| base_url | Required, env fallback | Required, env fallback | ✅ Complete |
| timeout | float \| Timeout \| None | pos_integer (ms) | ⚠️ Partial |
| max_retries | int (unlimited=math.inf) | non_neg_integer | ⚠️ Partial |
| default_headers | Mapping[str, str] | Not in Config | ❌ Missing |
| default_query | Mapping[str, object] | Not in Config | ❌ Missing |
| http_client | Custom httpx.AsyncClient | http_pool atom | ⚠️ Partial |
| _strict_response_validation | bool for validation mode | Not implemented | ❌ Missing |
| custom_auth | httpx.Auth | Not supported | ❌ Missing |
| Platform detection | get_platform() | Not implemented | ❌ Missing |
| Architecture detection | get_architecture() | stainless_arch() | ✅ Complete |
| Python version | platform.python_version() | Elixir/OTP version | ✅ Complete |
| | | | |
| **Client Methods** | | | |
| get() | Full implementation | Basic implementation | ⚠️ Partial |
| post() | Full implementation | Basic implementation | ⚠️ Partial |
| patch() | Full implementation | Not implemented | ❌ Missing |
| put() | Full implementation | Not implemented | ❌ Missing |
| delete() | Full implementation | Basic implementation | ⚠️ Partial |
| request() | Generic request method | Not implemented | ❌ Missing |
| _prepare_options() | Hook for option mutation | Not implemented | ❌ Missing |
| _prepare_request() | Hook for request mutation | Not implemented | ❌ Missing |
| close() | Client cleanup | Not needed (BEAM) | N/A |
| __aenter__/__aexit__ | Context manager support | Not applicable | N/A |
| with_options() | Client copying | Not implemented | ❌ Missing |
| copy() | Client duplication | Not implemented | ❌ Missing |
| | | | |
| **Response Wrappers** | | | |
| with_raw_response | Raw response property | Not implemented | ❌ Missing |
| with_streaming_response | Streaming response property | Not implemented | ❌ Missing |
| to_raw_response_wrapper() | Function wrapper | Not implemented | ❌ Missing |
| async_to_raw_response_wrapper() | Async wrapper | Not implemented | ❌ Missing |
| to_streamed_response_wrapper() | Stream wrapper | Not implemented | ❌ Missing |
| async_to_streamed_response_wrapper() | Async stream wrapper | Not implemented | ❌ Missing |
| to_custom_raw_response_wrapper() | Custom response wrapper | Not implemented | ❌ Missing |
| to_custom_streamed_response_wrapper() | Custom stream wrapper | Not implemented | ❌ Missing |
| | | | |
| **Version Management** | | | |
| __version__ | importlib.metadata.version | Mix.Project.config[:version] | ✅ Complete |
| Version module | _version.py | Tinkex.Version | ✅ Complete |
| | | | |
| **Compatibility Layer** | | | |
| Pydantic V1/V2 compat | PYDANTIC_V2 flag + shims | Not applicable | N/A |
| parse_obj() | V1/V2 unified | Not applicable | N/A |
| model_dump() | V1/V2 unified | Not applicable | N/A |
| model_copy() | V1/V2 unified | Not applicable | N/A |
| field helpers | field_is_required(), etc. | Not applicable | N/A |
| cached_property | Compatibility wrapper | Not needed | N/A |
| GenericModel | Pydantic generic base | Not applicable | N/A |
| | | | |
| **Resource Pattern** | | | |
| AsyncAPIResource | Resource base class | Not implemented | ❌ Missing |
| _client reference | Client injection | Not implemented | ❌ Missing |
| HTTP method shortcuts | _get, _post, etc. | Not implemented | ❌ Missing |
| _sleep() helper | anyio.sleep wrapper | Not implemented | ❌ Missing |
| | | | |
| **Misc Infrastructure** | | | |
| ForceMultipartDict | Empty dict that evaluates True | Not needed | N/A |
| _merge_mappings() | Mapping merge with Omit | Not implemented | ❌ Missing |
| _serialize_multipartform() | Form serialization | Not implemented | ❌ Missing |
| _maybe_override_cast_to() | Cast type override | Not implemented | ❌ Missing |
| user_agent property | Dynamic user agent | Static from config | ⚠️ Partial |
| platform_headers() | Cached header generation | stainless_headers() | ✅ Complete |
| qs property | Querystring instance | Not exposed | ⚠️ Partial |

---

## 3. Detailed Gap Analysis

### GAP-CORE-001: Base Client Architecture
**Severity:** Critical
**Python Feature:** Abstract `BaseClient` class with sync/async variants, sophisticated lifecycle management
**Elixir Status:** Single `Tinkex.API` module without abstraction layers
**What's Missing:**
- No base client abstraction
- No sync/async distinction (BEAM handles this differently)
- No client lifecycle management (open/close)
- No custom HTTP client injection

**Implementation Notes:**
- Elixir's BEAM VM handles concurrency differently than Python's async/await
- Consider whether a base behavior/protocol is needed
- Finch client injection could be supported via config

### GAP-CORE-002: Request Building Infrastructure
**Severity:** Critical
**Python Feature:** Comprehensive `_build_request()` with multipart, file uploads, content-type detection
**Elixir Status:** Basic `Finch.build()` calls with JSON only
**What's Missing:**
- Multipart/form-data support
- File upload handling
- Dynamic content-type detection
- Request body serialization for non-JSON payloads
- SNI hostname workaround for underscore in hostnames

**Implementation Notes:**
```elixir
# Need to implement:
defmodule Tinkex.RequestBuilder do
  def build(method, url, headers, body, opts) do
    # Handle multipart
    # Handle files
    # Set appropriate content-type
    # Build Finch.Request
  end
end
```

### GAP-CORE-003: Response Parsing and Type Construction
**Severity:** Critical
**Python Feature:** `_process_response_data()` with Pydantic validation, type construction, strict mode
**Elixir Status:** Direct JSON decoding with no validation
**What's Missing:**
- Type validation against expected schemas
- Type construction (building structs from maps)
- Strict vs. lenient parsing modes
- Custom model builder protocol
- BaseModel subclass checking

**Implementation Notes:**
```elixir
# Need to implement:
defmodule Tinkex.TypeBuilder do
  def construct_type(type, data) do
    # Use Ecto.Changeset or similar for validation
    # Support custom builders
    # Handle union types
  end

  def validate_type(type, data, strict: true) do
    # Strict validation mode
  end
end
```

### GAP-CORE-004: Response Wrapper Classes
**Severity:** High
**Python Feature:** `APIResponse`, `AsyncAPIResponse`, `BinaryAPIResponse` with rich methods
**Elixir Status:** Direct map/struct returns
**What's Missing:**
- Response object abstraction
- `parse()`, `read()`, `text()`, `json()` methods
- Response metadata access (status, headers, url, etc.)
- Binary response helpers
- File writing helpers (write_to_file, stream_to_file)
- Response caching by type

**Implementation Notes:**
```elixir
defmodule Tinkex.Response do
  defstruct [:raw, :cast_to, :client, :options, :parsed_by_type]

  def parse(%__MODULE__{} = resp, to: type) do
    # Parse with type coercion
  end

  def read(%__MODULE__{} = resp) do
    # Return binary content
  end

  def text(%__MODULE__{} = resp) do
    # Return decoded text
  end
end
```

### GAP-CORE-005: Pagination Infrastructure
**Severity:** High
**Python Feature:** Complete pagination with `PageInfo`, `BasePage`, `AsyncPaginator`
**Elixir Status:** Not implemented
**What's Missing:**
- PageInfo for next page construction
- BasePage generic pagination base
- Paginator for iteration
- has_next_page(), next_page_info(), get_next_page()
- Async iteration over pages and items
- _request_api_list() helper

**Implementation Notes:**
```elixir
defmodule Tinkex.Pagination do
  defmodule PageInfo do
    defstruct [:url, :params, :json]
  end

  defmodule Page do
    @callback has_next_page?() :: boolean()
    @callback next_page_info() :: PageInfo.t() | nil
    @callback items() :: [term()]
  end

  def paginate(client, request, opts) do
    # Return Stream that fetches pages lazily
  end
end
```

### GAP-CORE-006: Server-Sent Events (SSE) Streaming
**Severity:** High
**Python Feature:** `Stream`, `AsyncStream`, `SSEDecoder` for real-time streaming
**Elixir Status:** Not implemented
**What's Missing:**
- SSE protocol decoder
- Stream/AsyncStream classes
- Event parsing and yielding
- Stream chunk type extraction
- _should_stream_response_body() detection
- Default stream class configuration

**Implementation Notes:**
```elixir
defmodule Tinkex.SSE do
  defmodule Stream do
    defstruct [:response, :cast_to, :client]

    def stream(%__MODULE__{} = stream) do
      # Return Elixir Stream that yields SSE events
    end
  end

  defmodule Decoder do
    def decode(chunk) do
      # Parse SSE format: "data: {...}\n\n"
    end
  end
end
```

### GAP-CORE-007: File Upload and Multipart Handling
**Severity:** High
**Python Feature:** Comprehensive file handling in `_files.py`
**Elixir Status:** Not implemented
**What's Missing:**
- to_httpx_files() file transformation
- Multiple file tuple formats support
- PathLike file path handling
- Async file reading
- File content type detection
- Multipart form encoding

**Implementation Notes:**
```elixir
defmodule Tinkex.Files do
  def to_multipart(files) do
    # Transform files to multipart format
    # Support: binary, {name, binary}, {name, binary, content_type}, {name, binary, content_type, headers}
    # Support Path for file paths
  end

  def read_file(path) do
    # Sync file reading
  end

  def read_file_async(path) do
    # Could use File.stream! for large files
  end
end
```

### GAP-CORE-008: NotGiven and Omit Sentinels
**Severity:** Medium
**Python Feature:** `NotGiven` and `Omit` sentinel classes for optional vs. removal
**Elixir Status:** Not implemented
**What's Missing:**
- Distinguish between "not provided" and "explicitly nil"
- Header removal mechanism
- Type-safe optional parameters

**Implementation Notes:**
```elixir
defmodule Tinkex.Sentinel do
  defmodule NotGiven do
    # Singleton for "not provided"
  end

  defmodule Omit do
    # Singleton for "remove this"
  end

  def is_given?(NotGiven), do: false
  def is_given?(_), do: true

  def merge_headers(base, custom) do
    # Remove headers marked with Omit
  end
end
```

### GAP-CORE-009: Query String Serialization
**Severity:** Medium
**Python Feature:** `Querystring` class with array format support
**Elixir Status:** Basic query param passing
**What's Missing:**
- Array format options (comma, brackets, etc.)
- stringify_items() for multipart
- Nested parameter serialization
- Query param merging logic

**Implementation Notes:**
```elixir
defmodule Tinkex.QueryString do
  @array_formats [:comma, :brackets, :indices]

  def stringify(params, array_format: format) do
    # foo: [1, 2] -> "foo=1,2" (comma)
    # foo: [1, 2] -> "foo[]=1&foo[]=2" (brackets)
    # foo: [1, 2] -> "foo[0]=1&foo[1]=2" (indices)
  end
end
```

### GAP-CORE-010: Timeout Type Flexibility
**Severity:** Medium
**Python Feature:** `float | Timeout | None` with read/write/connect/pool timeouts
**Elixir Status:** Single `pos_integer()` in milliseconds
**What's Missing:**
- Read timeout
- Write timeout
- Connect timeout
- Pool timeout
- None for no timeout
- httpx.Timeout object equivalent

**Implementation Notes:**
```elixir
defmodule Tinkex.Timeout do
  defstruct [:read, :write, :connect, :pool]

  @type t :: pos_integer() | %__MODULE__{} | nil

  def to_finch_opts(%__MODULE__{} = timeout) do
    # Convert to Finch timeout options
  end

  def to_finch_opts(ms) when is_integer(ms) do
    [receive_timeout: ms]
  end
end
```

### GAP-CORE-011: Custom Authentication Support
**Severity:** Medium
**Python Feature:** `custom_auth` property for httpx.Auth
**Elixir Status:** Hardcoded API key in headers
**What's Missing:**
- Custom auth callback/module
- OAuth support
- Bearer token support
- Auth header customization

**Implementation Notes:**
```elixir
defmodule Tinkex.Auth do
  @callback auth_headers(Config.t()) :: [{String.t(), String.t()}]

  defmodule ApiKey do
    @behaviour Tinkex.Auth
    def auth_headers(config), do: [{"x-api-key", config.api_key}]
  end

  defmodule Bearer do
    @behaviour Tinkex.Auth
    def auth_headers(config), do: [{"authorization", "Bearer #{config.token}"}]
  end
end
```

### GAP-CORE-012: Response Context Managers
**Severity:** Medium
**Python Feature:** `ResponseContextManager`, `AsyncResponseContextManager`
**Elixir Status:** Not implemented
**What's Missing:**
- Lazy request execution
- Automatic response cleanup
- Context manager pattern

**Implementation Notes:**
```elixir
# Elixir doesn't have context managers, but we can use functions with blocks:

defmodule Tinkex.ResponseManager do
  def with_response(request_fn, callback) do
    response = request_fn.()
    try do
      callback.(response)
    after
      # Cleanup if needed
    end
  end
end

# Usage:
ResponseManager.with_response(
  fn -> client.get("/path") end,
  fn resp ->
    # Use response
  end
)
```

### GAP-CORE-013: Response Wrapper Functions
**Severity:** Medium
**Python Feature:** `to_raw_response_wrapper()`, `to_streamed_response_wrapper()`, etc.
**Elixir Status:** Not implemented
**What's Missing:**
- Function decorators for response wrapping
- with_raw_response property
- with_streaming_response property
- Custom response class injection

**Implementation Notes:**
```elixir
defmodule Tinkex.ResponseWrapper do
  def with_raw_response(module) do
    # Create wrapped version of all functions that returns raw response
  end

  def with_streaming_response(module) do
    # Create wrapped version that returns streaming response
  end
end

# Could use macros to generate wrapped versions:
defmacro __using__(_opts) do
  quote do
    def with_raw_response do
      Tinkex.ResponseWrapper.wrap_module(__MODULE__, :raw)
    end
  end
end
```

### GAP-CORE-014: Client Method Variants
**Severity:** Medium
**Python Feature:** `patch()`, `put()`, generic `request()` method
**Elixir Status:** Only `get()`, `post()`, `delete()`
**What's Missing:**
- PATCH method
- PUT method
- Generic request() method with method parameter
- Method-specific overloads with type safety

**Implementation Notes:**
```elixir
# Add to Tinkex.API:

def patch(path, body, opts) do
  # Implement PATCH
end

def put(path, body, opts) do
  # Implement PUT
end

def request(method, path, opts) when method in [:get, :post, :patch, :put, :delete] do
  # Generic request
end
```

### GAP-CORE-015: Request/Response Hook Methods
**Severity:** Low
**Python Feature:** `_prepare_options()`, `_prepare_request()` hooks
**Elixir Status:** Not implemented
**What's Missing:**
- Pre-request option mutation hook
- Pre-request mutation hook (for adding headers based on URL, etc.)
- Hook system for extending behavior

**Implementation Notes:**
```elixir
defmodule Tinkex.Hooks do
  @callback prepare_options(FinalRequestOptions.t()) :: FinalRequestOptions.t()
  @callback prepare_request(Finch.Request.t()) :: Finch.Request.t()
end

# In Config:
defstruct [..., :hooks]

# In API:
defp apply_hooks(request, opts, config) do
  if config.hooks do
    config.hooks.prepare_request(request)
  else
    request
  end
end
```

### GAP-CORE-016: Client Copying and with_options
**Severity:** Low
**Python Feature:** `copy()` and `with_options()` for client duplication
**Elixir Status:** Not implemented
**What's Missing:**
- Client duplication
- Option merging for temporary overrides
- Immutable client pattern

**Implementation Notes:**
```elixir
defmodule Tinkex.Client do
  def with_options(config, opts) do
    # Merge opts into config, return new config
    struct(config, opts)
  end

  def copy(config, opts \\ []) do
    # Full copy with optional overrides
    config
    |> Map.from_struct()
    |> Map.merge(Map.new(opts))
    |> then(&struct(Tinkex.Config, &1))
  end
end
```

### GAP-CORE-017: Strict Response Validation Mode
**Severity:** Medium
**Python Feature:** `_strict_response_validation` flag
**Elixir Status:** Not implemented
**What's Missing:**
- Strict validation mode toggle
- Validation vs. construction choice
- Content-Type enforcement in strict mode

**Implementation Notes:**
```elixir
# Add to Config:
defstruct [..., :strict_response_validation]

# In response handling:
def parse_response(data, type, config) do
  if config.strict_response_validation do
    validate_type(type, data)
  else
    construct_type(type, data)
  end
end
```

### GAP-CORE-018: Platform Detection
**Severity:** Low
**Python Feature:** `get_platform()` with iOS, Android, FreeBSD, etc. detection
**Elixir Status:** Basic OS detection
**What's Missing:**
- iOS detection
- Android detection
- Detailed Linux distribution detection
- OtherPlatform handling

**Implementation Notes:**
```elixir
defmodule Tinkex.Platform do
  def detect do
    case :os.type() do
      {:unix, :darwin} -> detect_darwin()
      {:unix, :linux} -> detect_linux()
      {:unix, :freebsd} -> "FreeBSD"
      {:unix, :openbsd} -> "OpenBSD"
      {:win32, _} -> "Windows"
      other -> {:other, inspect(other)}
    end
  end

  defp detect_darwin do
    # Check for iOS via uname -a
  end

  defp detect_linux do
    # Check for Android
    # Use distro detection
  end
end
```

### GAP-CORE-019: Default Headers and Query Configuration
**Severity:** Medium
**Python Feature:** `default_headers`, `default_query` in client config
**Elixir Status:** Not in Config struct
**What's Missing:**
- Default headers in config
- Default query params in config
- Header/query merging in requests

**Implementation Notes:**
```elixir
# Add to Config:
defstruct [..., :default_headers, :default_query]

# In build_headers:
defp build_headers(method, config, opts, timeout_ms) do
  base_headers()
  |> merge_headers(config.default_headers)
  |> merge_headers(opts[:headers])
  |> dedupe_headers()
end
```

### GAP-CORE-020: Error Exception Hierarchy
**Severity:** Medium
**Python Feature:** Specific exception classes for each error type
**Elixir Status:** Single Error struct with type field
**What's Missing:**
- BadRequestError (400)
- AuthenticationError (401)
- PermissionDeniedError (403)
- NotFoundError (404)
- ConflictError (409)
- UnprocessableEntityError (422)
- RateLimitError (429)
- InternalServerError (500+)

**Implementation Notes:**
```elixir
# Elixir approach - pattern match on status:
def handle_error(%Error{status: 400} = err), do: {:error, :bad_request, err}
def handle_error(%Error{status: 401} = err), do: {:error, :authentication, err}
# etc.

# Or create exception modules:
defmodule Tinkex.BadRequestError do
  defexception [:message, :response, :body]
end

# Then raise in _make_status_error:
defp _make_status_error(err_msg, body: body, response: response) do
  case response.status do
    400 -> raise Tinkex.BadRequestError, message: err_msg, response: response, body: body
    401 -> raise Tinkex.AuthenticationError, message: err_msg, response: response, body: body
    # etc.
  end
end
```

### GAP-CORE-021: Lock Timeout Retry (409)
**Severity:** Low
**Python Feature:** Retry on 409 Conflict status
**Elixir Status:** Not explicitly handled
**What's Missing:**
- 409 status in retry logic

**Implementation Notes:**
```elixir
# In retry_decision:
defp status_based_decision(409, _headers, attempt),
  do: {:retry, retry_delay(attempt)}
```

### GAP-CORE-022: HTTP-Date Parsing in Retry-After
**Severity:** Low
**Python Feature:** `email.utils.parsedate_tz()` for HTTP-date format
**Elixir Status:** Only parses integers
**What's Missing:**
- HTTP-date format parsing (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")

**Implementation Notes:**
```elixir
defp parse_retry_after_date(headers) do
  case normalized_header(headers, "retry-after") do
    nil -> nil
    value ->
      # Try to parse as HTTP-date
      case Timex.parse(value, "{RFC1123}") do
        {:ok, datetime} ->
          DateTime.diff(datetime, DateTime.utc_now(), :millisecond)
        _ ->
          nil
      end
  end
end
```

### GAP-CORE-023: SNI Hostname Workaround
**Severity:** Low
**Python Feature:** Underscore in hostname workaround
**Elixir Status:** Not implemented
**What's Missing:**
- SNI hostname override for hostnames with underscores

**Implementation Notes:**
```elixir
defp build_request(url, headers, body) do
  uri = URI.parse(url)

  extensions =
    if String.contains?(uri.host, "_") do
      [sni_hostname: String.replace(uri.host, "_", "-")]
    else
      []
    end

  Finch.build(:post, url, headers, body, extensions: extensions)
end
```

### GAP-CORE-024: Max Retries Unlimited Support
**Severity:** Low
**Python Feature:** `math.inf` for unlimited retries
**Elixir Status:** Only non_neg_integer
**What's Missing:**
- Unlimited retries option
- Very high number as substitute

**Implementation Notes:**
```elixir
# Use :infinity atom:
@type max_retries :: non_neg_integer() | :infinity

defp do_retry(context, attempt) do
  if context.max_retries == :infinity or attempt < context.max_retries do
    # Continue retrying
  else
    # Stop
  end
end
```

### GAP-CORE-025: AsyncResource Base Class
**Severity:** Low
**Python Feature:** `AsyncAPIResource` with client shortcuts
**Elixir Status:** Not implemented
**What's Missing:**
- Base module for resource implementations
- Client reference injection
- HTTP method shortcuts (_get, _post, etc.)
- _sleep() helper

**Implementation Notes:**
```elixir
defmodule Tinkex.Resource do
  defmacro __using__(opts) do
    quote do
      @client nil

      def set_client(client), do: @client = client

      defp http_get(path, opts), do: Tinkex.API.get(path, [{:config, @client.config} | opts])
      defp http_post(path, body, opts), do: Tinkex.API.post(path, body, [{:config, @client.config} | opts])
      # etc.

      defp sleep(ms), do: Process.sleep(ms)
    end
  end
end
```

### GAP-CORE-026: Header Merging with Omit
**Severity:** Low
**Python Feature:** `_merge_mappings()` that removes `Omit` values
**Elixir Status:** Basic header merging
**What's Missing:**
- Omit sentinel for removing headers
- Merging that respects removal

**Implementation Notes:**
```elixir
defmodule Tinkex.Omit, do: defstruct []

def merge_headers(base, custom) do
  merged = Keyword.merge(base, custom)
  Enum.reject(merged, fn {_k, v} -> match?(%Tinkex.Omit{}, v) end)
end
```

### GAP-CORE-027: Serialization for Multipart
**Severity:** Low
**Python Feature:** `_serialize_multipartform()` with array handling
**Elixir Status:** Not implemented
**What's Missing:**
- Multipart form serialization
- Array handling for multipart (multiple values for same key)

**Implementation Notes:**
```elixir
def serialize_multipart(data, array_format: format) do
  data
  |> QueryString.stringify_items(array_format: format)
  |> Enum.reduce(%{}, fn {key, value}, acc ->
    case Map.get(acc, key) do
      nil -> Map.put(acc, key, value)
      existing when is_list(existing) -> Map.put(acc, key, existing ++ [value])
      existing -> Map.put(acc, key, [existing, value])
    end
  end)
end
```

### GAP-CORE-028: Cast-To Type Override
**Severity:** Low
**Python Feature:** `_maybe_override_cast_to()` with `OVERRIDE_CAST_TO_HEADER`
**Elixir Status:** Not implemented
**What's Missing:**
- Temporary cast-to type override via header
- Support for with_raw_response and with_streaming_response

**Implementation Notes:**
```elixir
@override_cast_to_header "x-stainless-override-cast-to"

defp maybe_override_cast_to(cast_to, opts) do
  case Keyword.get(opts, :headers, []) do
    headers when is_list(headers) ->
      case List.keyfind(headers, @override_cast_to_header, 0) do
        {_, override_type} -> override_type
        nil -> cast_to
      end
    _ ->
      cast_to
  end
end
```

---

## 4. Python Features Inventory

### _base_client.py (1469 lines)

#### Classes

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| PageInfo | Next page information | ❌ Missing |
| BasePage | Generic pagination base | ❌ Missing |
| AsyncPaginator | Async page iterator | ❌ Missing |
| BaseAsyncPage | Async page implementation | ❌ Missing |
| BaseClient | Abstract base client | ⚠️ Tinkex.API (not abstract) |
| AsyncAPIClient | Async HTTP client | ⚠️ Tinkex.API |
| _DefaultAsyncHttpxClient | Default httpx client | N/A (uses Finch) |
| _DefaultAioHttpClient | Aiohttp transport | N/A |
| AsyncHttpxClientWrapper | Client wrapper | N/A |
| ForceMultipartDict | Empty dict for multipart | ❌ Missing |
| OtherPlatform | Unknown platform | ❌ Missing |
| OtherArch | Unknown architecture | ❌ Missing |

#### Constants

| Name | Value | Elixir Equivalent |
|------|-------|-------------------|
| DEFAULT_MAX_RETRIES | 2 | @default_max_retries 2 ✅ |
| DEFAULT_TIMEOUT | Timeout(60.0) | @default_timeout 120_000 ⚠️ |
| DEFAULT_CONNECTION_LIMITS | httpx.Limits(...) | Finch pool config ⚠️ |
| INITIAL_RETRY_DELAY | 0.5 | @initial_retry_delay 500 ✅ |
| MAX_RETRY_DELAY | 8.0 | @max_retry_delay 8_000 ✅ |
| OVERRIDE_CAST_TO_HEADER | "x-stainless-override-cast-to" | ❌ Missing |
| RAW_RESPONSE_HEADER | "x-stainless-raw-response" | ⚠️ Via :raw_response? |

#### Functions

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| make_request_options() | Build RequestOptions dict | ❌ Missing |
| get_platform() | Detect OS platform | ⚠️ stainless_os() |
| platform_headers() | Generate platform headers | ✅ stainless_headers() |
| get_python_runtime() | Get Python implementation | ✅ "BEAM" |
| get_python_version() | Get Python version | ✅ Elixir/OTP version |
| get_architecture() | Get CPU architecture | ✅ stainless_arch() |
| _merge_mappings() | Merge dicts with Omit | ❌ Missing |

#### BaseClient Methods

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| __init__() | Initialize client | Config.new() ⚠️ |
| _enforce_trailing_slash() | Ensure URL ends with / | PoolKey.normalize_base_url() ⚠️ |
| _make_status_error_from_response() | Create error from response | from_response() ✅ |
| _make_status_error() | Abstract error factory | _make_status_error() ✅ |
| _build_headers() | Build request headers | build_headers() ⚠️ |
| _prepare_url() | Merge base URL with path | build_url() ⚠️ |
| _make_sse_decoder() | Create SSE decoder | ❌ Missing |
| _build_request() | Build httpx.Request | Finch.build() ⚠️ |
| _serialize_multipartform() | Serialize multipart data | ❌ Missing |
| _maybe_override_cast_to() | Override response type | ❌ Missing |
| _should_stream_response_body() | Check if streaming | ❌ Missing |
| _process_response_data() | Parse response data | ❌ Missing |
| qs (property) | Querystring instance | ❌ Missing |
| custom_auth (property) | Custom auth | ❌ Missing |
| auth_headers (property) | Auth headers | auth_headers() ✅ |
| default_headers (property) | Default headers | build_headers() ⚠️ |
| default_query (property) | Default query params | ❌ Missing |
| _validate_headers() | Validate headers | ❌ Missing |
| user_agent (property) | User agent string | user_agent() ⚠️ |
| base_url (property) | Base URL getter | config.base_url ✅ |
| base_url (setter) | Base URL setter | ❌ Missing |
| platform_headers() | Platform headers | stainless_headers() ✅ |
| _parse_retry_after_header() | Parse Retry-After | parse_retry_after() ⚠️ |
| _calculate_retry_timeout() | Calculate retry delay | retry_delay() ✅ |
| _should_retry() | Check if retryable | retry_decision() ✅ |
| _idempotency_key() | Generate idempotency key | build_idempotency_key() ✅ |

#### AsyncAPIClient Methods

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| __init__() | Initialize async client | Config.new() ⚠️ |
| is_closed() | Check if client closed | N/A |
| close() | Close HTTP client | N/A |
| __aenter__() | Context manager enter | N/A |
| __aexit__() | Context manager exit | N/A |
| _prepare_options() | Prepare request options | ❌ Missing |
| _prepare_request() | Prepare request | ❌ Missing |
| request() | Generic request | ❌ Missing |
| _sleep_for_retry() | Sleep before retry | Process.sleep() ✅ |
| _process_response() | Process response | handle_response() ⚠️ |
| _request_api_list() | Request list API | ❌ Missing |
| get() | HTTP GET | get() ⚠️ |
| post() | HTTP POST | post() ⚠️ |
| patch() | HTTP PATCH | ❌ Missing |
| put() | HTTP PUT | ❌ Missing |
| delete() | HTTP DELETE | delete() ⚠️ |
| get_api_list() | Get paginated list | ❌ Missing |

### _client.py (362 lines)

#### Classes

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| AsyncTinker | Main async client | ❌ Missing (Tinkex is module) |
| AsyncTinkerWithRawResponse | Raw response wrapper | ❌ Missing |
| AsyncTinkerWithStreamedResponse | Streamed response wrapper | ❌ Missing |

#### AsyncTinker Methods

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| __init__() | Initialize client | ❌ Missing |
| service (property) | Service resource | ServiceClient ⚠️ |
| training (property) | Training resource | TrainingClient ⚠️ |
| models (property) | Models resource | ❌ Missing |
| weights (property) | Weights resource | ❌ Missing |
| sampling (property) | Sampling resource | SamplingClient ⚠️ |
| futures (property) | Futures resource | ❌ Missing |
| telemetry (property) | Telemetry resource | ❌ Missing |
| with_raw_response (property) | Raw response access | ❌ Missing |
| with_streaming_response (property) | Streaming response access | ❌ Missing |
| qs (property) | Querystring with array_format | ❌ Missing |
| auth_headers (property) | X-API-Key header | ✅ In build_headers() |
| default_headers (property) | All default headers | ⚠️ In build_headers() |
| copy() | Copy client with overrides | ❌ Missing |
| with_options() | Alias for copy | ❌ Missing |
| _make_status_error() | Create status error | ✅ _make_status_error() |

### _response.py (855 lines)

#### Classes

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| BaseAPIResponse | Base response wrapper | ❌ Missing |
| APIResponse | Sync response | ❌ Missing |
| AsyncAPIResponse | Async response | ❌ Missing |
| BinaryAPIResponse | Binary response helpers | ❌ Missing |
| AsyncBinaryAPIResponse | Async binary helpers | ❌ Missing |
| StreamedBinaryAPIResponse | Streamed binary | ❌ Missing |
| AsyncStreamedBinaryAPIResponse | Async streamed binary | ❌ Missing |
| MissingStreamClassError | Stream class not provided | ❌ Missing |
| StreamAlreadyConsumed | Stream consumed error | ❌ Missing |
| ResponseContextManager | Sync context manager | ❌ Missing |
| AsyncResponseContextManager | Async context manager | ❌ Missing |

#### Functions

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| to_streamed_response_wrapper() | Wrap for streaming | ❌ Missing |
| async_to_streamed_response_wrapper() | Async streaming wrapper | ❌ Missing |
| to_custom_streamed_response_wrapper() | Custom streaming wrapper | ❌ Missing |
| async_to_custom_streamed_response_wrapper() | Async custom streaming | ❌ Missing |
| to_raw_response_wrapper() | Raw response wrapper | ❌ Missing |
| async_to_raw_response_wrapper() | Async raw wrapper | ❌ Missing |
| to_custom_raw_response_wrapper() | Custom raw wrapper | ❌ Missing |
| async_to_custom_raw_response_wrapper() | Async custom raw | ❌ Missing |
| extract_response_type() | Extract generic type var | ❌ Missing |

#### BaseAPIResponse Properties/Methods

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| headers | Response headers | ❌ Missing |
| http_request | Request object | ❌ Missing |
| status_code | HTTP status | ❌ Missing |
| url | Request URL | ❌ Missing |
| method | HTTP method | ❌ Missing |
| http_version | HTTP version | ❌ Missing |
| elapsed | Request duration | ❌ Missing |
| is_closed | Check if closed | ❌ Missing |
| _parse() | Internal parse | ❌ Missing |

#### APIResponse Methods

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| parse() | Parse to type | ❌ Missing |
| read() | Read binary content | ❌ Missing |
| text() | Decode to text | ❌ Missing |
| json() | Parse JSON | ⚠️ Implicit |
| close() | Close response | ❌ Missing |
| iter_bytes() | Iterate bytes | ❌ Missing |
| iter_text() | Iterate text chunks | ❌ Missing |
| iter_lines() | Iterate lines | ❌ Missing |

#### BinaryAPIResponse Methods

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| write_to_file() | Write binary to file | ❌ Missing |
| stream_to_file() | Stream binary to file | ❌ Missing |

### _resource.py (25 lines)

#### Classes

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| AsyncAPIResource | Resource base class | ❌ Missing |

#### Methods

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| __init__() | Initialize resource | ❌ Missing |
| _sleep() | Sleep helper | ❌ Missing |

### _types.py (220 lines)

#### Type Aliases

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| Transport | BaseTransport | N/A |
| AsyncTransport | AsyncBaseTransport | N/A |
| Query | Mapping[str, object] | keyword() ⚠️ |
| Body | object | map() ⚠️ |
| AnyMapping | Mapping[str, object] | map() ⚠️ |
| ModelT | TypeVar bound to BaseModel | N/A |
| ProxiesDict | Dict of proxy mappings | ❌ Missing |
| ProxiesTypes | Proxy types union | ❌ Missing |
| Base64FileInput | IO or PathLike | ❌ Missing |
| FileContent | bytes, IO, or PathLike | ❌ Missing |
| FileTypes | File type unions | ❌ Missing |
| RequestFiles | Mapping or Sequence of files | ❌ Missing |
| HttpxFileContent | httpx file content | ❌ Missing |
| HttpxFileTypes | httpx file types | ❌ Missing |
| HttpxRequestFiles | httpx request files | ❌ Missing |
| NoneType | Type[None] | ❌ Missing |
| NotGivenOr | Union[T, NotGiven] | ❌ Missing |
| Headers | Mapping with Omit | keyword() ⚠️ |
| HeadersLike | Union of header types | ❌ Missing |
| ResponseT | Response type var | ❌ Missing |
| StrBytesIntFloat | Primitive union | ❌ Missing |
| IncEx | Include/exclude type | ❌ Missing |
| PostParser | Callable for post-parsing | ❌ Missing |
| HttpxSendArgs | httpx send args | ❌ Missing |

#### Classes

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| RequestOptions | TypedDict for options | keyword() ⚠️ |
| NotGiven | Sentinel for omitted | ❌ Missing |
| Omit | Sentinel for removal | ❌ Missing |
| ModelBuilderProtocol | Custom model builder | ❌ Missing |
| HeadersLikeProtocol | Header-like protocol | ❌ Missing |
| InheritsGeneric | Generic inheritance protocol | N/A |
| _GenericAlias | Generic alias protocol | N/A |

#### Constants

| Name | Value | Elixir Equivalent |
|------|-------|-------------------|
| NOT_GIVEN | NotGiven() | ❌ Missing |

### _files.py (124 lines)

#### Functions

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| is_base64_file_input() | Type guard for files | ❌ Missing |
| is_file_content() | Type guard for content | ❌ Missing |
| assert_is_file_content() | Assert file content type | ❌ Missing |
| to_httpx_files() | Transform to httpx files | ❌ Missing |
| _transform_file() | Transform single file | ❌ Missing |
| read_file_content() | Read file content | ❌ Missing |
| async_to_httpx_files() | Async transform files | ❌ Missing |
| _async_transform_file() | Async transform file | ❌ Missing |
| async_read_file_content() | Async read file | ❌ Missing |

### _compat.py (220 lines)

All Pydantic V1/V2 compatibility - N/A for Elixir

### _version.py (5 lines)

| Name | Purpose | Elixir Equivalent |
|------|---------|-------------------|
| __title__ | Package name | Mix project :app ✅ |
| __version__ | Package version | Mix project :version ✅ |

---

## 5. Recommendations

### Priority 1: Critical Infrastructure (Implement First)

1. **Response Wrapper Classes** (GAP-CORE-004)
   - Implement `Tinkex.Response` module
   - Add `parse()`, `read()`, `text()`, `json()` methods
   - Expose response metadata (status, headers, url)
   - ~500 LOC

2. **Type Construction and Validation** (GAP-CORE-003)
   - Implement `Tinkex.TypeBuilder` module
   - Support struct construction from maps
   - Add validation with Ecto.Changeset or similar
   - Support strict vs. lenient modes
   - ~300 LOC

3. **File Upload and Multipart** (GAP-CORE-007)
   - Implement `Tinkex.Files` module
   - Support file uploads from paths and binaries
   - Handle multipart/form-data encoding
   - ~200 LOC

4. **Request Building Enhancement** (GAP-CORE-002)
   - Enhance request builder with multipart support
   - Add content-type detection
   - Support file uploads in requests
   - ~150 LOC

### Priority 2: High-Value Features (Implement Second)

5. **Pagination Infrastructure** (GAP-CORE-005)
   - Implement `Tinkex.Pagination` module
   - Add PageInfo, Page protocol
   - Create lazy Stream-based pagination
   - ~250 LOC

6. **SSE Streaming** (GAP-CORE-006)
   - Implement `Tinkex.SSE` module
   - Add SSEDecoder for event parsing
   - Support streaming responses
   - ~300 LOC

7. **Client Method Variants** (GAP-CORE-014)
   - Add PATCH and PUT methods
   - Implement generic request() method
   - ~100 LOC

8. **NotGiven and Omit Sentinels** (GAP-CORE-008)
   - Implement sentinel modules
   - Update header merging logic
   - Support optional vs. removal semantics
   - ~100 LOC

### Priority 3: Nice-to-Have Enhancements (Implement Third)

9. **Query String Serialization** (GAP-CORE-009)
   - Implement `Tinkex.QueryString` module
   - Support array formats (comma, brackets, indices)
   - ~150 LOC

10. **Timeout Type Flexibility** (GAP-CORE-010)
    - Create `Tinkex.Timeout` struct
    - Support read/write/connect/pool timeouts
    - ~100 LOC

11. **Custom Authentication** (GAP-CORE-011)
    - Define auth behavior
    - Support custom auth modules
    - ~150 LOC

12. **Response Wrappers** (GAP-CORE-013)
    - Implement with_raw_response pattern
    - Implement with_streaming_response pattern
    - ~200 LOC

### Priority 4: Optional Improvements (Consider Later)

13. **Request/Response Hooks** (GAP-CORE-015)
14. **Client Copying** (GAP-CORE-016)
15. **Strict Validation Mode** (GAP-CORE-017)
16. **Platform Detection** (GAP-CORE-018)
17. **Default Headers/Query in Config** (GAP-CORE-019)
18. **Error Exception Hierarchy** (GAP-CORE-020)
19. **HTTP-Date Parsing** (GAP-CORE-022)
20. **Unlimited Retries** (GAP-CORE-024)
21. **AsyncResource Base** (GAP-CORE-025)

### Implementation Effort Estimate

- **Priority 1:** ~1,150 LOC, ~3-4 weeks
- **Priority 2:** ~750 LOC, ~2-3 weeks
- **Priority 3:** ~500 LOC, ~1-2 weeks
- **Priority 4:** ~400 LOC, ~1 week

**Total:** ~2,800 LOC, ~7-10 weeks of focused development

### Testing Recommendations

For each implemented feature:
1. Unit tests for core functionality
2. Integration tests with mock HTTP server
3. Property-based tests for type construction/validation
4. Doctests for public API examples

### Architecture Recommendations

1. **Use Behaviours for Abstractions**
   - Define `Tinkex.HTTPClient` behaviour (already exists)
   - Define `Tinkex.Auth` behaviour
   - Define `Tinkex.Page` protocol

2. **Leverage BEAM Patterns**
   - Use Streams for pagination (lazy evaluation)
   - Use GenStage for SSE streaming if needed
   - Use Task.async for concurrent requests

3. **Type Safety**
   - Use Dialyzer/Gradient for type checking
   - Define comprehensive typespecs
   - Use Ecto.Changeset for validation

4. **Error Handling**
   - Continue using tagged tuples {:ok, _} | {:error, _}
   - Consider raising exceptions for programmer errors
   - Keep error categorization for retry logic

---

## 6. Conclusion

The Elixir tinkex port has established a solid foundation with:
- Basic HTTP operations (GET, POST, DELETE)
- Retry logic with exponential backoff
- Error handling and categorization
- Configuration management
- Telemetry integration

However, it is missing approximately **65% of Python tinker's core infrastructure**, particularly:
- Response abstraction and type-safe parsing
- File upload and multipart handling
- Pagination and streaming
- Advanced request building
- Type system features (NotGiven, Omit, etc.)

The recommended implementation path focuses on high-impact features first (response wrappers, type construction, file handling) before moving to nice-to-have enhancements. With focused effort, the core infrastructure can reach feature parity in approximately 2-3 months.

The BEAM VM's inherent concurrency model simplifies some aspects (no need for explicit async/await), but Elixir's different type system and patterns require thoughtful adaptation of Python's Pydantic-based approach.

---

**End of Gap Analysis**
