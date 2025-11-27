# ADR-002: Cloudflare Access Header Support

## Status
Proposed

## Context

### Problem Statement
The Python Tinker SDK automatically injects Cloudflare Access authentication headers (`CF-Access-Client-Id` and `CF-Access-Client-Secret`) from environment variables, enabling seamless integration with Zero-Trust protected deployments. The Elixir Tinkex port lacks this capability entirely, preventing it from accessing Cloudflare-protected API endpoints without manual workarounds that are not currently supported.

### Current Python Implementation

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\service_client.py`

**Lines 375-389:**
```python
def _get_default_headers() -> dict[str, str]:
    headers = {}

    if (api_key := os.environ.get("TINKER_API_KEY", "")) and "X-API-Key" not in headers:
        headers["X-API-Key"] = api_key

    if (
        client_id := os.environ.get("CLOUDFLARE_ACCESS_CLIENT_ID")
    ) and "CF-Access-Client-Id" not in headers:
        headers["CF-Access-Client-Id"] = client_id
    if (
        client_secret := os.environ.get("CLOUDFLARE_ACCESS_CLIENT_SECRET")
    ) and "CF-Access-Client-Secret" not in headers:
        headers["CF-Access-Client-Secret"] = client_secret
    return headers
```

**Key Behaviors:**
1. Reads from environment variables: `CLOUDFLARE_ACCESS_CLIENT_ID` and `CLOUDFLARE_ACCESS_CLIENT_SECRET`
2. Only injects headers if env vars are present (graceful degradation)
3. Avoids overwriting if headers are already present (defensive coding)
4. Called in `ServiceClient.__init__()` (line 59) and merged with user-provided `default_headers`
5. These headers are automatically included in ALL HTTP requests made by the SDK

**Usage in Python:** Lines 58-65 show integration into client initialization:
```python
def __init__(self, user_metadata: dict[str, str] | None = None, **kwargs: Any):
    default_headers = _get_default_headers() | kwargs.pop("default_headers", {})
    self.holder = InternalClientHolder(
        user_metadata=user_metadata,
        **kwargs,
        default_headers=default_headers,
        _strict_response_validation=True,
    )
```

### Current Elixir Implementation

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\api\api.ex`

**Lines 256-272 - Header Building:**
```elixir
defp build_headers(method, api_key, opts, timeout_ms) do
  [
    {"accept", "application/json"},
    {"content-type", "application/json"},
    {"user-agent", user_agent()},
    {"connection", "keep-alive"},
    {"accept-encoding", "gzip"},
    {"x-api-key", api_key}
  ]
  |> Kernel.++(stainless_headers(timeout_ms))
  |> Kernel.++(request_headers(opts))
  |> Kernel.++(idempotency_headers(method, opts))
  |> Kernel.++(sampling_headers(opts))
  |> Kernel.++(maybe_raw_response_header(opts))
  |> Kernel.++(Keyword.get(opts, :headers, []))
  |> dedupe_headers()
end
```

**Key Observations:**
1. **No Cloudflare header support** - Neither environment variable reading nor config-based injection
2. API key is read from config (passed as parameter), not directly from environment
3. Custom headers can be passed via `opts[:headers]` (line 270), but this is per-request, not SDK-wide
4. No mechanism for default headers that apply to all requests

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\config.ex`

**Lines 14-22 - Config Struct:**
```elixir
@enforce_keys [:base_url, :api_key]
defstruct [
  :base_url,
  :api_key,
  :http_pool,
  :timeout,
  :max_retries,
  :user_metadata
]
```

**Key Observations:**
1. No fields for Cloudflare credentials
2. No `default_headers` or similar field for SDK-wide headers
3. API key is pulled from config/env (lines 45-48) but no similar pattern for Cloudflare headers

**Lines 45-48 - API Key Sourcing:**
```elixir
api_key =
  opts[:api_key] ||
    Application.get_env(:tinkex, :api_key) ||
    System.get_env("TINKER_API_KEY")
