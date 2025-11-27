# ADR-001: API Endpoint and Paging Alignment

## Status
Proposed

## Context

During the port of the Tinker SDK from Python to Elixir (Tinkex), two API inconsistencies were identified that create incompatibility between the implementations:

### 1. Heartbeat Endpoint Path Mismatch

**Python Implementation:**
- File: `tinker/src/tinker/resources/service.py` (lines 112-154)
- Endpoint: `/api/v1/session_heartbeat`
- Method: POST
- Request body: `SessionHeartbeatRequest(session_id=session_id)`

```python
async def session_heartbeat(
    self,
    *,
    session_id: str,
    # ... other params ...
) -> SessionHeartbeatResponse:
    """Send a heartbeat for an active session to keep it alive"""
    request = SessionHeartbeatRequest(session_id=session_id)
    return await self._post(
        "/api/v1/session_heartbeat",  # Python endpoint
        body=model_dump(request, exclude_unset=True, mode="json"),
        options=options,
        cast_to=SessionHeartbeatResponse,
    )
```

**Elixir Implementation:**
- File: `lib/tinkex/api/session.ex` (lines 53-64)
- Endpoint: `/api/v1/heartbeat`
- Method: POST
- Request body: `%{session_id: session_id}`

```elixir
@spec heartbeat(map(), keyword()) ::
        {:ok, map()} | {:error, Tinkex.Error.t()}
def heartbeat(request, opts) do
  Tinkex.API.post(
    "/api/v1/heartbeat",  # Elixir endpoint - DIFFERENT!
    request,
    Keyword.put(opts, :pool_type, :session)
  )
end
```

**Usage Context:**
- The heartbeat is called by `Tinkex.SessionManager` (line 159) every 10 seconds by default
- It's critical for keeping sessions alive and preventing server-side timeout
- Python SDK also uses this for session lifecycle management via `InternalClientHolder`

**Impact:**
- Cross-SDK incompatibility: Sessions created by Python SDK cannot be heartbeated by Elixir SDK and vice versa
- Potential server-side routing issues if both endpoints exist
- Documentation confusion about the canonical endpoint

### 2. List User Checkpoints Pagination Default Mismatch

**Python Implementation:**
- File: `tinker/src/tinker/lib/public_interfaces/rest_client.py` (lines 513-571)
- Default limit: 100
- Method signature: `list_user_checkpoints(self, limit: int = 100, offset: int = 0)`
- Endpoint: `/api/v1/checkpoints`

```python
def _list_user_checkpoints_submit(
    self, limit: int = 100, offset: int = 0  # Python default: 100
) -> AwaitableConcurrentFuture[types.CheckpointsListResponse]:
    """Internal method to submit list user checkpoints request."""
    async def _list_user_checkpoints_async() -> types.CheckpointsListResponse:
        async def _send_request() -> types.CheckpointsListResponse:
            with self.holder.aclient(ClientConnectionPoolType.TRAIN) as client:
                params: dict[str, object] = {"limit": limit, "offset": offset}
                return await client.get(
                    "/api/v1/checkpoints",
                    options={"params": params},
                    cast_to=types.CheckpointsListResponse,
                )
            return await self.holder.execute_with_retries(_send_request)
    return self.holder.run_coroutine_threadsafe(_list_user_checkpoints_async())
```

**Elixir Implementation:**
- File: `lib/tinkex/api/rest.ex` (lines 46-58)
- Default limit: 50
- Method signature: `list_user_checkpoints(config, limit \\ 50, offset \\ 0)`
- File: `lib/tinkex/rest_client.ex` (lines 116-138)
- Also uses default limit: 50

