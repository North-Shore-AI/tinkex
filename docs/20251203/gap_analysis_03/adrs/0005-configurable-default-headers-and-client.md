# ADR 0005: Support configurable default headers/query and custom HTTP client

## Context
- Python `AsyncTinker` accepts `default_headers`, `default_query`, and a custom `http_client`, letting users inject org-wide headers, proxies, or tuning per client.
- Elixir `Tinkex.Config` lacks equivalent fields; callers cannot set global headers/query params or supply a custom Finch/HTTP client.

## Decision
- Extend `Tinkex.Config` (and ServiceClient construction) to accept:
  - `:default_headers`/`:default_query` merged into every request before user-supplied per-call headers/params.
  - An injectable HTTP client/pool override for advanced tuning/testing.
- Preserve existing precedence (opts > app config > env) and keep defaults unchanged when unset.

## Consequences
- Enables parity features (org headers, per-client query defaults, custom transports).
- Slightly broader surface area; document precedence and validation to avoid conflicting options.
