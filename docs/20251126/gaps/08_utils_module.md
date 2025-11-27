# Utils Module Gap Analysis - Python tinker to Elixir tinkex

**Analysis Date:** 2025-11-26
**Analyst:** Claude Code
**Domain:** Utils Module (`tinker/_utils/`)

---

## Executive Summary

### Overall Completeness: ~15%

The utils module shows a **CRITICAL GAP** - Elixir tinkex has virtually no equivalent utility infrastructure. Python tinker has a comprehensive utils package with 10 files containing ~70+ utility functions across multiple domains. The Elixir port currently lacks almost all of this functionality.

### Gap Statistics

- **Total Python Utility Functions:** ~70+ functions
- **Critical Gaps (Needed):** 42 functions
- **High Priority Gaps:** 15 functions
- **Medium Priority Gaps:** 8 functions
- **Not Applicable (Python-specific):** ~18 functions
- **Implemented in Elixir:** 2-3 functions (basic config helpers)

### Critical Areas Requiring Implementation

1. **Transform/Serialization** - TypedDict to API format transformation (CRITICAL)
2. **Type Introspection** - Type checking and extraction utilities (HIGH)
3. **Data Validation** - NotGiven handling, file extraction (CRITICAL)
4. **Logging Setup** - Environment-based logging configuration (MEDIUM)
5. **Async Utilities** - Thread pool execution (NOT APPLICABLE - OTP handles differently)

---

## Python Utils Package Structure

### File Inventory

| File | Purpose | Functions | Needed in Elixir? |
|------|---------|-----------|-------------------|
| `__init__.py` | Public exports | N/A | Reference only |
| `_utils.py` | Core utilities | 24 functions | YES - 18 needed |
| `_transform.py` | Data transformation | 15+ functions | YES - CRITICAL |
| `_proxy.py` | Lazy loading proxy | 1 class | NO - Different pattern |
| `_resources_proxy.py` | Resource lazy loading | 1 class | NO - Not applicable |
| `_typing.py` | Type introspection | 13 functions | PARTIAL - 8 needed |
| `_reflection.py` | Function inspection | 2 functions | PARTIAL - 1 needed |
| `_sync.py` | Async/sync conversion | 2 functions | NO - OTP pattern different |
| `_streams.py` | Stream consumption | 2 functions | NO - Elixir Streams different |
| `_logs.py` | Logging setup | 2 functions | YES - Needs adaptation |

---

## Section 1: Core Utilities (_utils.py)

### 1.1 Collection Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `flatten(t)` | Flatten nested iterables | YES | `List.flatten/1` | ✅ AVAILABLE |
| `is_dict(obj)` | Type guard for dict | PARTIAL | `is_map/1` macro | ⚠️ SEMANTIC DIFF |
| `is_list(obj)` | Type guard for list | PARTIAL | `is_list/1` macro | ✅ AVAILABLE |
| `is_tuple(obj)` | Type guard for tuple | PARTIAL | `is_tuple/1` macro | ✅ AVAILABLE |
| `is_mapping(obj)` | Type guard for Mapping | YES | Need custom guard | ❌ GAP-UTIL-001 |
| `is_mapping_t(obj)` | Type narrowing variant | PARTIAL | Pattern matching | ⚠️ PATTERN DIFF |
| `is_sequence(obj)` | Type guard for Sequence | PARTIAL | `is_list/1` + custom | ❌ GAP-UTIL-002 |
| `is_sequence_t(obj)` | Type narrowing variant | PARTIAL | Pattern matching | ⚠️ PATTERN DIFF |
| `is_iterable(obj)` | Type guard for Iterable | PARTIAL | `Enumerable` protocol | ⚠️ PROTOCOL DIFF |

### 1.2 Data Processing Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `deepcopy_minimal(item)` | Minimal deepcopy for dicts/lists | YES | Need implementation | ❌ GAP-UTIL-003 |
| `human_join(seq)` | Join with oxford comma | YES | Need implementation | ❌ GAP-UTIL-004 |
| `quote(string)` | Add single quotes | NO | String interpolation | ✅ NOT NEEDED |
| `json_safe(data)` | Convert to JSON-safe types | YES | Need implementation | ❌ GAP-UTIL-005 |
| `extract_files(query, paths)` | Extract files from nested dict | **CRITICAL** | Need implementation | ❌ GAP-UTIL-006 |
| `_extract_items(...)` | Recursive file extraction | **CRITICAL** | Need implementation | ❌ GAP-UTIL-007 |

### 1.3 Validation Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `is_given(obj)` | Check if NotGiven | **CRITICAL** | Need NotGiven pattern | ❌ GAP-UTIL-008 |
| `strip_not_given(obj)` | Remove NotGiven values | **CRITICAL** | Need implementation | ❌ GAP-UTIL-009 |
| `required_args(*variants)` | Decorator for arg validation | NO | @spec + guards | ✅ NOT NEEDED |

