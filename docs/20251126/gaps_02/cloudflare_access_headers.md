# Cloudflare Access headers

**Gap:** Python auto-injects Cloudflare Access headers from env; Elixir never forwards them.

- **Python feature set**
  - `_get_default_headers()` in `service_client.py` sets `CF-Access-Client-Id` and `CF-Access-Client-Secret` if env vars are present.
  - Ensures Zero-Trust protected deployments work without manual header wiring.
- **Elixir port status**
  - `lib/tinkex/api/api.ex` builds headers with API key + stainless metadata only; no Cloudflare headers.
  - No config/env plumbing for these values.
- **Impact**
  - Elixir SDK cannot reach CF-protected deployments unless callers manually inject headers (not currently supported), blocking certain environments.
- **Suggested alignment**
  1) Add optional config fields or env lookup for `CF-Access-Client-Id`/`CF-Access-Client-Secret`.
  2) Merge into default headers in `Tinkex.API` (similar to API key injection).
  3) Document expected env vars for Zero-Trust setups.
