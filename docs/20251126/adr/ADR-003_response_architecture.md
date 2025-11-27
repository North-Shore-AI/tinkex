# ADR-003: Response Wrappers, Validation, and Streaming

- **Status:** Accepted
- **Date:** 2025-11-26

## Context
- Python wraps responses (`BaseAPIResponse`, `APIResponse`, SSE streams) with metadata, parsing, and validation, including strict mode and pagination helpers.
- Elixir currently returns decoded maps from `lib/tinkex/api/api.ex` with no metadata, no typed parsing/validation, no pagination helpers, and no SSE support.

## Decision
- Add a minimal response struct exposing status, headers, url, retries, and body accessors.
- Provide opt-in parsing to typed structs (where present) plus a strict validation toggle; keep defaults lenient to avoid breaking callers.
- Implement SSE decoder/stream for endpoints that advertise `text/event-stream`.
- Add pagination helper functions (`has_next_page`, `next_page_info`, `get_next_page`) as a thin layer atop existing REST calls.

## Consequences
- Clients can inspect metadata and stream responses.
- Validation failures become explicit errors instead of silent map passthrough.
- Enables future CLI/table outputs to use typed pages.

## Evidence
- Python behavior: `tinker/src/tinker/_response.py`, `_streaming.py`.
- Elixir gap: `lib/tinkex/api/api.ex` directly returns `{:ok, map()}` with no wrappers; no SSE modules present.
