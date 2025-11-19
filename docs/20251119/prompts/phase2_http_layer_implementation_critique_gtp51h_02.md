Short answer: the overall Phase 2 shape is solid and very “Elixir-y” (config threading, clear module boundaries, Bypass-based tests), but the retry implementation as written is **incorrect**, x-should-retry semantics are too narrow, and there are a few places where you’re fighting your own constraints (multi-tenancy vs global Finch env, config/env split). I’d also explicitly justify “Finch over Req” in the doc, because right now the choice is implicit.

I’ll go section by section, then give a prioritized punch-list.

---

## 1. Finch vs Req – should this really be Finch?

### Why Finch makes sense here

For an SDK like this, Finch actually is a pretty defensible choice:

1. **HTTP/2 and connection pools are first-class concerns**

   Phase 2 is all about **pool shape** (training/sampling/session/futures/telemetry) and **pool selection per request**. Finch is literally “a small HTTP client built on Mint that focuses on connection pools”.

   You’re doing things Req doesn’t expose as ergonomically:

   ```elixir
   Finch.request(request, config.http_pool,
     receive_timeout: timeout,
     pool: Tinkex.PoolKey.build(config.base_url, pool_type)
   )
   ```

   That `pool:` option, combined with `{normalized_base, :pool_type}` keys, is exactly what Finch wants to do and what Req mostly hides from you.

2. **SDK, not app: you want a very thin HTTP dependency**

   For an SDK that’s going to be embedded in other apps:

   * Fewer layers = fewer surprises for downstream users.
   * Finch has a small, stable surface area: `build`, `request`, pool config.
   * You already have your own concerns: retry policy, categorised errors, telemetry events, multi-tenant config.

   If you used Req, you’d probably run with a “dumbed-down” subset anyway (you already want your own retry logic and error types), which makes the extra abstraction less valuable.

3. **You already have your own “Req-like” abstraction: `Tinkex.API`**

   Your `Tinkex.API.post/3`/`get/2` *is* the high-level client:

   * JSON encoding/decoding
   * retry logic
   * error shaping into `Tinkex.Error`
   * pool selection

   So stacking Req on top of Finch, then Tinkex.API on top of Req, is likely overkill.

### When Req *would* be tempting

Req would be nice if:

* This was an *application* rather than a reusable SDK.
* You wanted built-in middleware for:

  * redirects
  * robust retry plugins
  * auth plugins
* You didn’t care about explicit Finch pools per operation – a single “client” abstraction with global configuration would be fine.

Given your requirements (strict retry semantics, per-operation pools, multi-tenant config), I’d keep Finch, but make this explicit in the doc:

> “We use Finch directly instead of Req because we need explicit control over Finch pools per {base_url, operation}, and we already provide our own retry, error, and config abstractions via `Tinkex.API` and `Tinkex.Config`.”

That way future readers don’t “helpfully” swap it out for Req and break the invariants.

If you want a compromise: define an internal behaviour, e.g. `Tinkex.HTTPClient`, with a Finch implementation now and leave the door open for a Req-based implementation later. But I wouldn’t start with Req.

---

## 2. Tinkex.PoolKey

### What looks good

* Centralising URL normalisation is **exactly** right; having a single source of truth for pool keys is a big deal.
* Stripping default ports (80/443) is nice and matches typical pool key design.
* Returning `:default` for the default pool keeps call-sites simple.

### Things I’d tighten

1. **Guard against malformed URLs**

   Right now:

   ```elixir
   uri = URI.parse(url)
   "#{uri.scheme}://#{uri.host}#{port}"
   ```

   If someone passes `"localhost:4000"` or just `"tinker"`, you’ll generate `"nil://nil"`. For a library, I’d rather *fail loud* than silently generate a nonsense pool key.

   Suggested tweak:

   ```elixir
   def normalize_base_url(url) when is_binary(url) do
     case URI.parse(url) do
       %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
         # existing port logic

       _ ->
         raise ArgumentError, "invalid base_url for pool key: #{inspect(url)}"
     end
   end
   ```

2. **Consider downcasing host**

   HTTP hosts are case-insensitive, so:

   ```elixir
   host = String.downcase(uri.host || "")
   ```

   That prevents subtle pool splitting if someone mis-cases a base_url.

---