### 1.4 String Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `removeprefix(string, prefix)` | Remove prefix (backport) | NO | `String.trim_leading/2` | ✅ AVAILABLE |
| `removesuffix(string, suffix)` | Remove suffix (backport) | NO | `String.trim_trailing/2` | ✅ AVAILABLE |

### 1.5 Type Coercion Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `coerce_integer(val)` | String to int | YES | `String.to_integer/1` | ✅ AVAILABLE |
| `coerce_float(val)` | String to float | YES | `String.to_float/1` | ✅ AVAILABLE |
| `coerce_boolean(val)` | String to bool | YES | Need custom | ❌ GAP-UTIL-010 |
| `maybe_coerce_integer(val)` | Nullable int coercion | YES | Pattern match + above | ⚠️ PATTERN DIFF |
| `maybe_coerce_float(val)` | Nullable float coercion | YES | Pattern match + above | ⚠️ PATTERN DIFF |
| `maybe_coerce_boolean(val)` | Nullable bool coercion | YES | Pattern match + GAP-010 | ❌ GAP-UTIL-011 |

### 1.6 File/Path Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `file_from_path(path)` | Read file to tuple | YES | `File.read!/1` + basename | ⚠️ NEEDS WRAPPER |
| `parse_date(str)` | Parse ISO8601 date | YES | `Date.from_iso8601!/1` | ✅ AVAILABLE |
| `parse_datetime(str)` | Parse ISO8601 datetime | YES | `DateTime.from_iso8601/1` | ✅ AVAILABLE |

### 1.7 HTTP Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `get_required_header(headers, header)` | Extract header (case-insensitive) | YES | Need implementation | ❌ GAP-UTIL-012 |

### 1.8 Async Detection

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `get_async_library()` | Detect async library | NO | OTP/BEAM handles | ✅ NOT NEEDED |

### 1.9 Caching

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `lru_cache(maxsize)` | LRU cache decorator | PARTIAL | `:persistent_term` or ETS | ⚠️ DIFFERENT PATTERN |

---

## Section 2: Transform Module (_transform.py) - CRITICAL

### 2.1 PropertyInfo Class

**Python Implementation:**
```python
class PropertyInfo:
    alias: str | None  # e.g., "account_holder_name" -> "accountHolderName"
    format: PropertyFormat | None  # "iso8601", "base64", "custom"
    format_template: str | None  # For custom date formats
    discriminator: str | None  # For union type discrimination
```

**Gap Status:** ❌ **GAP-UTIL-013 (CRITICAL)**

**Elixir Needs:**
- Type metadata system (similar to TypedDict Annotated types)
- Field alias mapping for camelCase conversion
- Format transformation hooks
- Discriminator support for union types

### 2.2 Transform Functions

| Function | Purpose | Needed? | Gap Status |
|----------|---------|---------|-----------|
| `transform(data, expected_type)` | Transform dict based on type annotations | **CRITICAL** | ❌ GAP-UTIL-014 |
| `maybe_transform(data, expected_type)` | Nullable transform wrapper | **CRITICAL** | ❌ GAP-UTIL-015 |
| `async_transform(data, expected_type)` | Async version (file I/O) | **CRITICAL** | ❌ GAP-UTIL-016 |
| `async_maybe_transform(data, expected_type)` | Async nullable wrapper | **CRITICAL** | ❌ GAP-UTIL-017 |

### 2.3 Internal Transform Functions

| Function | Purpose | Needed? | Gap Status |
|----------|---------|---------|-----------|
| `_transform_recursive(data, annotation, inner_type)` | Recursive transformation | **CRITICAL** | ❌ GAP-UTIL-018 |
| `_transform_typeddict(data, expected_type)` | TypedDict-specific transform | **CRITICAL** | ❌ GAP-UTIL-019 |
| `_maybe_transform_key(key, type_)` | Key aliasing (snake_case → camelCase) | **CRITICAL** | ❌ GAP-UTIL-020 |
| `_format_data(data, format_, template)` | Format dates/base64 | **CRITICAL** | ❌ GAP-UTIL-021 |
| `_async_format_data(...)` | Async file base64 encoding | **CRITICAL** | ❌ GAP-UTIL-022 |
| `_get_annotated_type(type_)` | Extract PropertyInfo annotations | **CRITICAL** | ❌ GAP-UTIL-023 |
| `_no_transform_needed(annotation)` | Optimization for primitives | MEDIUM | ❌ GAP-UTIL-024 |
| `get_type_hints(obj, ...)` | Cached type hint extraction | MEDIUM | ❌ GAP-UTIL-025 |

### 2.4 Transform Logic Summary