```elixir
# lib/tinkex/api/rest.ex
@spec list_user_checkpoints(Config.t(), integer(), integer()) ::
        {:ok, map()} | {:error, Tinkex.Error.t()}
def list_user_checkpoints(config, limit \\ 50, offset \\ 0) do  # Elixir default: 50
  path = "/api/v1/checkpoints?limit=#{limit}&offset=#{offset}"
  API.get(path, config: config, pool_type: :training)
end

# lib/tinkex/rest_client.ex
@spec list_user_checkpoints(t(), keyword()) ::
        {:ok, CheckpointsListResponse.t()} | {:error, Tinkex.Error.t()}
def list_user_checkpoints(%__MODULE__{config: config}, opts \\ []) do
  limit = Keyword.get(opts, :limit, 50)  # Also 50 here
  offset = Keyword.get(opts, :offset, 0)

  case Rest.list_user_checkpoints(config, limit, offset) do
    {:ok, data} -> {:ok, CheckpointsListResponse.from_map(data)}
    error -> error
  end
end
```

**Impact:**
- Behavioral inconsistency: Users expect the same pagination behavior across SDKs
- Different default page sizes mean different network performance characteristics
- Potential confusion when porting code between Python and Elixir
- Documentation examples may give different results depending on SDK

**Other Pagination Defaults for Context:**
Both SDKs agree on these defaults:
- `list_training_runs`: limit=20, offset=0 (both SDKs)
- `list_sessions`: limit=20, offset=0 (both SDKs)
- `list_checkpoints` (per run): No pagination, fetches all (both SDKs)

## Decision Drivers

1. **API Compatibility**: SDKs should be interoperable and provide the same developer experience
2. **Server-Side Expectations**: The canonical API contract must be identified and followed
3. **Backward Compatibility**: Changes should not break existing client code if possible
4. **Developer Ergonomics**: Defaults should be sensible and match user expectations
5. **Documentation Alignment**: API docs should accurately reflect both SDK behaviors
6. **Performance Considerations**: Pagination defaults affect network bandwidth and latency

## Considered Options

### Option 1: Align Elixir to Match Python (Recommended)

**Heartbeat Endpoint:**
- Change Elixir endpoint from `/api/v1/heartbeat` to `/api/v1/session_heartbeat`
- Update `lib/tinkex/api/session.ex` line 60

**Pagination Default:**
- Change Elixir default from 50 to 100
- Update `lib/tinkex/api/rest.ex` line 55
- Update `lib/tinkex/rest_client.ex` line 131

**Rationale:**
- Python SDK is the original/reference implementation
- Fewer Elixir users means lower migration impact
- Server likely expects `/api/v1/session_heartbeat` as the canonical endpoint
- Limit of 100 is more common in pagination APIs (GitHub, AWS, etc. use 100)

**Migration Impact:**
- Elixir users calling `list_user_checkpoints()` without explicit limit will get 100 items instead of 50
- This is a transparent change (more data, not less) and unlikely to break code
- Heartbeat endpoint change is transparent to SDK users (internal implementation)

### Option 2: Align Python to Match Elixir

**Heartbeat Endpoint:**
- Change Python endpoint from `/api/v1/session_heartbeat` to `/api/v1/heartbeat`
- Update `tinker/src/tinker/resources/service.py` line 150

**Pagination Default:**
- Change Python default from 100 to 50
- Update `tinker/src/tinker/lib/public_interfaces/rest_client.py` line 514, 536, 568

**Rationale:**
- Shorter endpoint name (`/heartbeat` vs `/session_heartbeat`) is cleaner
- Limit of 50 reduces initial bandwidth for users with many checkpoints
- Elixir is newer and may have made more considered decisions

**Migration Impact:**
- HIGH: Python has more users and is more established
- Breaking change for Python users who rely on getting 100 items by default
- Heartbeat endpoint change requires server-side support for both endpoints during transition
- Requires Python SDK version bump and deprecation cycle

### Option 3: Make Both Configurable at Runtime

**Implementation:**
- Add configuration option for heartbeat endpoint path
- Add server-side feature detection to use correct endpoint
- Keep different pagination defaults but document them clearly

**Rationale:**
- Allows gradual migration
- Supports multiple server versions
- No breaking changes for either SDK

**Migration Impact:**
- Increased complexity in both SDKs
- Requires server-side feature negotiation
- Documentation becomes more complex
- Users still face inconsistency until they configure

### Option 4: Accept the Divergence

