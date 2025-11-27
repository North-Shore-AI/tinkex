# Gap #7 Assessment: Raw REST "extra_*" Extension Points

**Date:** 2025-11-27
**Status:** NOT NEEDED

## Finding

**Python's `extra_query` and `extra_body` are boilerplate - exposed but NEVER used.**

## Evidence

| Parameter | Python Resources | Actual Usage |
|-----------|------------------|--------------|
| `extra_headers` | All 7 | Internal only (retry headers) |
| `extra_query` | All 7 | **0 calls** (tests only) |
| `extra_body` | All 7 | **0 calls** (tests only) |

## Elixir Already Has Equivalent Support

- Custom headers: `opts[:headers]` ✅
- Query params: String interpolation (clearer than runtime merging) ✅
- Body fields: Direct map passing ✅

## Recommendation

**Skip implementation.** Elixir's current approach is simpler and more type-safe than Python's over-engineered boilerplate.
