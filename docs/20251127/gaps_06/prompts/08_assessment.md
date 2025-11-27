# Gap #8 Assessment: Proxies & Custom HTTP Clients

**Date:** 2025-11-27
**Status:** IMPLEMENT (Minimal Scope)

## Finding

**This is a REAL gap** - unlike #5-7 which were dead code.

Python SDK provides proxy support via "pass your own httpx client" with **zero documentation**.
Elixir/Finch already supports proxies - just needs Config exposure.

## Recommendation

**Implement minimal Config-based proxy support (~50 LOC):**

```elixir
# Add to Config
defstruct [..., :proxy, :proxy_headers]

# Pass to Finch in Application.start
conn_opts: [proxy: config.proxy, proxy_headers: config.proxy_headers]
```

## What to Skip

- ❌ HTTPClient behaviour abstraction (overengineered)
- ❌ Per-request proxy (Finch doesn't support)
- ❌ Custom implementations (nobody will use)

## Effort

~4-6 hours total:
- Config changes: 1 hour
- Application.ex changes: 1 hour
- Tests: 2 hours
- Documentation: 1-2 hours

## Why This Gap is Different

| Gap | Python Usage | Verdict |
|-----|--------------|---------|
| #5 Transform | Dead code | Skip |
| #6 Streaming | Unused | Skip |
| #7 extra_* | Boilerplate | Skip |
| **#8 Proxy** | **Real (undocumented)** | **Implement** |