**What Python Does:**
1. Takes a dict like `%{card_id: "12345"}`
2. Uses TypedDict annotations with PropertyInfo
3. Transforms keys: `card_id` → `cardID` (using alias)
4. Formats values: DateTime → ISO8601 string, Path → base64
5. Recursively processes nested dicts, lists, unions
6. Handles Pydantic models via `model_dump(mode="json")`

**Elixir Needs:**
- Compile-time type metadata (similar to `@type` but with field aliases)
- Runtime transformation based on type specs
- OR: Manual transformation functions for each request type
- OR: Macro system to generate transformers from type definitions

---

## Section 3: Typing Module (_typing.py)

### 3.1 Type Checking Functions

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `is_annotated_type(typ)` | Check if Annotated[T, ...] | NO | Pattern matching | ✅ NOT NEEDED |
| `is_list_type(typ)` | Check if List[T] | PARTIAL | `is_list/1` | ✅ AVAILABLE |
| `is_iterable_type(typ)` | Check if Iterable[T] | PARTIAL | `Enumerable` protocol | ⚠️ PROTOCOL DIFF |
| `is_union_type(typ)` | Check if Union[A, B] | NO | Pattern matching | ✅ NOT NEEDED |
| `is_required_type(typ)` | Check if Required[T] | NO | Default values | ✅ NOT NEEDED |
| `is_typevar(typ)` | Check if TypeVar | NO | Not applicable | ✅ NOT NEEDED |
| `is_type_alias_type(tp)` | Check if TypeAliasType | NO | `@type` system | ✅ NOT NEEDED |

### 3.2 Type Extraction Functions

| Function | Purpose | Needed? | Gap Status |
|----------|---------|---------|-----------|
| `strip_annotated_type(typ)` | Extract T from Annotated[T, ...] | NO | Not applicable | ✅ NOT NEEDED |
| `extract_type_arg(typ, index)` | Get type argument at index | NO | Not applicable | ✅ NOT NEEDED |
| `extract_type_var_from_base(typ, ...)` | Extract generic type variable | NO | Not applicable | ✅ NOT NEEDED |

**Summary:** Most typing utilities are Python-specific due to its dynamic type system. Elixir's static typing via `@spec` and pattern matching handles this differently.

---

## Section 4: Reflection Module (_reflection.py)

### 4.1 Function Inspection

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `function_has_argument(func, arg_name)` | Check if function has param | PARTIAL | Function arity check | ⚠️ DIFFERENT |
| `assert_signatures_in_sync(source, check, ...)` | Ensure matching signatures | NO | Dialyzer/compile checks | ✅ NOT NEEDED |

**Analysis:** Python needs runtime signature checking because it lacks static typing. Elixir uses Dialyzer and compile-time checks for this purpose.

---

## Section 5: Sync Module (_sync.py)

### 5.1 Async-to-Thread Utilities

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `asyncify(function)` | Convert blocking to async | NO | `Task.async/1` or `:poolboy` | ⚠️ DIFFERENT PATTERN |
| `to_thread(func, *args, **kwargs)` | Run in thread pool | NO | `Task.Supervisor` | ⚠️ DIFFERENT PATTERN |

**Analysis:** Python's async model (asyncio/anyio) requires explicit thread pooling for blocking I/O. Elixir's BEAM VM handles concurrency natively via lightweight processes. The patterns are fundamentally different:

- **Python:** `asyncio.to_thread(blocking_func)` moves work to thread pool
- **Elixir:** `Task.async(fn -> blocking_func() end)` spawns lightweight process

**Conclusion:** NOT NEEDED - OTP concurrency model is superior.

---

## Section 6: Streams Module (_streams.py)

### 6.1 Iterator Consumption

| Function | Purpose | Needed? | Elixir Equivalent | Gap Status |
|----------|---------|---------|-------------------|------------|
| `consume_sync_iterator(iterator)` | Exhaust iterator | NO | `Enum.each/2` or `Stream.run/1` | ✅ AVAILABLE |
| `consume_async_iterator(iterator)` | Exhaust async iterator | NO | `Stream.run/1` | ✅ AVAILABLE |

**Analysis:** Python needs explicit consumption helpers. Elixir's Stream and Enum modules handle this elegantly.

---

## Section 7: Logging Module (_logs.py)

### 7.1 Logging Setup

| Function | Purpose | Needed? | Gap Status |
|----------|---------|---------|-----------|
| `setup_logging()` | Configure logging based on env | YES | ❌ GAP-UTIL-026 |
| `_basic_config()` | Set up basic logging format | YES | ❌ GAP-UTIL-027 |

### 7.2 Python Logging Behavior

**Environment Variables:**
- `TINKER_LOG=debug` → Set logger to DEBUG, httpx to DEBUG
- `TINKER_LOG=info` → Set logger to INFO, httpx to INFO
- Default → logger WARNING, httpx WARNING (suppress 4xx backpressure noise)