**Implementation:**
- Document the differences in both SDKs
- Clearly note in migration guides
- Add server-side support for both endpoints if needed

**Rationale:**
- Zero migration cost
- Each SDK can optimize for its ecosystem conventions
- Reduces coordination overhead

**Migration Impact:**
- Permanent inconsistency between SDKs
- Harder to port code between languages
- May indicate lack of API stability/governance
- Poor developer experience when using both SDKs

## Decision

**Recommendation: Option 1 - Align Elixir to Match Python**

This decision is based on:

1. **Python as Reference**: The Python SDK is the original implementation and likely matches the server's expected API contract
2. **Minimal Impact**: Elixir SDK is newer with fewer users; changes are less disruptive
3. **Industry Standards**: Both changes align with common conventions:
   - More descriptive endpoint names (`session_heartbeat` clearly scopes the operation)
   - Pagination limit of 100 is industry standard (GitHub, AWS, Stripe, etc.)
4. **Transparent Changes**: Neither change breaks existing Elixir code:
   - Heartbeat endpoint is internal implementation detail
   - Higher default limit is backward compatible (returns more data, not less)

## Consequences

### Positive

1. **SDK Parity**: Both SDKs will behave identically for the same operations
2. **Clearer Documentation**: Examples and tutorials work across both SDKs
3. **Easier Code Porting**: Teams using both languages can port code with confidence
4. **Server Alignment**: Removes potential server-side routing ambiguity
5. **Better Performance**: Higher pagination default reduces round trips for users with many checkpoints
6. **No Breaking Changes**: Elixir users won't experience any breakage

### Negative

1. **Minor Behavior Change**: Elixir users who don't specify limit will get 100 items instead of 50
   - Mitigation: This is likely desirable; users wanted "all my checkpoints" anyway
   - Mitigation: Users who need 50 can explicitly pass `limit: 50`
2. **Server-Side Update**: If server only supports `/api/v1/heartbeat`, it needs to add `/api/v1/session_heartbeat`
   - Mitigation: Implement server-side alias or route both to same handler
   - Mitigation: Add server-side deprecation warning for old endpoint if needed
3. **Requires Testing**: Both changes need verification against live server
4. **Documentation Update**: All Elixir docs and examples need review

## Implementation Plan

### Phase 1: Investigation (Prior to Changes)

1. **Verify Server API Contract**
   - Check server-side routing configuration
   - Confirm which endpoint(s) the server actually supports
   - Review server API documentation
   - File: Check server codebase or OpenAPI spec

2. **Test Current Behavior**
   - Verify Python SDK actually uses `/api/v1/session_heartbeat` successfully
   - Verify Elixir SDK works with `/api/v1/heartbeat`
   - This confirms both endpoints exist or server has routing logic

### Phase 2: Code Changes

**File: `lib/tinkex/api/session.ex`**
```elixir
# Line 60: Change endpoint path
def heartbeat(request, opts) do
  Tinkex.API.post(
-    "/api/v1/heartbeat",
+    "/api/v1/session_heartbeat",
    request,
    Keyword.put(opts, :pool_type, :session)
  )
end
```

**File: `lib/tinkex/api/rest.ex`**
```elixir
# Line 55: Change default limit from 50 to 100
-def list_user_checkpoints(config, limit \\ 50, offset \\ 0) do
+def list_user_checkpoints(config, limit \\ 100, offset \\ 0) do
  path = "/api/v1/checkpoints?limit=#{limit}&offset=#{offset}"
  API.get(path, config: config, pool_type: :training)
end

# Lines 47-52: Update documentation comment
@doc """
List all checkpoints for the current user with pagination.

## Options
-  * `:limit` - Maximum number of checkpoints to return (default: 50)
+  * `:limit` - Maximum number of checkpoints to return (default: 100)
  * `:offset` - Offset for pagination (default: 0)
"""
```