```

This pattern shows the SDK **does** know how to read from `System.get_env()`, establishing precedent.

### Gap Analysis

| Aspect | Python SDK | Elixir SDK | Gap |
|--------|-----------|-----------|-----|
| **CF Client ID** | Auto-injected from `CLOUDFLARE_ACCESS_CLIENT_ID` | Not supported | ❌ Missing |
| **CF Client Secret** | Auto-injected from `CLOUDFLARE_ACCESS_CLIENT_SECRET` | Not supported | ❌ Missing |
| **Config Fields** | Runtime via `default_headers` kwarg | No `default_headers` in Config | ❌ Missing |
| **Env Var Reading** | Yes (`os.environ.get()`) | Pattern exists for API key | ✅ Precedent exists |
| **Per-Request Override** | Yes (merge with user headers) | Yes (`opts[:headers]`) | ✅ Partial |
| **Zero-Trust Support** | Full | None | ❌ Blocking |

### Impact

**Critical Scenarios Blocked:**
1. **Production deployments** behind Cloudflare Access cannot use Tinkex
2. **Enterprise environments** with Zero-Trust architecture are unsupported
3. **Multi-tenant scenarios** requiring different CF credentials per client instance
4. **Security-conscious deployments** that mandate Cloudflare protection

**Workaround Attempts:**
- Passing `headers: [{"CF-Access-Client-Id", id}, {"CF-Access-Client-Secret", secret}]` on every API call is:
  - **Tedious** - Must be added to every `post/3`, `get/2`, `delete/2` call
  - **Error-prone** - Easy to forget for new endpoints
  - **Non-idiomatic** - Violates DRY principle
  - **Breaks abstraction** - Higher-level client modules would need to thread headers through

## Decision Drivers

1. **Security Parity** - Elixir SDK must support same security patterns as Python SDK
2. **Zero-Trust Enablement** - Enable deployment in Cloudflare Access protected environments
3. **Developer Experience** - Users should not need to manually inject headers on every call
4. **Configuration Flexibility** - Support both environment variables (12-factor) and programmatic config
5. **Backward Compatibility** - Must not break existing code
6. **Elixir Idioms** - Follow Elixir patterns for configuration management
7. **Minimal Surface Area** - Keep API changes focused and simple

## Considered Options

### Option 1: Environment Variables Only (Minimal)

**Implementation:**
- Add env var reading in `build_headers/4` function
- Read `CLOUDFLARE_ACCESS_CLIENT_ID` and `CLOUDFLARE_ACCESS_CLIENT_SECRET` directly
- Inject headers if env vars are present

**Pros:**
- ✅ Minimal code change (single function modification)
- ✅ Zero API surface changes
- ✅ Matches Python's environment-first approach
- ✅ Backward compatible (no config changes needed)
- ✅ Follows 12-factor app principles

**Cons:**
- ❌ No runtime override capability (must set env vars before BEAM starts)
- ❌ Not suitable for multi-tenant scenarios (single set of credentials per VM)
- ❌ Testing requires manipulating environment
- ❌ Less explicit than config-based approach

**Code Changes:**
```elixir
# In lib/tinkex/api/api.ex, modify build_headers/4:
defp build_headers(method, api_key, opts, timeout_ms) do
  [
    {"accept", "application/json"},
    {"content-type", "application/json"},
    {"user-agent", user_agent()},
    {"connection", "keep-alive"},
    {"accept-encoding", "gzip"},
    {"x-api-key", api_key}
  ]
  |> Kernel.++(stainless_headers(timeout_ms))
  |> Kernel.++(cloudflare_headers())  # NEW
  |> Kernel.++(request_headers(opts))
  |> Kernel.++(idempotency_headers(method, opts))
  |> Kernel.++(sampling_headers(opts))
  |> Kernel.++(maybe_raw_response_header(opts))
  |> Kernel.++(Keyword.get(opts, :headers, []))
  |> dedupe_headers()
end

