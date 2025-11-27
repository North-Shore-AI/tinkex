# Gap #6 Assessment: Streaming API Parity

**Date:** 2025-11-27
**Status:** MOSTLY NOT NEEDED

## Finding

**Python's streaming infrastructure is NOT used.** All 7 resource files use regular request/response.

## Evidence

| Python Component | Exists | Used in Resources |
|------------------|--------|-------------------|
| `Stream[T]` | Yes | **0 calls** |
| `StreamedBinaryAPIResponse` | Yes | **0 calls** |
| `with_streaming_response` | Exposed | **0 calls** |

Checkpoint download in both SDKs: get signed URL, download externally (not via SDK streaming).

## One Valid Issue

`CheckpointDownload.do_download/3` loads entire file to RAM before writing.

**Fix:** Use `:httpc` streaming mode or `Finch.stream/5`. Effort: 2-4 hours.

## Recommendation

- Close "Streaming API Parity" gap - no Python streaming to match
- Create smaller issue: "Fix CheckpointDownload Memory" (one function fix)
- Skip proposed `Tinkex.Stream`, `BinaryStream`, `SSEBytesDecoder`, `API.Streaming` modules