**Elixir Equivalent Needed:**
```elixir
# lib/tinkex/logging.ex
defmodule Tinkex.Logging do
  require Logger

  def setup_logging do
    case System.get_env("TINKER_LOG") do
      "debug" ->
        Logger.configure(level: :debug)
        # Configure Finch/Req logging
      "info" ->
        Logger.configure(level: :info)
      _ ->
        Logger.configure(level: :warning)
    end
  end
end
```

**Gap Status:** ❌ **GAP-UTIL-026, GAP-UTIL-027**

---

## Section 8: Proxy Module (_proxy.py)

### 8.1 LazyProxy Class

**Purpose:** Lazy loading of `tinker.resources` module to avoid circular imports and improve startup time.

**Python Pattern:**
```python
class LazyProxy(Generic[T], ABC):
    def __getattr__(self, attr: str) -> object:
        proxied = self.__load__()
        return getattr(proxied, attr)

    @abstractmethod
    def __load__(self) -> T: ...
```

**Elixir Pattern:**
- Modules are loaded lazily by default
- No circular import issues due to compile-time resolution
- If needed, use `Code.ensure_loaded?/1` or `apply/3`

**Gap Status:** ✅ **NOT NEEDED** - Elixir's module system handles this natively.

---

## Section 9: Resources Proxy (_resources_proxy.py)

**Purpose:** Single use case - lazy load `tinker.resources` module.

**Gap Status:** ✅ **NOT NEEDED** - Not applicable to Elixir port.

---

## Detailed Gap Analysis

### GAP-UTIL-001: is_mapping guard function
- **Severity:** Medium
- **Python Function:** `is_mapping(obj)` - Type guard for Mapping protocol
- **Why Needed:** Distinguish between Map, Keyword list, and struct
- **Implementation:**
  ```elixir
  defguard is_mapping(term) when is_map(term) and not is_struct(term)
  ```

### GAP-UTIL-002: is_sequence guard function
- **Severity:** Low
- **Python Function:** `is_sequence(obj)` - Type guard for Sequence (list/tuple)
- **Why Needed:** Validate list-like data structures
- **Implementation:**
  ```elixir
  defguard is_sequence(term) when is_list(term) or is_tuple(term)
  ```

### GAP-UTIL-003: deepcopy_minimal
- **Severity:** Medium
- **Python Function:** Minimal deepcopy for dicts/lists (performance)
- **Why Needed:** Deep clone request bodies to avoid mutation issues
- **Implementation:**
  ```elixir
  def deepcopy_minimal(item) when is_map(item) do
    Map.new(item, fn {k, v} -> {k, deepcopy_minimal(v)} end)
  end
  def deepcopy_minimal(item) when is_list(item) do
    Enum.map(item, &deepcopy_minimal/1)
  end
  def deepcopy_minimal(item), do: item
  ```

### GAP-UTIL-004: human_join
- **Severity:** Low
- **Python Function:** `human_join(["a", "b", "c"], final="or")` → "a, b or c"
- **Why Needed:** User-friendly error messages (from `required_args` decorator)
- **Implementation:**
  ```elixir
  def human_join([], _opts), do: ""
  def human_join([single], _opts), do: single
  def human_join([a, b], opts) do
    final = Keyword.get(opts, :final, "or")
    "#{a} #{final} #{b}"
  end
  def human_join(seq, opts) do
    delim = Keyword.get(opts, :delim, ", ")
    final = Keyword.get(opts, :final, "or")
    {init, [last]} = Enum.split(seq, -1)
    Enum.join(init, delim) <> " #{final} #{last}"
  end
  ```

### GAP-UTIL-005: json_safe
- **Severity:** High
- **Python Function:** Recursively convert data to JSON-safe types (DateTime → ISO8601)
- **Why Needed:** Ensure all data can be JSON encoded before API requests
- **Implementation:**
  ```elixir
  def json_safe(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {json_safe(k), json_safe(v)} end)
  end
  def json_safe(data) when is_list(data) do
    Enum.map(data, &json_safe/1)
  end
  def json_safe(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def json_safe(%Date{} = d), do: Date.to_iso8601(d)
  def json_safe(data), do: data
  ```

### GAP-UTIL-006 & GAP-UTIL-007: extract_files + _extract_items
- **Severity:** CRITICAL
- **Python Function:** Recursively extract file objects from nested dict based on paths
- **Why Needed:** Multipart form uploads - separate files from JSON body
- **Example:**
  ```python
  query = {
    "foo": {
      "files": [
        {"data": file_obj_1},
        {"data": file_obj_2}
      ]
    }
  }
  paths = [["foo", "files", "<array>", "data"]]
  extract_files(query, paths=paths)
  # Returns: [("foo[files][][data]", file_obj_1), ("foo[files][][data]", file_obj_2)]
  # Mutates query to remove the "data" fields
  ```