# Add new function:
defp cloudflare_headers do
  []
  |> maybe_put_cf("CF-Access-Client-Id", System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID"))
  |> maybe_put_cf("CF-Access-Client-Secret", System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET"))
end

defp maybe_put_cf(headers, _name, nil), do: headers
defp maybe_put_cf(headers, name, value), do: [{name, value} | headers]
```

### Option 2: Config-Based with Env Fallback (Flexible)

**Implementation:**
- Add `cf_access_client_id` and `cf_access_client_secret` fields to `Tinkex.Config`
- Source from config options, app env, or system env (priority order)
- Pass through config to `build_headers/4`
- Inject headers if config values are present

**Pros:**
- ✅ Runtime configuration possible (multi-tenant support)
- ✅ Testable without environment manipulation
- ✅ Explicit in config struct
- ✅ Follows existing API key pattern
- ✅ Supports per-client credentials

**Cons:**
- ❌ Larger API surface change (config struct modification)
- ❌ More code changes across multiple modules
- ❌ Requires passing config to `build_headers/4` (currently receives api_key string)
- ❌ More complex implementation

**Code Changes:**
```elixir
# In lib/tinkex/config.ex:
defstruct [
  :base_url,
  :api_key,
  :http_pool,
  :timeout,
  :max_retries,
  :user_metadata,
  :cf_access_client_id,      # NEW
  :cf_access_client_secret   # NEW
]

@type t :: %__MODULE__{
  # ... existing types ...
  cf_access_client_id: String.t() | nil,
  cf_access_client_secret: String.t() | nil
}

def new(opts \\ []) do
  # ... existing code ...

  cf_access_client_id =
    opts[:cf_access_client_id] ||
      Application.get_env(:tinkex, :cf_access_client_id) ||
      System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID")

  cf_access_client_secret =
    opts[:cf_access_client_secret] ||
      Application.get_env(:tinkex, :cf_access_client_secret) ||
      System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET")

  %__MODULE__{
    # ... existing fields ...
    cf_access_client_id: cf_access_client_id,
    cf_access_client_secret: cf_access_client_secret
  }
end

# In lib/tinkex/api/api.ex:
# Modify all call sites to pass config instead of just api_key
defp build_headers(method, config, opts, timeout_ms) do
  # ... base headers ...
  |> Kernel.++(cloudflare_headers(config))
  # ...
end

defp cloudflare_headers(config) do
  []
  |> maybe_put_cf("CF-Access-Client-Id", config.cf_access_client_id)
  |> maybe_put_cf("CF-Access-Client-Secret", config.cf_access_client_secret)
end
```

### Option 3: Default Headers Map (Python-like)

**Implementation:**
- Add `default_headers` map field to `Tinkex.Config`
- Allow users to specify arbitrary default headers
- Automatically inject CF headers from env into default headers
- Merge default headers in `build_headers/4`

**Pros:**
- ✅ Maximum flexibility (any default headers)
- ✅ Direct Python SDK parity
- ✅ Single field addition
- ✅ Extensible for future header needs

**Cons:**
- ❌ Less type-safe than dedicated fields
- ❌ Headers become opaque to config inspection
- ❌ No validation of header names/values
- ❌ Requires map merge logic

**Code Changes:**
```elixir
# In lib/tinkex/config.ex:
defstruct [
  # ... existing ...
  :default_headers  # NEW - map of string => string
]

def new(opts \\ []) do
  env_headers = %{
    "CF-Access-Client-Id" => System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID"),
    "CF-Access-Client-Secret" => System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET")
  }
  |> Enum.reject(fn {_, v} -> is_nil(v) end)
  |> Map.new()

  default_headers =
    Map.merge(env_headers, opts[:default_headers] || %{})

  %__MODULE__{
    # ...
    default_headers: default_headers
  }
end

# In lib/tinkex/api/api.ex:
defp build_headers(method, api_key, opts, timeout_ms) do
  # ... base headers ...
  |> Kernel.++(config_default_headers(opts[:config]))
  # ...
end

defp config_default_headers(nil), do: []
defp config_default_headers(%{default_headers: headers}) when is_map(headers) do
  Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)
end
```

### Option 4: Hybrid - Env Only with Future Config Extension Point

**Implementation:**
- Implement Option 1 (env vars only) immediately
- Add `default_headers` field to Config (empty for now)
- Document extension point for future multi-tenant needs
- Keep door open for runtime config later

**Pros:**
- ✅ Fast to implement (unblocks Zero-Trust now)
- ✅ Minimal surface area
- ✅ Leaves room for enhancement
- ✅ Config change is minimal (single optional field)

**Cons:**
- ❌ Two-phase implementation (technical debt)
- ❌ Multi-tenant still unsupported in phase 1

## Decision

**Recommended Approach: Option 2 - Config-Based with Env Fallback**

### Rationale

1. **Long-term Flexibility**: Multi-tenant scenarios are increasingly common in SaaS environments. Supporting runtime configuration from the start avoids future breaking changes.

2. **Follows Existing Patterns**: The API key is already handled via config with env fallback. Cloudflare headers should follow the same pattern for consistency.

3. **Type Safety**: Dedicated fields in the config struct provide compile-time guarantees and better IDE support compared to a generic map.

4. **Testability**: Config-based approach allows tests to instantiate clients with specific credentials without manipulating global environment state.

5. **Explicitness**: Config struct clearly documents all SDK configuration options in one place.

6. **Elixir Idioms**: Structured configs are preferred over implicit environment reading in Elixir libraries.

### Justification vs. Other Options

- **vs. Option 1 (Env Only)**: While simpler, it permanently closes the door on multi-tenant use cases. The additional complexity is justified by future-proofing.

- **vs. Option 3 (Default Headers Map)**: While more flexible, it sacrifices type safety and documentation clarity. CF headers are important enough to warrant dedicated fields.

- **vs. Option 4 (Hybrid)**: While pragmatic, it creates technical debt. Better to do it right once than revisit later with a breaking change.

## Consequences

### Positive

1. **Zero-Trust Support**: Tinkex can now be deployed behind Cloudflare Access protection
2. **Enterprise Readiness**: Meets security requirements of enterprise deployments
3. **Multi-Tenant Capability**: Different Tinkex clients can use different CF credentials
4. **Feature Parity**: Closes gap with Python SDK
5. **Idiomatic Elixir**: Follows established config patterns in the Elixir ecosystem
6. **Backward Compatible**: Existing code continues to work (new fields are optional)
7. **Testable**: Tests can inject credentials programmatically

### Negative

1. **Config Surface Area**: Two new fields in Config struct
2. **Implementation Complexity**: Need to refactor `build_headers/4` signature to accept config
3. **Documentation Burden**: Must document new env vars and config options
4. **Potential Confusion**: Users might not understand when CF headers are needed
5. **Performance**: Two additional map lookups per request (negligible, but measurable)

### Neutral

1. **Security Considerations**: Credentials in memory (same risk as API key)
2. **Logging**: Must ensure CF secrets are masked in debug output (similar to API key masking)

## Implementation Plan

### Phase 1: Config Extension (1-2 hours)

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\config.ex`

1. Add fields to struct (line 21):
   ```elixir
   defstruct [
     # ... existing ...
     :cf_access_client_id,
     :cf_access_client_secret
   ]
   ```

2. Add to typespec (line 24):
   ```elixir
   @type t :: %__MODULE__{
     # ... existing ...
     cf_access_client_id: String.t() | nil,
     cf_access_client_secret: String.t() | nil
   }
   ```

3. Add sourcing logic in `new/1` (after line 48):
   ```elixir
   cf_access_client_id =
     opts[:cf_access_client_id] ||
       Application.get_env(:tinkex, :cf_access_client_id) ||
       System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID")

   cf_access_client_secret =
     opts[:cf_access_client_secret] ||
       Application.get_env(:tinkex, :cf_access_client_secret) ||
       System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET")
   ```

4. Add to struct instantiation (line 60):
   ```elixir
   %__MODULE__{
     # ... existing ...
     cf_access_client_id: cf_access_client_id,
     cf_access_client_secret: cf_access_client_secret
   }
   ```

5. Add masking to `Inspect` impl (line 152):
   ```elixir
   data =
     config
     |> Map.from_struct()
     |> Map.update(:api_key, nil, &Tinkex.Config.mask_api_key/1)
     |> Map.update(:cf_access_client_secret, nil, &mask_secret/1)
   ```

6. Add masking helper:
   ```elixir
   defp mask_secret(nil), do: nil
   defp mask_secret(secret) when is_binary(secret), do: "[REDACTED]"
   defp mask_secret(other), do: other
   ```

### Phase 2: API Module Refactor (2-3 hours)

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\api\api.ex`

1. Change `build_headers/4` signature (line 256):
   ```elixir
   # OLD:
   defp build_headers(method, api_key, opts, timeout_ms)

   # NEW:
   defp build_headers(method, config, opts, timeout_ms)
   ```

2. Update API key reference in base headers (line 263):
   ```elixir
   # OLD:
   {"x-api-key", api_key}

   # NEW:
   {"x-api-key", config.api_key}
   ```

3. Add CF headers injection (after line 265):
   ```elixir
   |> Kernel.++(cloudflare_headers(config))
   ```

4. Add new helper function (after line 272):
   ```elixir
   defp cloudflare_headers(%{cf_access_client_id: id, cf_access_client_secret: secret})
        when is_binary(id) and is_binary(secret) do
     [
       {"CF-Access-Client-Id", id},
       {"CF-Access-Client-Secret", secret}
     ]
   end

   defp cloudflare_headers(_config), do: []
   ```

5. Update all `build_headers/4` call sites (lines 36, 78, 119, 160):
   ```elixir
   # OLD:
   headers = build_headers(:post, config.api_key, opts, timeout)

   # NEW:
   headers = build_headers(:post, config, opts, timeout)
   ```

6. Update `redact_headers/1` to mask CF secret (line 633):
   ```elixir
   defp redact_headers(headers) do
     Enum.map(headers, fn
       {name, value} ->
         lower_name = String.downcase(name)
         cond do
           lower_name == "x-api-key" -> {name, "[redacted]"}
           lower_name == "cf-access-client-secret" -> {name, "[redacted]"}
           true -> {name, value}
         end

       other ->
         other
     end)
   end
   ```

### Phase 3: Documentation (1 hour)

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\README.md`

1. Add section on Cloudflare Access:
   ```markdown
   ### Cloudflare Access Integration

   Tinkex automatically supports Cloudflare Access protected deployments:

   #### Via Environment Variables (Recommended)
   ```elixir
   # Set before starting your application
   export CLOUDFLARE_ACCESS_CLIENT_ID="your-client-id"
   export CLOUDFLARE_ACCESS_CLIENT_SECRET="your-client-secret"

   # Tinkex will automatically include CF headers
   config = Tinkex.Config.new()
   ```

   #### Via Runtime Configuration
   ```elixir
   config = Tinkex.Config.new(
     cf_access_client_id: "your-client-id",
     cf_access_client_secret: "your-client-secret"
   )
   ```

   #### Via Application Config
   ```elixir
   # config/runtime.exs
   config :tinkex,
     cf_access_client_id: System.get_env("CLOUDFLARE_ACCESS_CLIENT_ID"),
     cf_access_client_secret: System.get_env("CLOUDFLARE_ACCESS_CLIENT_SECRET")
   ```
   ```

**File:** Create `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\docs\cloudflare_access.md`

2. Comprehensive guide on Cloudflare Access setup

### Phase 4: Testing (2-3 hours)

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\test\tinkex\config_test.exs`

1. Test CF config sourcing:
   ```elixir
   test "sources Cloudflare credentials from opts" do
     config = Config.new(
       cf_access_client_id: "test-id",
       cf_access_client_secret: "test-secret"
     )

     assert config.cf_access_client_id == "test-id"
     assert config.cf_access_client_secret == "test-secret"
   end

   test "sources Cloudflare credentials from env" do
     # Set env vars in test
     # Assert they're picked up
   end

   test "masks CF secret in inspect" do
     config = Config.new(cf_access_client_secret: "super-secret")
     inspected = inspect(config)

     refute String.contains?(inspected, "super-secret")
     assert String.contains?(inspected, "[REDACTED]")
   end
   ```

**File:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\test\tinkex\api\api_test.exs`

2. Test header injection:
   ```elixir
   test "includes Cloudflare headers when configured" do
     # Use test helper to capture headers sent
     # Assert CF-Access-Client-Id and CF-Access-Client-Secret present
   end

   test "omits Cloudflare headers when not configured" do
     # Assert headers not present when config fields are nil
   end

   test "redacts CF secret in debug logs" do
     # Enable TINKEX_DUMP_HEADERS
     # Assert secret is redacted
   end
   ```

### Phase 5: Validation (1 hour)

1. Manual testing against CF-protected endpoint
2. Verify backward compatibility (existing tests still pass)
3. Performance regression check (header building overhead)
4. Security audit (ensure no credential leaks in logs)

### Total Estimated Effort: 7-10 hours

## References

### Python SDK
- **Service Client:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\tinker\src\tinker\lib\public_interfaces\service_client.py`
  - Lines 375-389: `_get_default_headers()` implementation
  - Lines 58-65: Integration into ServiceClient initialization

### Elixir SDK (Before Changes)
- **Config:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\config.ex`
  - Lines 14-22: Config struct definition
  - Lines 45-48: API key sourcing pattern (precedent for CF headers)
  - Lines 145-156: Inspect implementation (masking pattern)

- **API:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\api\api.ex`
  - Lines 256-272: `build_headers/4` function (needs refactor)
  - Lines 36, 78, 119, 160: Call sites (need signature update)
  - Lines 633-644: `redact_headers/1` (needs CF secret masking)

### Related Documentation
- **Gap Analysis:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\docs\20251126\gaps_02\cloudflare_access_headers.md`
- **Cloudflare Access Docs:** https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/

### Environment Variables
- `CLOUDFLARE_ACCESS_CLIENT_ID` - Client ID for Cloudflare Access service token
- `CLOUDFLARE_ACCESS_CLIENT_SECRET` - Client secret for Cloudflare Access service token
- `TINKER_API_KEY` - Existing API key (precedent for env var pattern)

---

**Document Version:** 1.0
**Created:** 2025-11-26
**Author:** Claude (ADR Analysis)
**Status:** Proposed - Awaiting Implementation
