# API Mismatches Analysis - Gap 02

This directory contains the analysis and decision records for API mismatches identified between the Python Tinker SDK and the Elixir Tinkex port.

## Overview

Two API inconsistencies were identified during the SDK port:

1. **Heartbeat Endpoint Path Mismatch**
   - Python: `/api/v1/session_heartbeat`
   - Elixir: `/api/v1/heartbeat`

2. **List User Checkpoints Pagination Default**
   - Python: limit=100 (default)
   - Elixir: limit=50 (default)

## ADRs

- [ADR-001: API Endpoint and Paging Alignment](./adrs/001_api_mismatches.md) - Comprehensive analysis and recommendation to align Elixir to match Python

## Quick Summary

**Recommendation**: Align Elixir implementation to match Python SDK

**Changes Required**:
1. Update `lib/tinkex/api/session.ex` line 60: `/api/v1/heartbeat` → `/api/v1/session_heartbeat`
2. Update `lib/tinkex/api/rest.ex` line 55: default limit 50 → 100
3. Update `lib/tinkex/rest_client.ex` line 131: default limit 50 → 100

**Rationale**:
- Python is the reference implementation
- Fewer Elixir users = lower migration impact
- Both changes are backward compatible
- Aligns with industry standards

## Impact Assessment

- **Heartbeat Change**: Transparent (internal implementation detail)
- **Pagination Change**: Minor behavior change, but backward compatible (more data, not less)
- **Breaking Changes**: None
- **Migration Required**: None (optional: users can explicitly set `limit: 50` if desired)

## Next Steps

1. Review and approve ADR-001
2. Verify server supports `/api/v1/session_heartbeat`
3. Implement changes per ADR-001 Phase 2
4. Run tests per ADR-001 Phase 3
5. Update documentation per ADR-001 Phase 4
6. Release new version per ADR-001 Phase 5

## Files Analyzed

### Python SDK
- `tinker/src/tinker/resources/service.py`
- `tinker/src/tinker/lib/public_interfaces/rest_client.py`

### Elixir SDK
- `lib/tinkex/api/session.ex`
- `lib/tinkex/api/rest.ex`
- `lib/tinkex/rest_client.ex`
- `lib/tinkex/session_manager.ex`

---

**Date**: 2025-11-26
**Status**: Analysis Complete, Awaiting Implementation