- **Implementation Notes:**
  - Complex recursive traversal
  - Handles array notation `<array>`
  - Builds flattened keys: `foo[files][][data]`
  - Mutates input map (removes extracted files)
  - Critical for file upload endpoints

### GAP-UTIL-008 & GAP-UTIL-009: NotGiven handling
- **Severity:** CRITICAL
- **Python Function:** `is_given(obj)` and `strip_not_given(obj)`
- **Why Needed:** Distinguish between `nil` (explicit null) and "not provided"
- **Elixir Pattern:**
  ```elixir
  # Option 1: Sentinel value
  @not_given :__not_given__

  def is_given(:__not_given__), do: false
  def is_given(_), do: true

  def strip_not_given(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> v == :__not_given__ end)
    |> Map.new()
  end

  # Option 2: Wrap in {:ok, value} | :not_given
  # Option 3: Use NimbleOptions with default: nil vs no default
  ```
- **Challenge:** Python's `NotGiven` is a singleton type. Elixir needs a convention.

### GAP-UTIL-010 & GAP-UTIL-011: coerce_boolean variants
- **Severity:** Medium
- **Python Function:** `coerce_boolean("true")` → true, `coerce_boolean("1")` → true
- **Why Needed:** Parse environment variables and query params
- **Implementation:**
  ```elixir
  def coerce_boolean(val) when val in ["true", "1", "on"], do: true
  def coerce_boolean(_), do: false

  def maybe_coerce_boolean(nil), do: nil
  def maybe_coerce_boolean(val), do: coerce_boolean(val)
  ```

### GAP-UTIL-012: get_required_header
- **Severity:** Medium
- **Python Function:** Case-insensitive header extraction with fallbacks
- **Why Needed:** Webhook signature verification, response parsing
- **Implementation:**
  ```elixir
  def get_required_header(headers, header) when is_list(headers) do
    lower_header = String.downcase(header)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == lower_header, do: v
    end) || raise "Could not find #{header} header"
  end
  ```

### GAP-UTIL-013: PropertyInfo Metadata System
- **Severity:** CRITICAL
- **Python Implementation:** Uses `Annotated[str, PropertyInfo(alias="accountHolderName")]`
- **Why Needed:**
  - Elixir uses snake_case convention
  - API expects camelCase JSON keys
  - Need systematic transformation
- **Elixir Options:**

  **Option 1: Manual field mapping**
  ```elixir
  defmodule Tinkex.Types.CreateSessionRequest do
    @type t :: %{
      account_holder_name: String.t(),  # → accountHolderName
      card_id: String.t()               # → cardID
    }

    @field_aliases %{
      account_holder_name: "accountHolderName",
      card_id: "cardID"
    }

    def to_api_format(params) do
      Enum.map(params, fn {k, v} ->
        {Map.get(@field_aliases, k, k), v}
      end)
      |> Map.new()
    end
  end
  ```

  **Option 2: Macro-based code generation**
  ```elixir
  defmodule Tinkex.TypedParam do
    defmacro defparam(name, do: block) do
      # Generate struct + to_api_format/1 function
      # Parse field definitions with aliases
    end
  end

  defparam CreateSessionRequest do
    field :account_holder_name, :string, alias: "accountHolderName"
    field :card_id, :string, alias: "cardID"
  end
  ```

  **Option 3: Use existing library (e.g., Ecto.Changeset, TypedStruct)**
  ```elixir
  use TypedStruct

  typedstruct do
    field :account_holder_name, String.t()
    field :card_id, String.t()
  end

  # Separate transformer module
  ```

### GAP-UTIL-014 through GAP-UTIL-025: Transform System
- **Severity:** CRITICAL
- **Python Functionality:**
  - Type-driven transformation engine
  - Handles nested dicts, lists, unions, Pydantic models
  - Applies PropertyInfo transformations (aliases, format conversions)
  - Recursive processing with caching
- **Why Needed:**
  - Core functionality for API request preparation
  - Without this, every API call needs manual transformation
  - Ensures consistency across all endpoints