## 3. Tinkex.Config

### Good:

* `Config.new/1` with env defaults is a reasonable compromise with your “no Application.get_env at call time” rule.
* Having `http_pool`, `timeout`, `max_retries` on config is good for multi-tenancy.
* Having a `validate!/1` helper is nice, though you aren’t using it yet.

### Concerns & suggestions

1. **The “no Application.get_env at call time” rule is a bit leaky**

   The doc says:

   > NO Application.get_env at call time – Config must be threaded through function calls.

   But `Config.new/1` *is* a call-time env lookup. Practically, that’s fine if:

   * you call `Config.new/1` once per logical client, not per request, and
   * you’re explicit about that in the doc (“we only read env when constructing Configs, never inside the HTTP layer”).

   I’d add that clarification to Phase 2, otherwise someone could reasonably think `Config.new/1` is off-limits too.

2. **Consider enforcing required fields**

   You already raise if `api_key` is missing in `new/1`. For strictness, I’d either:

   * add `@enforce_keys [:base_url, :api_key]` and have `new/1` always set them, or
   * call `validate!/1` in `new/1` so a hand-constructed `%Config{}` doesn’t slip through with `nil` api_key.

3. **Base URL vs app-level pools**

   Tension: `Tinkex.Application` builds pools for *one* base_url (from `Application.get_env(:tinkex, :base_url, ...)`), but `Config` allows arbitrary `base_url`. For a config whose base_url doesn’t match the “boot” base_url:

   * `Tinkex.PoolKey.build/2` will produce `{other_base, :training}`, etc.
   * Finch *will* happily create an on-the-fly pool using the default pool config when it sees a new key – meaning your carefully tuned pool sizes are only guaranteed for the env base_url.

   That’s not necessarily wrong, but it’s worth documenting:

   * Either: “Phase 2 only guarantees pool shape for the configured `:tinkex, :base_url`; other base URLs use the default pool config.”
   * Or: move pool config into a function of base_url so that additional tenants can also get tuned pools.

---

## 4. Tinkex.API – this is where the dragons are 🐉

This is the critical part, and it has both design wins and a serious bug.

### 4.1 The big bug: `with_retries/3` clause ordering

Current code (simplified):

```elixir
defp with_retries(fun, max_retries, attempt) do
  case fun.() do
    # 1. Matches ALL {:ok, %Finch.Response{}} responses
    {:ok, %Finch.Response{headers: headers} = response} = success ->
      case List.keyfind(headers, "x-should-retry", 0) do
        ...
      end

    # 2. Intended 429 case
    {:ok, %Finch.Response{status: 429, headers: headers}} = response ->
      ...

    # 3. Intended 5xx/408 case
    {:ok, %Finch.Response{status: status}} = response
    when status >= 500 or status == 408 ->
      ...
    ...
  end
end
```

Because the first clause matches **any** `{:ok, %Finch.Response{}}`, the 429 and 5xx branches are **never reachable**. That means:

* You don’t actually use Retry-After for 429s.
* You don’t retry on 5xx/408 based on status at all.
* You only ever retry when `x-should-retry: "true"` is present (and even then, only with your exponential backoff, not Retry-After).

Your own sample tests in the doc for “retries on 5xx” and “uses Retry-After for 429” would fail against this implementation, which is actually good: they’ll catch it.

**Fix**: either reorder or change the pattern shapes. For example:

```elixir
defp with_retries(fun, max_retries, attempt) do
  case fun.() do
    {:ok, %Finch.Response{status: status, headers: headers} = resp} = raw ->
      case should_retry?(status, headers, attempt, max_retries) do
        {:retry, delay_ms} ->
          Process.sleep(delay_ms)
          with_retries(fun, max_retries, attempt + 1)

        :no_retry ->
          raw
      end

    {:error, %Mint.TransportError{}} = error ->
      retry_or_return(error, attempt, max_retries)

    {:error, %Mint.HTTPError{}} = error ->
      retry_or_return(error, attempt, max_retries)

    other ->
      other
  end
end
```

Where `should_retry?/4` can combine:

* `x-should-retry` (takes precedence),
* 429 + Retry-After,
* 5xx/408 + exponential backoff.

This also avoids pattern-matching by `status` multiple times.

### 4.2 x-should-retry semantics