**File: `lib/tinkex/rest_client.ex`**
```elixir
# Line 131: Change default limit from 50 to 100
def list_user_checkpoints(%__MODULE__{config: config}, opts \\ []) do
-  limit = Keyword.get(opts, :limit, 50)
+  limit = Keyword.get(opts, :limit, 100)
  offset = Keyword.get(opts, :offset, 0)

  case Rest.list_user_checkpoints(config, limit, offset) do
    {:ok, data} -> {:ok, CheckpointsListResponse.from_map(data)}
    error -> error
  end
end

# Lines 117-122: Update documentation comment
@doc """
List all checkpoints for the current user with pagination.

## Options
-  * `:limit` - Maximum number of checkpoints to return (default: 50)
+  * `:limit` - Maximum number of checkpoints to return (default: 100)
  * `:offset` - Offset for pagination (default: 0)
```

### Phase 3: Testing

1. **Unit Tests**
   - Add test to verify heartbeat calls `/api/v1/session_heartbeat`
   - Add test to verify default limit is 100 for `list_user_checkpoints`
   - Verify existing tests still pass

2. **Integration Tests**
   - Test heartbeat against live server
   - Test `list_user_checkpoints` with no params returns 100 items (if available)
   - Test explicit limit still works: `list_user_checkpoints(client, limit: 50)`

3. **Comparison Tests**
   - Run same operations in Python and Elixir
   - Verify identical results for same inputs
   - Verify heartbeat keeps session alive identically in both SDKs

### Phase 4: Documentation Updates

1. **Update API Documentation**
   - File: `README.md` - Update any examples showing `list_user_checkpoints`
   - File: Any tutorial/guide files - Search for pagination examples
   - File: ExDoc comments - Already updated in Phase 2

2. **Add Changelog Entry**
   - Document endpoint change (internal, non-breaking)
   - Document pagination default change (minor behavior change)
   - Recommend users relying on 50-item pages add explicit `limit: 50`

3. **Update Migration Guide** (if one exists)
   - Note: Elixir SDK now matches Python SDK pagination defaults
   - Note: No action required for most users

### Phase 5: Rollout

1. **Create PR** with changes from Phase 2
2. **Run CI/CD** to verify all tests pass
3. **Deploy** to staging environment
4. **Smoke Test** against staging server
5. **Merge** to main branch
6. **Release** new Tinkex version (minor version bump, e.g., 0.2.0 → 0.3.0)

### Validation Checklist

- [ ] Server supports `/api/v1/session_heartbeat` endpoint
- [ ] Python SDK confirmed using `/api/v1/session_heartbeat`
- [ ] Elixir endpoint updated to `/api/v1/session_heartbeat`
- [ ] Elixir pagination default updated to 100
- [ ] All unit tests pass
- [ ] Integration tests pass against live server
- [ ] Documentation updated
- [ ] Changelog updated
- [ ] PR reviewed and approved
- [ ] Changes deployed and smoke tested

## References

### Python SDK Files
- `tinker/src/tinker/resources/service.py` (lines 112-154) - Heartbeat implementation
- `tinker/src/tinker/lib/public_interfaces/rest_client.py` (lines 513-571) - Pagination implementation
- `tinker/src/tinker/types/session_heartbeat_request.py` - Request type
- `tinker/src/tinker/types/session_heartbeat_response.py` - Response type

### Elixir SDK Files
- `lib/tinkex/api/session.ex` (lines 53-64) - Heartbeat implementation
- `lib/tinkex/api/rest.ex` (lines 46-58) - Low-level REST API
- `lib/tinkex/rest_client.ex` (lines 116-138) - High-level client wrapper
- `lib/tinkex/session_manager.ex` (line 159) - Heartbeat caller

### Related Documentation
- Tinker API Specification (if available)
- Server-side routing configuration
- Python SDK documentation for `session_heartbeat`
- Elixir SDK documentation for `list_user_checkpoints`

### Industry Standards Referenced
- GitHub API: Default pagination limit of 100
- AWS API: Default pagination limit of 100
- Stripe API: Default pagination limit of 100
- REST API Design Best Practices (Richardson, Fielding)

---

**ADR Status**: Proposed (awaiting approval and implementation)
**Date**: 2025-11-26
**Authors**: Claude Code (gap analysis automation)
**Reviewers**: TBD