- **Elixir Implementation Strategy:**

  **Two Approaches:**

  **A) Type-Driven (mirrors Python):**
  - Define transformation metadata on types
  - Generic `transform/2` function
  - Pros: DRY, consistent, mirrors Python
  - Cons: Complex, runtime overhead, non-idiomatic

  **B) Manual per-Type (Elixir-idiomatic):**
  - Each request type has `to_api_format/1` function
  - Explicit transformations
  - Pros: Clear, type-safe, fast, idiomatic
  - Cons: Repetitive, more code

  **Recommendation:** Start with **Approach B** (manual), extract common patterns into helpers, then potentially build macro system if too repetitive.

  **Example Manual Approach:**
  ```elixir
  defmodule Tinkex.Types.CreateSessionRequest do
    @type t :: %{
      account_holder_name: String.t(),
      card_id: String.t(),
      birth_date: Date.t() | nil,
      profile_image: Path.t() | nil
    }

    def to_api_format(params) do
      params
      |> rename_keys()
      |> format_dates()
      |> encode_files()
    end

    defp rename_keys(params) do
      params
      |> Map.new(fn
        {:account_holder_name, v} -> {"accountHolderName", v}
        {:card_id, v} -> {"cardID", v}
        {k, v} -> {to_string(k), v}
      end)
    end

    defp format_dates(params) do
      Map.new(params, fn
        {k, %Date{} = v} -> {k, Date.to_iso8601(v)}
        {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
        {k, v} -> {k, v}
      end)
    end

    defp encode_files(params) do
      Map.new(params, fn
        {k, %Path{} = v} -> {k, base64_encode_file(v)}
        {k, v} -> {k, v}
      end)
    end
  end
  ```

### GAP-UTIL-026 & GAP-UTIL-027: Logging Setup
- **Severity:** Medium
- **Python Function:** Environment-based logging configuration
- **Why Needed:** Debug mode for development, quiet mode for production
- **Implementation:**
  ```elixir
  defmodule Tinkex.Logging do
    require Logger

    def setup_logging do
      case System.get_env("TINKER_LOG") do
        "debug" ->
          Logger.configure(level: :debug)
          configure_finch_logging(:debug)

        "info" ->
          Logger.configure(level: :info)
          configure_finch_logging(:info)

        _ ->
          Logger.configure(level: :warning)
          configure_finch_logging(:warning)
      end
    end

    defp configure_finch_logging(level) do
      # Configure Finch/Mint logging if possible
      # May need to use Logger metadata filtering
      :ok
    end
  end

  # Call from application.ex start/2
  ```

---

## Not Applicable Analysis

### Functions NOT Needed in Elixir (18 total)

| Function | Reason Not Needed |
|----------|-------------------|
| `LazyProxy` class | Elixir modules load lazily, no circular imports |
| `ResourcesProxy` | Specific to Python packaging |
| `required_args` decorator | Dialyzer + @spec provide compile-time checks |
| `assert_signatures_in_sync` | Dialyzer handles this |
| `asyncify`, `to_thread` | OTP concurrency model is fundamentally different |
| `consume_sync_iterator`, `consume_async_iterator` | `Enum.each/2`, `Stream.run/1` handle this |
| `get_async_library()` | BEAM VM handles concurrency uniformly |
| `lru_cache` decorator | ETS, persistent_term, or Cachex for different use case |
| Most `_typing.py` functions | Python dynamic typing vs Elixir static typing |
| `quote(string)` | String interpolation sufficient |
| `removeprefix`, `removesuffix` | String module has equivalents |
| `is_typevar`, `is_type_alias_type` | Not applicable to Elixir's type system |
| `strip_annotated_type` | Not applicable |
| `extract_type_arg`, `extract_type_var_from_base` | Not applicable |

---

## Section 10: Recommendations

### 10.1 Immediate Actions (Critical Priority)

1. **Implement NotGiven Pattern** (GAP-UTIL-008, GAP-UTIL-009)
   - Choose sentinel value approach: `:__not_given__` or `@not_given`
   - Implement `is_given/1` guard
   - Implement `strip_not_given/1` for map cleaning
   - Document pattern in CONVENTIONS.md

2. **Implement Transform System** (GAP-UTIL-014 through GAP-UTIL-025)
   - **Phase 1:** Manual `to_api_format/1` for each request type
   - **Phase 2:** Extract common transformations (rename_keys, format_dates, encode_files)
   - **Phase 3:** Consider macro system if too repetitive
   - Create `Tinkex.Transform` helper module

3. **Implement File Extraction** (GAP-UTIL-006, GAP-UTIL-007)
   - Port `extract_files/2` logic
   - Handle array notation `<array>`
   - Build flattened key syntax
   - Critical for multipart uploads

4. **Create Logging Setup** (GAP-UTIL-026, GAP-UTIL-027)
   - Add `Tinkex.Logging.setup_logging/0`
   - Call from `application.ex`
   - Respect `TINKER_LOG` environment variable
   - Configure Finch/HTTP client logging levels

### 10.2 High Priority Actions

5. **Implement Core Utilities** (GAP-UTIL-003, GAP-UTIL-005, GAP-UTIL-012)
   - `deepcopy_minimal/1`
   - `json_safe/1`
   - `get_required_header/2`
   - Create `Tinkex.Utils` module

6. **Implement String Coercion** (GAP-UTIL-010, GAP-UTIL-011)
   - `coerce_boolean/1`
   - `maybe_coerce_boolean/1`
   - Used for env vars and query params

