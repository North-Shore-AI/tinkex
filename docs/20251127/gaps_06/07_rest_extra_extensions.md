# Gap #7: Raw REST "extra_*" Extension Points

**Date:** 2025-11-27
**Author:** Claude (Deep-Dive Analysis)
**Status:** Comprehensive Technical Analysis

---

## Executive Summary

The Python Tinker SDK provides a flexible, extensible HTTP request system through five "extra_*" parameters that allow users to augment requests beyond the defined API schema. The Elixir Tinkex SDK has a narrower extension system: it supports header merging, per-request timeouts, per-request `max_retries`, and idempotency keys for non-GET requests, but lacks mechanisms for extending query parameters or body fields.

**Python Extension Points (5):**
1. `extra_headers` - Merge additional HTTP headers
2. `extra_query` - Merge additional query string parameters
3. `extra_body` - Merge additional JSON body fields
4. `idempotency_key` - Set idempotency header
5. `timeout` - Override client-level timeout

Mutation endpoints also expose `max_retries`; read-only endpoints use the client default.

**Elixir Extension Points (4):**
1. `:headers` - Merge additional HTTP headers (via `opts`)
2. `:idempotency_key` - Set idempotency header (via `opts`, ignored on GET; `:omit` disables auto-generation)
3. `:timeout` - Override client-level timeout (via `opts`)
4. `:max_retries` - Override client-level retry count (via `opts`)

**Missing in Elixir:**
- ❌ No `extra_query` mechanism for dynamic query parameters
- ❌ No `extra_body` mechanism for dynamic body field extension
- ⚠️ `:idempotency_key` is ignored for GET (unlike Python, which accepts it when provided via headers)
- ⚠️ Query strings built with ad-hoc string interpolation (`"?limit=#{limit}&offset=#{offset}"`)
- ⚠️ No query builder utility like Python's `Querystring`

---

## Table of Contents

