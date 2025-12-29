# multipart_ex Library Design (Client-Agnostic Multipart + File Helpers)

## Status
- Draft: 2025-12-27
- Target repo: `/home/home/p/g/n/multipart_ex`
- Source inventory: `lib/tinkex/multipart/*` and `lib/tinkex/files/*`

## Repository and Branding Requirements
- Create repo via GitHub CLI under `nshkrdotcom` (user account, not org).
- Use a long, multi-sentence description (GitHub + `mix.exs`).
- Max out GitHub topics; the last topic must be `nshkr-utilility`.
- Place hexagonal logo at `assets/multipart_ex.svg`.
- Add the logo at the top of `README.md` and wire it into `mix.exs` docs.

### Topics (maxed, last required)
```
elixir,erlang,beam,http,multipart,form-data,upload,streaming,finch,req,tesla,hackney,client,library,serializer,content-type,forms,files,adapter,nshkr-utilility
```

### README + Docs Branding
- `README.md` top: `![multipart_ex](assets/multipart_ex.svg)`
- `mix.exs` docs:
  - `logo: "assets/multipart_ex.svg"`
  - `assets: %{"assets" => "assets"}`

## Problem Statement
The Tinkex multipart implementation is tightly coupled to Finch, uses implicit
path detection, and loads entire files into memory. These are unacceptable for a
standalone library. We need a strict, stream-first, client-agnostic multipart
builder with configurable serialization strategies.

## Forensic Findings (Tinkex)
- **Implicit Path Vulnerability**: `lib/tinkex/files/reader.ex` treats strings
  containing `/` or `.` as file paths. This can read sensitive files or crash
  on user input. This is an LFI/TOCTOU class risk.
- **OOM Risk**: `lib/tinkex/multipart/encoder.ex` concatenates the full body
  into a binary; large uploads can exhaust memory.
- **Rigid Serialization**: `lib/tinkex/multipart/form_serializer.ex` hardcodes
  bracket notation; many backends expect dot or flat styles.

## Goals
- **Explicit Safety**: no implicit path detection; use explicit `{:path, path}`.
- **Memory Efficiency**: stream-first encoding with constant memory usage.
- **Protocol Flexibility**: pluggable serialization strategies.
- **Client Agnostic**: adapters for Finch/Req/Tesla/Hackney without coupling.

## Non-Goals
- Server-side multipart parsing.
- Full MIME database inside core (use optional dependency).

## Core Domain Model
### Multipart.Part
```elixir
defmodule Multipart.Part do
  defstruct body: nil,
            headers: [],
            disposition: "form-data",
            params: %{},
            size: nil
end
```
- `body`: `iodata()` or `Stream.t()`
- `headers`: list of header tuples
- `disposition` + `params`: structured `Content-Disposition`
- `size`: optional byte size for Content-Length

### Multipart (container)
```elixir
defmodule Multipart do
  defstruct parts: [], boundary: nil, preamble: nil, epilogue: nil
end
```
- Lazy boundary generation via `:crypto.strong_rand_bytes`.

## File Normalization (Safety First)
Supported inputs:
- `{:path, Path.t()}` (explicit file path)
- `{:content, binary(), filename}` (in-memory content)
- `%Multipart.Part{}` (advanced control)
- `{filename, content}` / `{filename, content, content_type}` /
  `{filename, content, content_type, headers}` (compatibility form)

Strict rule: bare strings are **never** treated as file paths.

## Serialization Strategies
`Multipart.Form.serialize/2` supports:
- `:bracket` (default) - Rails/PHP
- `:dot` - Java/Spring/Go
- `:flat` - reject nested structures

List handling options for `:dot`:
- `:repeat` (default), `:index`, or `:dot_index`

Nil handling:
- `:skip` (default) or `:empty` (send key with empty body)

## Encoder (Streaming)
- `Multipart.Encoder.encode/2` returns `{content_type, body}`.
- `body` may be `iodata()` or `Stream.t()` depending on parts.
- Use `Stream.concat` to emit boundary/header/body/CRLF lazily.

Content-Length:
- If all parts have known sizes, return `{:ok, len}`.
- If any part is unknown, omit length and allow chunked transfer.

## MIME Type Inference (Optional)
- Optional dependency on `mime`.
- If available, infer from filename; otherwise default to
  `application/octet-stream`.

## Client Adapters
- `Multipart.Adapter.Finch`: returns `{:stream, stream}` body and headers.
- `Multipart.Adapter.Req`: attaches a request step to set body/headers.
- Keep adapters in separate modules; core remains client-agnostic.

## Tinkex Integration Plan
1. Extract into `multipart_ex` with new strict API.
2. Add shim in Tinkex to preserve legacy tuple inputs.
3. Emit deprecation warning for implicit paths; remove shim in follow-up.
4. Replace `Tinkex.Multipart.*` and `Tinkex.Files.*` usage.

## Testing Plan
- Property tests for serialization (nested maps + lists).
- Round-trip: encode with multipart_ex, parse with Plug.Parsers.Multipart.
- Streaming/OOM test using large or infinite streams.
- Compatibility tests for Finch and Req adapters.

## Open Questions
- Should we ship a small ring buffer option for drop-old semantics? (likely no)
- Should `Multipart.Part` expose convenience builders for common cases?