### 10.3 Medium Priority Actions

7. **Implement Helper Guards** (GAP-UTIL-001, GAP-UTIL-002)
   - `is_mapping/1` guard
   - `is_sequence/1` guard
   - Document in guards module

8. **Implement String Utilities** (GAP-UTIL-004)
   - `human_join/2` for error messages
   - Quality-of-life improvement

### 10.4 Organizational Actions

9. **Create Utils Module Structure**
   ```
   lib/tinkex/
     utils.ex              # Core utilities, exports
     utils/
       guards.ex           # Type guards
       transform.ex        # Transformation helpers
       coerce.ex           # Type coercion
       files.ex            # File extraction
       not_given.ex        # NotGiven pattern
   ```

10. **Document Patterns**
    - Create `docs/patterns/NOT_GIVEN.md` explaining the pattern
    - Create `docs/patterns/TRANSFORMATION.md` explaining request transformation
    - Document in main README.md

### 10.5 Testing Strategy

11. **Port Python Tests**
    - Port `tests/test_utils.py` (if exists) to `test/tinkex/utils_test.exs`
    - Add property tests for transformations (use StreamData)
    - Test edge cases: empty maps, nil values, nested structures

12. **Integration Tests**
    - Test full request transformation pipeline
    - Test file extraction with real file objects
    - Test NotGiven stripping in API calls

### 10.6 Performance Considerations

13. **Optimize Transform System**
    - Profile transformation overhead
    - Consider compile-time macro generation if needed
    - Use ETS for type metadata if going type-driven route
    - Benchmark against Python's performance

### 10.7 Idiomatic Elixir Patterns

14. **Leverage Elixir Strengths**
    - Use protocols for polymorphic transformation if needed
    - Use `with` clauses for validation chains
    - Use pattern matching instead of type guards where possible
    - Use Streams for lazy iteration (no need for consume_* functions)
    - Use Task.async for concurrency (no asyncify needed)

### 10.8 Long-term Considerations

15. **Macro System for Type Metadata**
    - If manual transformations become too repetitive
    - Build `defparam` macro to generate:
      - Type definition
      - Field alias mapping
      - `to_api_format/1` function
      - `from_api_format/1` function (for responses)
    - Evaluate against existing libraries (Ecto.Schema, TypedStruct)

16. **Code Generation**
    - Consider generating utils from OpenAPI spec
    - Auto-generate field aliases from API schema
    - Validate against API contract in tests

---

## Appendix A: Python to Elixir Pattern Mapping

| Python Pattern | Elixir Equivalent | Notes |
|----------------|-------------------|-------|
| `isinstance(obj, dict)` | `is_map(obj)` | Maps, not dicts |
| `isinstance(obj, list)` | `is_list(obj)` | Built-in guard |
| `TypeGuard[T]` | Pattern matching | No runtime type guards needed |
| `@lru_cache` | ETS table or Cachex | Different caching strategy |
| `async def` | `Task.async` | Different concurrency model |
| `Annotated[T, metadata]` | No direct equivalent | Use module attributes or macros |
| `TypedDict` | `@type t :: %{...}` | Structural typing |
| `NotGiven` singleton | `:__not_given__` atom | Sentinel value |
| `**kwargs` | Keyword list | Named parameters |
| `functools.wraps` | No equivalent needed | Elixir functions are first-class |

---

## Appendix B: Function Dependency Graph

```
Core Dependencies (implement first):
├─ NotGiven pattern (GAP-008, GAP-009)
│  └─ Used by: transform, strip_not_given
├─ json_safe (GAP-005)
│  └─ Used by: transform, request encoding
└─ deepcopy_minimal (GAP-003)
   └─ Used by: request preparation

Transform System Dependencies:
├─ PropertyInfo metadata (GAP-013)
├─ transform/2 (GAP-014)
│  ├─ Depends on: NotGiven pattern
│  ├─ Depends on: json_safe
│  └─ Calls: _transform_recursive (GAP-018)
│     ├─ Calls: _transform_typeddict (GAP-019)
│     ├─ Calls: _maybe_transform_key (GAP-020)
│     └─ Calls: _format_data (GAP-021)
├─ maybe_transform/2 (GAP-015)
│  └─ Wraps: transform/2
└─ Async variants (GAP-016, GAP-017, GAP-022)
   └─ Add async file I/O for base64 encoding

File Handling:
├─ extract_files (GAP-006)
│  └─ Calls: _extract_items (GAP-007)
└─ Used by: multipart upload preparation

Utilities (independent):
├─ Logging setup (GAP-026, GAP-027)
├─ Coercion functions (GAP-010, GAP-011)
├─ get_required_header (GAP-012)
└─ human_join (GAP-004)
```

---

## Appendix C: Complexity Estimates