1. [Python SDK Deep Dive](#1-python-sdk-deep-dive)
2. [Elixir SDK Deep Dive](#2-elixir-sdk-deep-dive)
3. [Granular Differences](#3-granular-differences)
4. [Common Use Cases Affected](#4-common-use-cases-affected)
5. [TDD Implementation Plan](#5-tdd-implementation-plan)
6. [Backward Compatibility Analysis](#6-backward-compatibility-analysis)
7. [References](#7-references)

---

## 1. Python SDK Deep Dive

### 1.1 Resource Method Signatures

**Location:** `tinker/src/tinker/resources/`

Mutation endpoints (`POST`/`PUT`/`DELETE`) expose a uniform extension surface (`extra_headers`, `extra_query`, `extra_body`, `timeout`, `idempotency_key`, `max_retries`):

```python
# File: resources/models.py
async def create(
    self,
    *,
    request: CreateModelRequest,
    # Extension parameters (standard on mutation endpoints)
    extra_headers: Headers | None = None,
    extra_query: Query | None = None,
    extra_body: Body | None = None,
    timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
    idempotency_key: str | None = None,
    max_retries: int | NotGiven = NOT_GIVEN,
) -> UntypedAPIFuture:
    """
    Creates a new model.

    Args:
      request: The create model request
      extra_headers: Send extra headers
      extra_query: Add additional query parameters to the request
      extra_body: Add additional JSON properties to the request
      timeout: Override the client-level default timeout
      idempotency_key: Specify a custom idempotency key
    """
    options = make_request_options(
        extra_headers=extra_headers,
        extra_query=extra_query,
        extra_body=extra_body,
        timeout=timeout,
        idempotency_key=idempotency_key,
    )
    if max_retries is not NOT_GIVEN:
        options["max_retries"] = max_retries

    return await self._post(
        "/api/v1/create_model",
        body=model_dump(request, exclude_unset=True, mode="json"),
        options=options,
        cast_to=UntypedAPIFuture,
    )
```

**GET/List endpoints omit idempotency/max_retries:** Read-only calls (e.g., `get_server_capabilities`, `weights.list`, `weights.get_checkpoint_archive_url`) only expose `extra_headers`, `extra_query`, `extra_body`, and `timeout`; they rely on the client's default retry policy and do not surface `idempotency_key`:

```python
# File: resources/service.py
async def get_server_capabilities(
    self,
    *,
    extra_headers: Headers | None = None,
    extra_query: Query | None = None,
    extra_body: Body | None = None,
    timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
) -> GetServerCapabilitiesResponse:
    return await self._get(
        "/api/v1/get_server_capabilities",
        options=make_request_options(
            extra_headers=extra_headers,
            extra_query=extra_query,
            extra_body=extra_body,
            timeout=timeout,
        ),
        cast_to=GetServerCapabilitiesResponse,
    )
```

### 1.2 `make_request_options` Function

**Location:** `tinker/src/tinker/_base_client.py` (lines 1288-1322)

```python
def make_request_options(
    *,
    query: Query | None = None,
    extra_headers: Headers | None = None,
    extra_query: Query | None = None,
    extra_body: Body | None = None,
    idempotency_key: str | None = None,
    timeout: float | httpx.Timeout | None | NotGiven = NOT_GIVEN,
    post_parser: PostParser | NotGiven = NOT_GIVEN,
) -> RequestOptions:
    """Create a dict of type RequestOptions without keys of NotGiven values."""
    options: RequestOptions = {}

    # 1. extra_headers → options["headers"]
    if extra_headers is not None:
        options["headers"] = extra_headers

    # 2. extra_body → options["extra_json"]
    if extra_body is not None:
        options["extra_json"] = cast(AnyMapping, extra_body)

    # 3. query (base params) → options["params"]
    if query is not None:
        options["params"] = query

    # 4. extra_query (merged with base params)
    if extra_query is not None:
        options["params"] = {**options.get("params", {}), **extra_query}

    # 5. timeout
    if not isinstance(timeout, NotGiven):
        options["timeout"] = timeout

    # 6. idempotency_key
    if idempotency_key is not None:
        options["idempotency_key"] = idempotency_key

    # Internal parameter
    if is_given(post_parser):
        options["post_parser"] = post_parser

    return options
```

**Key Insight:** `extra_query` and `query` are **merged** into `options["params"]`, allowing dynamic query parameter extension.

### 1.3 `RequestOptions` TypedDict

**Location:** `tinker/src/tinker/_types.py` (lines 96-103)

```python
class RequestOptions(TypedDict, total=False):
    headers: Headers
    max_retries: int
    timeout: float | Timeout | None
    params: Query  # ← Query parameters
    extra_json: AnyMapping  # ← Extra body fields
    idempotency_key: str
    follow_redirects: bool
```

### 1.4 `FinalRequestOptions` Class

**Location:** `tinker/src/tinker/_models.py` (lines 499-527)

```python
@final
class FinalRequestOptions(pydantic.BaseModel):
    method: str
    url: str
    params: Query = {}  # ← Query parameters
    headers: Union[Headers, NotGiven] = NotGiven()
    max_retries: Union[int, NotGiven] = NotGiven()
    timeout: Union[float, Timeout, None, NotGiven] = NotGiven()
    files: Union[HttpxRequestFiles, None] = None
    idempotency_key: Union[str, None] = None
    post_parser: Union[Callable[[Any], Any], NotGiven] = NotGiven()
    follow_redirects: Union[bool, None] = None

    json_data: Union[Body, None] = None  # ← Base body
    extra_json: Union[AnyMapping, None] = None  # ← Extra body fields
```

### 1.5 Body Extension Merging

**Location:** `tinker/src/tinker/_base_client.py` (lines 437-446)

```python
def _build_request(
    self,
    options: FinalRequestOptions,
    *,
    retries_taken: int = 0,
) -> httpx.Request:
    # ...
    json_data = options.json_data

    # Merge extra_json into json_data
    if options.extra_json is not None:
        if json_data is None:
            json_data = cast(Body, options.extra_json)
        elif is_mapping(json_data):
            json_data = _merge_mappings(json_data, options.extra_json)
        else:
            raise RuntimeError(
                f"Unexpected JSON data type, {type(json_data)}, cannot merge with `extra_body`"
            )
    # ...
```

**Merging Logic:**
1. If `json_data` is `None` → use `extra_json` directly
2. If `json_data` is a mapping → merge: `{**json_data, **extra_json}`
3. Otherwise → raise error

### 1.6 Query Parameter Building

**Location:** `tinker/src/tinker/_base_client.py` (lines 449, 509)

```python
def _build_request(self, options: FinalRequestOptions, ...) -> httpx.Request:
    # ...
    headers = self._build_headers(options, retries_taken=retries_taken)
    params = _merge_mappings(self.default_query, options.params)  # ← Merge
    # ...

    return self._client.build_request(
        headers=headers,
        timeout=...,
        method=options.method,
        url=prepared_url,
        params=self.qs.stringify(cast(Mapping[str, Any], params)) if params else None,
        **kwargs,
    )
```

**Query String Builder:** Uses `self.qs` (a `Querystring` instance) from `_qs.py` to properly encode parameters.

### 1.7 Python Usage Examples

```python
# Example 1: Add extra headers for debugging
response = await client.models.create(
    request=CreateModelRequest(...),
    extra_headers={"X-Debug": "true", "X-Trace-ID": "abc123"}
)

# Example 2: Add extra query parameters (e.g., pagination)
response = await client.training.forward(
    request=ForwardRequest(...),
    extra_query={"verbose": "true", "include_metadata": "1"}
)

# Example 3: Add extra body fields (experimental features)
response = await client.models.create(
    request=CreateModelRequest(...),
    extra_body={"experimental_feature": True, "beta_flags": ["flag1"]}
)

# Example 4: Combine all extensions
response = await client.training.forward_backward(
    request=ForwardBackwardRequest(...),
    extra_headers={"X-Request-ID": "req-123"},
    extra_query={"debug": "true"},
    extra_body={"trace_gradients": True},
    timeout=60.0,
    idempotency_key="my-custom-key"
)
```

---

## 2. Elixir SDK Deep Dive

### 2.1 Current Extension Points

**Location:** `lib/tinkex/api/api.ex`

```elixir
def post(path, body, opts) do
  config = Keyword.fetch!(opts, :config)

  url = build_url(config.base_url, path)
  timeout = Keyword.get(opts, :timeout, config.timeout)  # ✅ Per-request timeout
  headers = build_headers(:post, config, opts, timeout)
  max_retries = Keyword.get(opts, :max_retries, config.max_retries)
  pool_type = Keyword.get(opts, :pool_type, :default)
  response_mode = Keyword.get(opts, :response)
  transform_opts = Keyword.get(opts, :transform, [])
  # ...
end
```

### 2.2 Header Merging

**Location:** `lib/tinkex/api/api.ex` (lines 257-274)

```elixir
defp build_headers(method, config, opts, timeout_ms) do
  [
    {"accept", "application/json"},
    {"content-type", "application/json"},
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
  |> Kernel.++(Keyword.get(opts, :headers, []))  # ✅ Extra headers
  |> dedupe_headers()
end
```

**Header Extension:** `Keyword.get(opts, :headers, [])` at line 272 allows passing extra headers.

### 2.3 Idempotency Key Handling

**Location:** `lib/tinkex/api/api.ex` (lines 706-717)

```elixir
defp idempotency_headers(:get, _opts), do: []

defp idempotency_headers(_method, opts) do
  key =
    case opts[:idempotency_key] do
      nil -> build_idempotency_key()  # Auto-generate
      :omit -> nil
      value -> to_string(value)
    end

  if key, do: [{"x-idempotency-key", key}], else: []
end
```

**Idempotency Extension:** `opts[:idempotency_key]` can override the auto-generated key for non-GET requests. For `:get`, the helper returns `[]`, so `:idempotency_key` is ignored (a manual header in `:headers` is required if a caller wants to send one).

### 2.4 Query String Construction (Ad-Hoc)

**Location:** `lib/tinkex/api/rest.ex`

```elixir
# Example 1: list_sessions (lines 33-36)
def list_sessions(config, limit \\ 20, offset \\ 0) do
  path = "/api/v1/sessions?limit=#{limit}&offset=#{offset}"  # ❌ String interpolation
  API.get(path, config: config, pool_type: :training)
end

# Example 2: list_checkpoints (line 43)
def list_checkpoints(config, run_id) do
  API.get("/api/v1/training_runs/#{run_id}/checkpoints", config: config, pool_type: :training)
end

# Example 3: list_user_checkpoints (lines 55-58)
def list_user_checkpoints(config, limit \\ 50, offset \\ 0) do
  path = "/api/v1/checkpoints?limit=#{limit}&offset=#{offset}"  # ❌ String interpolation
  API.get(path, config: config, pool_type: :training)
end

# Example 4: list_training_runs (lines 251-257)
def list_training_runs(config, limit \\ 20, offset \\ 0) do
  path = "/api/v1/training_runs?limit=#{limit}&offset=#{offset}"  # ❌ String interpolation

  case API.get(path, config: config, pool_type: :training) do
    {:ok, data} -> {:ok, TrainingRunsResponse.from_map(data)}
    {:error, _} = error -> error
  end
end
```

**Problems with Ad-Hoc String Interpolation:**
1. ❌ No URL encoding of parameter values
2. ❌ No support for arrays, nested objects, or special characters
3. ❌ Brittle (easy to introduce bugs with malformed query strings)
4. ❌ No query parameter merging capability

### 2.5 URL Building

**Location:** `lib/tinkex/api/api.ex` (lines 236-255)

```elixir
defp build_url(base_url, path) do
  base = URI.parse(base_url)
  base_path = base.path || "/"

  # Extract query from path if present
  {relative_path, query} =
    case String.split(path, "?", parts: 2) do
      [p, q] -> {p, q}
      [p] -> {p, nil}
    end

  merged_path =
    relative_path
    |> String.trim_leading("/")
    |> then(fn trimmed -> Path.join(base_path, trimmed) end)

  uri = %{base | path: merged_path}
  uri = if query, do: %{uri | query: query}, else: uri  # ← Query string from path

  URI.to_string(uri)
end
```

**Current Behavior:**
- Extracts query string from `path` (if path is `"/api/v1/sessions?limit=20&offset=0"`)
- No mechanism to pass query parameters separately from path
- No merging of query parameters from different sources

### 2.6 Elixir Usage Examples (Current Limitations)

```elixir
# ✅ Supported: Extra headers
Tinkex.API.Training.forward(
  %{model_id: "...", inputs: [...]},
  config: config,
  headers: [{"x-debug", "true"}, {"x-trace-id", "abc123"}]
)

# ✅ Supported: Custom idempotency key
Tinkex.API.Training.forward_backward(
  %{model_id: "...", inputs: [...]},
  config: config,
  idempotency_key: "my-custom-key"
)

# ✅ Supported: Per-request timeout
Tinkex.API.Training.optim_step(
  %{adam_params: %{...}, model_id: "..."},
  config: config,
  timeout: 60_000  # 60 seconds
)

# ❌ NOT Supported: Extra query parameters
# Would need to be passed in path string (brittle):
Tinkex.API.get(
  "/api/v1/forward?debug=true&verbose=1",  # ← Ad-hoc, no encoding
  config: config,
  pool_type: :training
)

# ❌ NOT Supported: Extra body fields
# No mechanism to merge additional fields beyond the request struct
```

---

## 3. Granular Differences

### 3.1 Extension Points Comparison

| Extension Point | Python | Elixir | Status | Notes |
|----------------|--------|--------|--------|-------|
| **Extra Headers** | `extra_headers` param | `:headers` in opts | ✅ Parity | Both support header merging |
| **Idempotency Key** | `idempotency_key` param (exposed on mutate endpoints; GET/list rely on client default but can set via headers) | `:idempotency_key` in opts (ignored for GET; use `:headers` to force, `:omit` to disable auto-gen) | ⚠️ Partial | Elixir drops the option for GET; Python does not expose a param on GET but will forward a header if provided |
| **Per-Request Timeout** | `timeout` param | `:timeout` in opts | ✅ Parity | Both support timeout override |
| **Extra Query Params** | `extra_query` param | ❌ None | ⚠️ **GAP** | Elixir lacks query param extension |
| **Extra Body Fields** | `extra_body` param | ❌ None | ⚠️ **GAP** | Elixir lacks body field extension |
| **Query Builder** | `Querystring` class | ❌ None | ⚠️ **GAP** | Elixir uses string interpolation |
| **Max Retries** | `max_retries` param (only on endpoints whose signatures include it) | `:max_retries` in opts | ⚠️ Partial | Elixir allows per-call override on GET/POST/DELETE; Python read-only endpoints rely on client default |

### 3.2 Query String Construction

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Method** | `Querystring.stringify()` utility | Ad-hoc string interpolation |
| **URL Encoding** | ✅ Automatic (via `httpx`) | ❌ No encoding in ad-hoc strings |
| **Array Support** | ✅ `{"ids": [1, 2, 3]}` → `?ids=1&ids=2&ids=3` | ❌ Manual handling required |
| **Nested Objects** | ✅ Supported | ❌ Not supported |
| **Special Characters** | ✅ Properly encoded | ⚠️ Must manually encode |
| **Merging** | ✅ `{**query, **extra_query}` | ❌ No merging mechanism |

### 3.3 Body Extension

| Aspect | Python | Elixir |
|--------|--------|--------|
| **Method** | `_merge_mappings()` | N/A |
| **Use Case** | Add experimental/beta fields | Not supported |
| **Merging** | `{**json_data, **extra_json}` | N/A |
| **Type Safety** | Runtime check (raises on non-mapping) | N/A |

---

## 4. Common Use Cases Affected

### 4.1 Debugging & Observability

**Python:**
```python
# Add trace headers for distributed tracing
response = await client.training.forward(
    request=ForwardRequest(...),
    extra_headers={
        "X-Trace-ID": trace_id,
        "X-Request-ID": request_id,
        "X-Debug": "true"
    }
)
```

**Elixir (Workaround):**
```elixir
# Can add headers, but more verbose
Tinkex.API.Training.forward(
  request,
  config: config,
  headers: [
    {"x-trace-id", trace_id},
    {"x-request-id", request_id},
    {"x-debug", "true"}
  ]
)
```

**Status:** ✅ Headers supported in both.

---

### 4.2 Pagination with Dynamic Filters

**Python:**
```python
# Add dynamic filters via extra_query
sessions = await client.service.list_sessions(
    limit=50,
    offset=0,
    extra_query={
        "filter": "active",
        "sort": "created_at",
        "order": "desc"
    }
)
```

**Elixir (Current Limitation):**
```elixir
# ❌ Cannot add extra query parameters
# Would need to modify REST.list_sessions to accept filters
# OR build path manually with string interpolation (brittle)
path = "/api/v1/sessions?limit=50&offset=0&filter=active&sort=created_at&order=desc"
API.get(path, config: config, pool_type: :training)
```

**Status:** ❌ Not supported in Elixir without code changes.

---

### 4.3 Experimental API Features

**Python:**
```python
# Beta feature: enable gradient checkpointing
response = await client.training.forward_backward(
    request=ForwardBackwardRequest(...),
    extra_body={
        "enable_gradient_checkpointing": True,
        "checkpoint_interval": 5
    }
)
```

**Elixir (Current Limitation):**
```elixir
# ❌ Cannot add extra body fields beyond the typed request struct
# Would need to:
# 1. Modify ForwardBackwardRequest type definition
# 2. Update serialization logic
# 3. Rebuild project
```

**Status:** ❌ Not supported in Elixir without modifying type definitions.

---

### 4.4 API Versioning & Migration

**Python:**
```python
# Gradually adopt new API version
response = await client.models.create(
    request=CreateModelRequest(...),
    extra_headers={"X-API-Version": "2024-11-01"}
)
```

**Elixir (Workaround):**
```elixir
# Can add headers
Tinkex.API.Models.create(
  request,
  config: config,
  headers: [{"x-api-version", "2024-11-01"}]
)
```

**Status:** ✅ Headers supported in both.

---

### 4.5 Search & Filtering

**Python:**
```python
# Complex search with multiple filters
checkpoints = await client.rest.list_checkpoints(
    run_id="run-123",
    extra_query={
        "status": "completed",
        "min_step": 1000,
        "max_step": 5000,
        "tags": ["production", "validated"]
    }
)
```

**Elixir (Current Limitation):**
```elixir
# ❌ Cannot pass dynamic filters
# Must build query string manually
encoded_tags = URI.encode_query([tags: ["production", "validated"]])
path = "/api/v1/training_runs/#{run_id}/checkpoints?status=completed&min_step=1000&max_step=5000&#{encoded_tags}"
API.get(path, config: config, pool_type: :training)
```

**Status:** ⚠️ Possible with manual encoding, but error-prone.

---

## 5. TDD Implementation Plan

### Phase 1: Query Parameter Extension

#### 5.1.1 Test Suite: Query Parameter Merging

**File:** `test/tinkex/api/query_params_test.exs` (NEW)

```elixir
defmodule Tinkex.API.QueryParamsTest do
  use ExUnit.Case, async: true

  alias Tinkex.API.QueryParams

  describe "encode/1" do
    test "encodes simple key-value pairs" do
      assert QueryParams.encode(%{"limit" => 20, "offset" => 0}) == "limit=20&offset=0"
    end

    test "URL-encodes special characters" do
      assert QueryParams.encode(%{"name" => "hello world"}) == "name=hello+world"
      assert QueryParams.encode(%{"filter" => "status=active"}) == "filter=status%3Dactive"
    end

    test "handles arrays as repeated keys" do
      result = QueryParams.encode(%{"ids" => [1, 2, 3]})
      assert result == "ids=1&ids=2&ids=3"
    end

    test "handles nil values (omits from query string)" do
      assert QueryParams.encode(%{"a" => 1, "b" => nil, "c" => 3}) == "a=1&c=3"
    end

    test "handles empty map" do
      assert QueryParams.encode(%{}) == ""
    end
  end

  describe "merge/2" do
    test "merges two query param maps" do
      base = %{"limit" => 20}
      extra = %{"offset" => 10, "filter" => "active"}

      result = QueryParams.merge(base, extra)
      assert result == %{"limit" => 20, "offset" => 10, "filter" => "active"}
    end

    test "extra params override base params" do
      base = %{"limit" => 20, "offset" => 0}
      extra = %{"limit" => 50}

      result = QueryParams.merge(base, extra)
      assert result == %{"limit" => 50, "offset" => 0}
    end

    test "handles nil base" do
      extra = %{"limit" => 20}
      assert QueryParams.merge(nil, extra) == extra
    end

    test "handles nil extra" do
      base = %{"limit" => 20}
      assert QueryParams.merge(base, nil) == base
    end
  end
end
```

#### 5.1.2 Implementation: Query Builder Module

**File:** `lib/tinkex/api/query_params.ex` (NEW)

```elixir
defmodule Tinkex.API.QueryParams do
  @moduledoc """
  Query string parameter encoding and merging utilities.

  Provides Python SDK parity for query parameter handling.
  """

  @doc """
  Encode a map of query parameters to a URL-encoded query string.

  ## Examples

      iex> QueryParams.encode(%{"limit" => 20, "offset" => 0})
      "limit=20&offset=0"

      iex> QueryParams.encode(%{"name" => "hello world"})
      "name=hello+world"

      iex> QueryParams.encode(%{"ids" => [1, 2, 3]})
      "ids=1&ids=2&ids=3"
  """
  @spec encode(map() | nil) :: String.t()
  def encode(nil), do: ""
  def encode(params) when params == %{}, do: ""

  def encode(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.flat_map(&expand_param/1)
    |> URI.encode_query()
  end

  @doc """
  Merge two query parameter maps.

  Extra params override base params.

  ## Examples

      iex> QueryParams.merge(%{"limit" => 20}, %{"offset" => 10})
      %{"limit" => 20, "offset" => 10}

      iex> QueryParams.merge(%{"limit" => 20}, %{"limit" => 50})
      %{"limit" => 50}
  """
  @spec merge(map() | nil, map() | nil) :: map()
  def merge(nil, extra), do: extra || %{}
  def merge(base, nil), do: base || %{}
  def merge(base, extra) when is_map(base) and is_map(extra) do
    Map.merge(base, extra)
  end

  # Expand array values into repeated key-value pairs
  defp expand_param({key, values}) when is_list(values) do
    Enum.map(values, fn value -> {key, value} end)
  end

  defp expand_param({key, value}), do: [{key, value}]
end
```

#### 5.1.3 Test Suite: API Integration

**File:** `test/tinkex/api/extra_query_test.exs` (NEW)

```elixir
defmodule Tinkex.API.ExtraQueryTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "extra_query parameter" do
    test "merges extra query params into path" do
      config = test_config()

      # Mock HTTP call
      expect(Tinkex.HTTPClientMock, :post, fn url, _body, _headers, _opts ->
        # Verify URL contains merged query params
        assert url =~ "limit=20"
        assert url =~ "offset=0"
        assert url =~ "debug=true"
        assert url =~ "verbose=1"

        {:ok, %Finch.Response{status: 200, body: "{}"}}
      end)

      # Call with extra_query
      Tinkex.API.post(
        "/api/v1/sessions",
        %{},
        config: config,
        query: %{"limit" => 20, "offset" => 0},
        extra_query: %{"debug" => "true", "verbose" => "1"}
      )
    end

    test "extra_query overrides base query params" do
      config = test_config()

      expect(Tinkex.HTTPClientMock, :post, fn url, _body, _headers, _opts ->
        # Verify override
        assert url =~ "limit=50"  # extra_query value
        refute url =~ "limit=20"  # base query value

        {:ok, %Finch.Response{status: 200, body: "{}"}}
      end)

      Tinkex.API.post(
        "/api/v1/sessions",
        %{},
        config: config,
        query: %{"limit" => 20},
        extra_query: %{"limit" => 50}
      )
    end
  end
end
```

#### 5.1.4 Refactor: Update `Tinkex.API.post/3`

**File:** `lib/tinkex/api/api.ex` (MODIFY)

```elixir
def post(path, body, opts) do
  config = Keyword.fetch!(opts, :config)

  # NEW: Extract and merge query parameters
  base_query = Keyword.get(opts, :query)
  extra_query = Keyword.get(opts, :extra_query)
  merged_query = QueryParams.merge(base_query, extra_query)

  # NEW: Build path with query string
  path_with_query = append_query_string(path, merged_query)

  url = build_url(config.base_url, path_with_query)
  timeout = Keyword.get(opts, :timeout, config.timeout)
  headers = build_headers(:post, config, opts, timeout)
  # ... rest of function
end

# NEW helper function
defp append_query_string(path, nil), do: path
defp append_query_string(path, query) when query == %{}, do: path

defp append_query_string(path, query) do
  query_string = QueryParams.encode(query)

  if String.contains?(path, "?") do
    # Path already has query string - append
    "#{path}&#{query_string}"
  else
    # No query string yet
    "#{path}?#{query_string}"
  end
end
```

---

### Phase 2: Body Field Extension

#### 5.2.1 Test Suite: Body Merging

**File:** `test/tinkex/api/extra_body_test.exs` (NEW)

```elixir
defmodule Tinkex.API.ExtraBodyTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  describe "extra_body parameter" do
    test "merges extra body fields into request body" do
      config = test_config()

      base_body = %{"model_id" => "model-123", "inputs" => [1, 2, 3]}
      extra_body = %{"debug" => true, "trace_gradients" => true}

      expect(Tinkex.HTTPClientMock, :post, fn _url, body, _headers, _opts ->
        decoded = Jason.decode!(body)

        # Verify merged body
        assert decoded["model_id"] == "model-123"
        assert decoded["inputs"] == [1, 2, 3]
        assert decoded["debug"] == true
        assert decoded["trace_gradients"] == true

        {:ok, %Finch.Response{status: 200, body: "{}"}}
      end)

      Tinkex.API.post(
        "/api/v1/forward",
        base_body,
        config: config,
        extra_body: extra_body
      )
    end

    test "extra_body overrides base body fields" do
      config = test_config()

      base_body = %{"model_id" => "model-123", "timeout" => 30}
      extra_body = %{"timeout" => 60}  # Override

      expect(Tinkex.HTTPClientMock, :post, fn _url, body, _headers, _opts ->
        decoded = Jason.decode!(body)
        assert decoded["timeout"] == 60  # extra_body value

        {:ok, %Finch.Response{status: 200, body: "{}"}}
      end)

      Tinkex.API.post(
        "/api/v1/forward",
        base_body,
        config: config,
        extra_body: extra_body
      )
    end

    test "handles nil base_body" do
      config = test_config()

      extra_body = %{"experimental" => true}

      expect(Tinkex.HTTPClientMock, :post, fn _url, body, _headers, _opts ->
        decoded = Jason.decode!(body)
        assert decoded == %{"experimental" => true}

        {:ok, %Finch.Response{status: 200, body: "{}"}}
      end)

      Tinkex.API.post(
        "/api/v1/test",
        nil,
        config: config,
        extra_body: extra_body
      )
    end
  end
end
```

#### 5.2.2 Implementation: Body Merging

**File:** `lib/tinkex/api/api.ex` (MODIFY)

```elixir
def post(path, body, opts) do
  config = Keyword.fetch!(opts, :config)

  # Query parameter merging (from Phase 1)
  base_query = Keyword.get(opts, :query)
  extra_query = Keyword.get(opts, :extra_query)
  merged_query = QueryParams.merge(base_query, extra_query)
  path_with_query = append_query_string(path, merged_query)

  # NEW: Body field merging
  extra_body = Keyword.get(opts, :extra_body)
  merged_body = merge_body(body, extra_body)

  url = build_url(config.base_url, path_with_query)
  timeout = Keyword.get(opts, :timeout, config.timeout)
  headers = build_headers(:post, config, opts, timeout)
  max_retries = Keyword.get(opts, :max_retries, config.max_retries)
  pool_type = Keyword.get(opts, :pool_type, :default)
  response_mode = Keyword.get(opts, :response)
  transform_opts = Keyword.get(opts, :transform, [])

  metadata = %{
    method: :post,
    path: path,
    pool_type: pool_type,
    base_url: config.base_url
  }
  |> merge_telemetry_metadata(opts)

  # Use merged_body instead of body
  request = Finch.build(:post, url, headers, prepare_body(merged_body, transform_opts))

  pool_key = PoolKey.build(config.base_url, pool_type)

  {result, retry_count, duration} =
    execute_with_telemetry(
      &with_retries/6,
      [request, config.http_pool, timeout, pool_key, max_retries, config.dump_headers?],
      metadata
    )

  handle_response(result,
    method: :post,
    url: url,
    retries: retry_count,
    elapsed_native: duration,
    response: response_mode
  )
end

# NEW helper function
defp merge_body(nil, nil), do: nil
defp merge_body(nil, extra_body) when is_map(extra_body), do: extra_body
defp merge_body(base_body, nil), do: base_body

defp merge_body(base_body, extra_body) when is_map(base_body) and is_map(extra_body) do
  Map.merge(base_body, extra_body)
end

defp merge_body(base_body, extra_body) when is_binary(base_body) and is_map(extra_body) do
  # Cannot merge into binary body - raise error (Python SDK parity)
  raise ArgumentError, """
  Cannot merge extra_body into binary request body.
  Base body type: #{inspect(base_body)}
  Extra body: #{inspect(extra_body)}
  """
end

defp merge_body(base_body, extra_body) do
  # Non-map base body - raise error
  raise ArgumentError, """
  Cannot merge extra_body - base body must be a map.
  Base body type: #{inspect(base_body)}
  Extra body: #{inspect(extra_body)}
  """
end
```

---

### Phase 3: Update High-Level API Methods

#### 5.3.1 Refactor: REST Module

**File:** `lib/tinkex/api/rest.ex` (MODIFY)

Replace string interpolation with proper query parameter handling:

**BEFORE:**
```elixir
def list_sessions(config, limit \\ 20, offset \\ 0) do
  path = "/api/v1/sessions?limit=#{limit}&offset=#{offset}"
  API.get(path, config: config, pool_type: :training)
end
```

**AFTER:**
```elixir
def list_sessions(config, limit \\ 20, offset \\ 0, extra_opts \\ []) do
  query = %{"limit" => limit, "offset" => offset}

  opts =
    [config: config, pool_type: :training, query: query]
    |> Keyword.merge(extra_opts)

  API.get("/api/v1/sessions", opts)
end
```

**Benefits:**
1. ✅ Proper URL encoding
2. ✅ Supports `extra_query` via `extra_opts`
3. ✅ More maintainable

#### 5.3.2 Test Suite: REST Module Updates

**File:** `test/tinkex/api/rest_test.exs` (MODIFY)

```elixir
describe "list_sessions/4 with extra_query" do
  test "supports extra query parameters" do
    config = test_config()

    expect(Tinkex.HTTPClientMock, :get, fn url, _headers, _opts ->
      # Verify base params
      assert url =~ "limit=20"
      assert url =~ "offset=0"

      # Verify extra params
      assert url =~ "filter=active"
      assert url =~ "sort=created_at"

      {:ok, %Finch.Response{status: 200, body: Jason.encode!(%{
        "sessions" => [],
        "total" => 0
      })}}
    end)

    Rest.list_sessions(
      config,
      20,
      0,
      extra_query: %{"filter" => "active", "sort" => "created_at"}
    )
  end
end
```

---

### Phase 4: Documentation & Examples

#### 5.4.1 Update API Documentation

**File:** `lib/tinkex/api/api.ex` (MODIFY)

Add comprehensive documentation for new parameters:

```elixir
@doc """
Perform a POST request.

## Options

  * `:config` (required) - Tinkex.Config struct
  * `:query` - Base query parameters (map)
  * `:extra_query` - Additional query parameters to merge (map)
  * `:extra_body` - Additional body fields to merge (map)
  * `:headers` - Additional HTTP headers (list of tuples)
  * `:idempotency_key` - Custom idempotency key (string or `:omit`)
  * `:timeout` - Request timeout in milliseconds (integer)
  * `:max_retries` - Maximum retry attempts (integer)
  * `:pool_type` - HTTP pool type (`:default`, `:training`, `:sampling`)

## Examples

    # Basic request
    Tinkex.API.post("/api/v1/forward", %{model_id: "..."}, config: config)

    # With extra query parameters
    Tinkex.API.post(
      "/api/v1/sessions",
      %{},
      config: config,
      query: %{"limit" => 20},
      extra_query: %{"filter" => "active", "sort" => "created_at"}
    )

    # With extra body fields (experimental features)
    Tinkex.API.post(
      "/api/v1/forward",
      %{model_id: "...", inputs: [...]},
      config: config,
      extra_body: %{"debug" => true, "trace_gradients" => true}
    )

    # Combining extensions
    Tinkex.API.post(
      "/api/v1/forward_backward",
      %{model_id: "...", inputs: [...]},
      config: config,
      headers: [{"x-trace-id", "abc123"}],
      extra_query: %{"verbose" => "true"},
      extra_body: %{"checkpoint_gradients" => true},
      timeout: 60_000,
      idempotency_key: "my-custom-key"
    )
"""
@spec post(String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
def post(path, body, opts) do
  # ...
end
```

---

## 6. Backward Compatibility Analysis

### 6.1 Breaking Changes

**None.** All changes are **additive** and **backward compatible**.

### 6.2 Existing Code Impact

| Code Pattern | Before | After | Compatible? |
|-------------|--------|-------|-------------|
| **Simple requests** | `API.post(path, body, config: config)` | Same | ✅ Yes |
| **With headers** | `API.post(path, body, config: config, headers: [...])` | Same | ✅ Yes |
| **Query in path** | `API.get("/path?limit=20", config: config)` | Same (still works) | ✅ Yes |
| **New query param** | N/A | `API.get(path, query: %{...}, config: config)` | ✅ New feature |
| **Extra query** | N/A | `API.get(path, extra_query: %{...}, config: config)` | ✅ New feature |
| **Extra body** | N/A | `API.post(path, body, extra_body: %{...}, config: config)` | ✅ New feature |

### 6.3 Migration Path

**Existing Code:** No migration required. All existing code continues to work.

**Recommended Refactoring (Optional):**
```elixir
# Old pattern (still works)
path = "/api/v1/sessions?limit=#{limit}&offset=#{offset}"
API.get(path, config: config)

# New pattern (recommended)
API.get(
  "/api/v1/sessions",
  config: config,
  query: %{"limit" => limit, "offset" => offset}
)
```

### 6.4 Performance Considerations

**Query Encoding:**
- `URI.encode_query/1` is a standard library function (well-optimized)
- Minimal overhead compared to string interpolation

**Body Merging:**
- `Map.merge/2` is O(n) where n = number of keys
- Negligible overhead for typical request sizes

**Memory:**
- No additional allocations beyond merged maps
- GC-friendly (short-lived intermediate data structures)

---

## 7. References

### 7.1 Python SDK Source Files

- `tinker/src/tinker/_base_client.py` - `make_request_options`, `_build_request`, `_merge_mappings`
- `tinker/src/tinker/_types.py` - `RequestOptions` TypedDict
- `tinker/src/tinker/_models.py` - `FinalRequestOptions` class
- `tinker/src/tinker/_qs.py` - `Querystring` utility
- `tinker/src/tinker/resources/models.py` - Example resource method signatures
- `tinker/src/tinker/resources/training.py` - Example resource method signatures

### 7.2 Elixir SDK Source Files

- `lib/tinkex/api/api.ex` - Core HTTP client
- `lib/tinkex/api/rest.ex` - REST endpoints (query string interpolation examples)
- `lib/tinkex/api/training.ex` - Training endpoints
- `lib/tinkex/api/models.ex` - Model endpoints

### 7.3 Related Documentation

- Elixir URI module: https://hexdocs.pm/elixir/URI.html
- Python httpx: https://www.python-httpx.org/
- OpenAPI 3.0 query parameters: https://swagger.io/docs/specification/describing-parameters/

---

## Appendix A: Full Example Comparison

### Python SDK - Full-Featured Request

```python
import asyncio
from tinker import AsyncTinker
from tinker.types import ForwardBackwardRequest

async def main():
    client = AsyncTinker(api_key="...")

    response = await client.training.forward_backward(
        request=ForwardBackwardRequest(
            model_id="model-123",
            inputs=[
                {"text": "Hello world", "image": None}
            ],
            seq_id=1
        ),
        # Extension parameters
        extra_headers={
            "X-Trace-ID": "abc123",
            "X-Debug": "true"
        },
        extra_query={
            "verbose": "true",
            "profile": "1"
        },
        extra_body={
            "checkpoint_gradients": True,
            "experimental_feature_x": True
        },
        timeout=60.0,
        idempotency_key="my-request-001",
        max_retries=5
    )

    print(f"Loss: {response.loss_fn_output}")

asyncio.run(main())
```

### Elixir SDK - After Implementation

```elixir
config = Tinkex.Config.new(api_key: "...")

{:ok, response} =
  Tinkex.API.Training.forward_backward(
    %{
      model_id: "model-123",
      inputs: [
        %{text: "Hello world", image: nil}
      ],
      seq_id: 1
    },
    # Extension options
    config: config,
    headers: [
      {"x-trace-id", "abc123"},
      {"x-debug", "true"}
    ],
    extra_query: %{
      "verbose" => "true",
      "profile" => "1"
    },
    extra_body: %{
      "checkpoint_gradients" => true,
      "experimental_feature_x" => true
    },
    timeout: 60_000,  # milliseconds
    idempotency_key: "my-request-001",
    max_retries: 5
  )

IO.puts("Loss: #{inspect(response.loss_fn_output)}")
```

**Parity Achieved:** ✅ Both SDKs support the same extension capabilities.

---

## Appendix B: Implementation Checklist

### Phase 1: Query Parameter Extension
- [ ] Create `lib/tinkex/api/query_params.ex`
- [ ] Write tests in `test/tinkex/api/query_params_test.exs`
- [ ] Implement `encode/1` function
- [ ] Implement `merge/2` function
- [ ] Update `Tinkex.API.post/3` to support `:query` and `:extra_query`
- [ ] Update `Tinkex.API.get/2` to support `:query` and `:extra_query`
- [ ] Update `Tinkex.API.delete/2` to support `:query` and `:extra_query`
- [ ] Add integration tests

### Phase 2: Body Field Extension
- [ ] Write tests in `test/tinkex/api/extra_body_test.exs`
- [ ] Implement `merge_body/2` in `Tinkex.API`
- [ ] Update `post/3` to use `merge_body/2`
- [ ] Add error handling for non-map bodies
- [ ] Add integration tests

### Phase 3: Refactor High-Level APIs
- [ ] Update `Tinkex.API.Rest.list_sessions/4` (add optional `extra_opts`)
- [ ] Update `Tinkex.API.Rest.list_checkpoints/2`
- [ ] Update `Tinkex.API.Rest.list_user_checkpoints/4`
- [ ] Update `Tinkex.API.Rest.list_training_runs/4`
- [ ] Update all other functions using string interpolation
- [ ] Write tests for each updated function

### Phase 4: Documentation
- [ ] Document `:query` option in `Tinkex.API`
- [ ] Document `:extra_query` option in `Tinkex.API`
- [ ] Document `:extra_body` option in `Tinkex.API`
- [ ] Add usage examples to module docs
- [ ] Update README.md with examples
- [ ] Create migration guide (optional refactoring)

### Phase 5: Testing & Validation
- [ ] Run full test suite
- [ ] Test backward compatibility
- [ ] Test URL encoding edge cases (special characters, arrays, etc.)
- [ ] Performance benchmarks (query encoding overhead)
- [ ] Manual integration tests against live API

---

## Conclusion

This gap analysis reveals a significant flexibility difference between the Python and Elixir SDKs. While Elixir supports headers, per-request timeouts, per-request retries, and idempotency keys on non-GET endpoints, it lacks the query parameter and body field extension mechanisms that make the Python SDK more adaptable to evolving APIs and experimental features.

The proposed TDD implementation plan provides a **backward-compatible, incremental path** to achieving full parity with minimal risk. The key improvements are:

1. **Query Parameter Extension** - Proper URL encoding and merging via `extra_query`
2. **Body Field Extension** - Dynamic field merging via `extra_body`
3. **Elimination of String Interpolation** - Replace ad-hoc query strings with type-safe builders

**Estimated Effort:**
- Phase 1: 4-6 hours (query params)
- Phase 2: 3-4 hours (body merging)
- Phase 3: 6-8 hours (refactoring)
- Phase 4: 2-3 hours (documentation)
- **Total:** ~15-20 hours

**Risk Level:** Low (all changes are additive and backward compatible)

**Recommendation:** Implement in order (Phase 1 → 2 → 3 → 4) with comprehensive testing at each phase.