Spec says:

> x-should-retry header – Server can override retry decisions

Right now you only check it on the “success” branch (and due to the bug, only that branch is used). Better semantics:

* If `x-should-retry: "false"` → **never** retry, regardless of status.
* If `x-should-retry: "true"` → **do** retry (subject to `max_retries`), regardless of status (including some 4xx if the server explicitly says so).
* Only if header is absent do you fall back to 429/5xx/408 heuristics.

So `should_retry?` could be:

```elixir
defp should_retry?(status, headers, attempt, max_retries) do
  if attempt >= max_retries do
    :no_retry
  else
    case header_value(headers, "x-should-retry") do
      "false" -> :no_retry
      "true" -> {:retry, retry_delay(attempt)}
      _ ->
        cond do
          status == 429 ->
            {:retry, parse_retry_after(headers)}
          status == 408 or status in 500..599 ->
            {:retry, retry_delay(attempt)}
          true ->
            :no_retry
        end
    end
  end
end
```

### 4.3 “Don’t retry user errors”

You correctly **don’t retry** 4xx (except 408/429), which is the primary practical case.

The doc also says:

> Don’t retry on user errors (error category = :user)

Your current design never inspects `error_data["category"]` inside `with_retries/3`, because you don’t decode JSON until `handle_response/1` *after* retries. If the backend ever returns 5xx with `"category": "user"`, you’d still retry. In practice that’s probably fine, but it technically violates your spec.

Two options:

* Adjust the spec to state that “user error” check is **primarily status-based** in the HTTP layer, and category is applied post-hoc via `Tinkex.Error.user_error?/1`.
* Or: decode just enough JSON inside `with_retries/3` for 5xx responses to look at the `category` field, at the cost of some duplicated JSON decode work.

I’d choose the first (simpler) and update the spec accordingly.

### 4.4 JSON decode errors

Your success clause:

```elixir
defp handle_response({:ok, %Finch.Response{status: status, body: body}})
     when status >= 200 and status < 300 do
  case Jason.decode(body) do
    {:ok, data} -> {:ok, data}
    {:error, reason} ->
      {:error, %Tinkex.Error{ ... type: :validation ... }}
  end
end
```

That’s reasonable. A few small polish points:

* Consider a `Tinkex.Error.new/3` call instead of constructing the struct manually for consistency.
* If you ever add telemetry, this is a natural place to emit a “response decode failure” event.

### 4.5 Generic `{:error, exception}` clause

```elixir
defp handle_response({:error, exception}) do
  {:error, %Tinkex.Error{
    message: Exception.message(exception),
    type: :api_connection,
    data: %{exception: exception}
  }}
end
```

`Exception.message/1` expects a struct implementing the `Exception` behaviour. If some library returns `{:error, :timeout}` or `{:error, :closed}`, you’ll get an `ArgumentError`. Safer:

```elixir
message =
  case exception do
    %_{} -> Exception.message(exception)
    other -> inspect(other)
  end
```

Small thing, but it makes the HTTP layer more robust.

---

## 5. Endpoint modules (`Tinkex.API.*`)

These are mostly nice thin wrappers – that’s good.

### What works

* Separating pool types here keeps `Tinkex.API` generic.
* You already encode “no retries from HTTP layer” for sampling and “low retries” for telemetry.
* Specs are in place and match the `{:ok, map()} | {:error, Tinkex.Error.t()}` contract.

### Tweaks

1. **Telemetry “fire and forget” comment is misleading**

   `Tinkex.API.Telemetry.send/2`:

   ```elixir
   def send(request, opts) do
     # Fire and forget - don't block on telemetry
     opts
     |> Keyword.put(:pool_type, :telemetry)
     |> Keyword.put(:max_retries, 1)
     |> then(&Tinkex.API.post("/api/v1/telemetry", request, &1))
   end
   ```

   This is still a synchronous HTTP call – the caller blocks until requests completes. That’s fine *if* callers are expected to put this inside a Task.

   I’d either:

   * Change the comment (“callers are expected to run this asynchronously”), or
   * Actually make it fire-and-forget in this layer, e.g.:

     ```elixir
     def send(request, opts) do
       Task.start(fn ->
         opts
         |> Keyword.put(:pool_type, :telemetry)
         |> Keyword.put(:max_retries, 1)
         |> then(&Tinkex.API.post("/api/v1/telemetry", request, &1))
         :ok
       end)

       :ok
     end
     ```

   Whether you want that behaviour in Phase 2 is a design choice, but the doc should match reality.