| Gap ID | Function | LOC Estimate | Complexity | Testing Effort |
|--------|----------|--------------|------------|----------------|
| GAP-008, 009 | NotGiven pattern | 20 | Low | Low |
| GAP-005 | json_safe | 15 | Low | Medium |
| GAP-003 | deepcopy_minimal | 10 | Low | Low |
| GAP-013 | PropertyInfo | 50-200 | High | High |
| GAP-014-025 | Transform system | 300-500 | Very High | Very High |
| GAP-006, 007 | File extraction | 80-100 | High | High |
| GAP-026, 027 | Logging setup | 30 | Low | Low |
| GAP-010-012 | Utilities | 40 | Low | Low |
| **TOTAL** | | **545-905 LOC** | | |

**Time Estimates:**
- Critical Priority (NotGiven, basic transform, files): 2-3 days
- High Priority (full transform system): 5-7 days
- Medium Priority (utilities, logging): 1-2 days
- Testing: 3-5 days
- **Total: 11-17 days** for complete utils port

---

## Appendix D: Example Manual Transform Implementation

```elixir
# lib/tinkex/types/create_session_request.ex
defmodule Tinkex.Types.CreateSessionRequest do
  @moduledoc """
  Request parameters for creating a training session.

  Automatically transforms Elixir-style snake_case keys to API-expected camelCase.
  """

  alias Tinkex.Utils.Transform

  @type t :: %{
    model_name: String.t(),
    batch_size: pos_integer(),
    learning_rate: float(),
    created_at: DateTime.t() | nil,
    metadata: map() | nil
  }

  @field_aliases %{
    model_name: "modelName",
    batch_size: "batchSize",
    learning_rate: "learningRate",
    created_at: "createdAt"
  }

  @doc """
  Transform Elixir params to API format.

  ## Example

      iex> params = %{
      ...>   model_name: "gpt-2",
      ...>   batch_size: 32,
      ...>   learning_rate: 0.001,
      ...>   created_at: ~U[2025-11-26 12:00:00Z]
      ...> }
      iex> CreateSessionRequest.to_api_format(params)
      %{
        "modelName" => "gpt-2",
        "batchSize" => 32,
        "learningRate" => 0.001,
        "createdAt" => "2025-11-26T12:00:00Z"
      }
  """
  @spec to_api_format(t()) :: map()
  def to_api_format(params) do
    params
    |> Transform.strip_not_given()
    |> Transform.rename_keys(@field_aliases)
    |> Transform.format_dates()
    |> Transform.json_safe()
  end
end

# lib/tinkex/utils/transform.ex
defmodule Tinkex.Utils.Transform do
  @moduledoc """
  Request transformation utilities.

  Converts Elixir-style parameters to API-compatible format.
  """

  @not_given :__not_given__

  def strip_not_given(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> v == @not_given end)
    |> Map.new()
  end

  def rename_keys(params, aliases) when is_map(params) do
    Map.new(params, fn {k, v} ->
      new_key = Map.get(aliases, k, to_string(k))
      {new_key, v}
    end)
  end

  def format_dates(params) when is_map(params) do
    Map.new(params, fn
      {k, %DateTime{} = v} -> {k, DateTime.to_iso8601(v)}
      {k, %Date{} = v} -> {k, Date.to_iso8601(v)}
      {k, v} when is_map(v) -> {k, format_dates(v)}
      {k, v} when is_list(v) -> {k, Enum.map(v, &format_value/1)}
      {k, v} -> {k, v}
    end)
  end

  defp format_value(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp format_value(%Date{} = v), do: Date.to_iso8601(v)
  defp format_value(v) when is_map(v), do: format_dates(v)
  defp format_value(v), do: v

  def json_safe(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, json_safe(v)} end)
  end
  def json_safe(data) when is_list(data) do
    Enum.map(data, &json_safe/1)
  end
  def json_safe(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def json_safe(%Date{} = d), do: Date.to_iso8601(d)
  def json_safe(data), do: data
end
```

---

## Summary

The utils module represents a **CRITICAL GAP** in the Elixir tinkex port. While some functionality is not applicable to Elixir (async/sync conversion, type introspection), the core transformation system is absolutely essential for the SDK to function.

**Top Priorities:**
1. ✅ Implement NotGiven pattern (2-4 hours)
2. ✅ Implement basic transform utilities (1 day)
3. ✅ Implement file extraction (1 day)
4. ✅ Build transform system (3-5 days manual approach, or 5-7 days type-driven)
5. ✅ Add logging setup (2-4 hours)

**Recommended Approach:**
Start with **manual transformation** approach for each request type. This is Elixir-idiomatic, type-safe, and easy to debug. Extract common patterns into `Tinkex.Utils.Transform` helper module. If too repetitive, consider building a macro system in Phase 2.

**Estimated Total Effort:** 11-17 days for complete utils module implementation.