2. **Consider typed response helpers**

   For the “service” endpoints, you’ve already got `CreateSessionResponse.from_json/1`, etc. You might want to standardise endpoint patterns:

   ```elixir
   def create(request, opts) do
     with {:ok, json} <- Tinkex.API.post("/api/v1/create_session", request, opts) do
       {:ok, Tinkex.Types.CreateSessionResponse.from_json(json)}
     end
   end
   ```

   That keeps “JSON map” confined to `Tinkex.API` + types, and exposes only typed DTOs from these higher-level modules.

---

## 6. `Tinkex.Application` + Finch pools

### Good:

* Using `{normalized_base, pool_type}` keys ties nicely to `PoolKey`.
* Pool sizes roughly match your usage patterns: small for training/session, large for sampling, etc.
* For `:session` you set `max_idle_time: :infinity`, which makes sense for heartbeat-style traffic.

### Points to watch

1. **Application not wired up yet**

   `mix.exs`:

   ```elixir
   def application do
     [
       extra_applications: [:logger]
     ]
   end
   ```

   To actually start your Application module, you’ll need:

   ```elixir
   def application do
     [
       mod: {Tinkex.Application, []},
       extra_applications: [:logger]
     ]
   end
   ```

   Not strictly Phase 2 code, but Phase 2 won’t “work” in a real app without this.

2. **Dynamic tenants again**

   As mentioned earlier: pools are tuned for the env base_url. Other base URLs get whatever Finch does for unknown pools (usually copying `:default` config). If multi-tenancy with different base URLs is a primary use case, you probably want that behaviour to be explicit in the doc.

3. **Telemetry**

   You mention telemetry in the high-level docs but don’t instrument the HTTP layer yet. Phase 2 might at least define the events you’ll emit later, even if implementation comes in a later phase, e.g.:

   * `[:tinkex, :http, :request, :start]`
   * `[:tinkex, :http, :request, :stop]`
   * `[:tinkex, :http, :request, :exception]`

---

## 7. Tests & TDD section

The proposed tests are very good – especially the Bypass-based retry tests. A few comments:

* **APITest should stay non-async.** You already omit `async: true` in the snippet; keep it that way because Bypass can be fussy with concurrent tests.
* The tests for 5xx and 429 are exactly what you need to protect against the `with_retries/3` bug – they should fail loudly if someone “fixes” the function in a way that breaks semantics.
* Consider adding a test for `x-should-retry: "true"` on a 400 to show that the header truly overrides normal retry logic.

---

## 8. Prioritised punch-list

If I were reviewing this as a PR, here’s what I’d ask for before merge:

1. **Fix `with_retries/3` clause ordering and semantics**

   * Ensure 429 and 5xx/408 branches actually execute.
   * Honour `x-should-retry` for *all* statuses and give it precedence.
   * Add tests for:

     * 5xx retry with exponential backoff
     * 429 using Retry-After ms
     * `x-should-retry: "false"` suppressing retries even for 5xx
     * `x-should-retry: "true"` triggering retries even for a 4xx like 400.

2. **Harden the generic error clause**

   * Safely handle non-Exception error terms in `handle_response/1`.

3. **Clarify / slightly adjust `Tinkex.Config`**

   * Document that env is only read during config construction.
   * Optionally call `validate!/1` inside `new/1`.
   * Consider `@enforce_keys` for `base_url` and `api_key`.

4. **Tighten `Tinkex.PoolKey`**

   * Add validation for clearly invalid base URLs.
   * Optionally downcase host.

5. **Align comments with behaviour**

   * Update Telemetry “fire and forget” comment or change implementation.
   * Add a short justification for “Finch over Req” in the Phase 2 doc.

6. **Wire up `Tinkex.Application` in `mix.exs`**

   * Add `mod: {Tinkex.Application, []}` so your Finch pools actually come up.

---

If you’d like, I can also draft a revised `with_retries/3` and a small `Tinkex.HTTPClient` behaviour so you can keep Finch now but make swapping to Req (or something else) trivial later.
