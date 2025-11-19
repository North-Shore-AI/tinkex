Here are the things that still look off to me after reading both your port docs and the packed Python repo.



I’ll group them into \*\*(A) concrete mismatches\*\*, \*\*(B) architectural inconsistencies\*\*, and \*\*(C) edge cases / design gaps\*\*.



---



\## A. Concrete mismatches with the Python SDK



These are places where your Elixir plan doesn’t quite match what’s in the Python repo you embedded.



\### 1. ImageChunk / ImageAssetPointerChunk field names



In `01\_type\_system.md` you describe:



```python

class ImageChunk(BaseModel):

&nbsp;   image\_data: str

&nbsp;   image\_format: str



class ImageAssetPointerChunk(BaseModel):

&nbsp;   asset\_id: str

```



But the actual Python types (from the packed repo) are:



```python

\# tinker/types/image\_chunk.py

class ImageChunk(StrictBase):

&nbsp;   data: bytes

&nbsp;   format: Literal\["png", "jpeg"]

&nbsp;   height: int

&nbsp;   tokens: int

&nbsp;   width: int

&nbsp;   type: Literal\["image"] = "image"



\# tinker/types/image\_asset\_pointer\_chunk.py

class ImageAssetPointerChunk(StrictBase):

&nbsp;   format: Literal\["png", "jpeg"]

&nbsp;   height: int

&nbsp;   location: str

&nbsp;   tokens: int

&nbsp;   width: int

&nbsp;   type: Literal\["image\_asset\_pointer"] = "image\_asset\_pointer"

```



With base64 handled via validators/serializers on `data`.



\*\*Implications for Tinkex:\*\*



\* Your Elixir structs must use the \*\*actual field names\*\* (`data`, `format`, `height`, `width`, `tokens`, `location`, `type`), not `image\_data`, `image\_format`, or `asset\_id`.

\* JSON shape must match the Python client’s JSON (base64 string in `data`, etc.), otherwise the Elixir SDK will generate incompatible payloads.



Right now the doc text is misleading; if you follow it literally you’ll send the wrong JSON.



---



\### 2. `SampleRequest.prompt\_logprobs` optionality vs default



In `01\_type\_system.md` you show:



```python

class SampleRequest(BaseModel):

&nbsp;   ...

&nbsp;   # Optional fields

&nbsp;   num\_samples: int = 1

&nbsp;   prompt\_logprobs: bool = False

&nbsp;   topk\_prompt\_logprobs: int = 0

```



But the actual type is:



```python

\# tinker/types/sample\_request.py

class SampleRequest(StrictBase):

&nbsp;   ...

&nbsp;   prompt\_logprobs: Optional\[bool] = None

&nbsp;   topk\_prompt\_logprobs: int = 0

```



So:



\* Python: \*\*`Optional\[bool] = None`\*\* (“not set” vs `false` are distinguishable)

\* Your plan: \*\*`bool = False`\*\* (collapses “not set” into `false`)



Given you’ve just gone to a lot of trouble to correctly distinguish `None` vs “not given”, this is a subtle regression: the Elixir struct should probably model this as `boolean | nil` with default `nil`, and let Jason encode `nil → null` (or omit field if you later decide `omit\_if\_nil`).



Same goes for any other fields where your doc “simplified” `Optional\[T] = None` into a non-optional default.



---



\### 3. `SaveWeightsForSamplerResponse` shape



Python:



```python

\# tinker/types/save\_weights\_for\_sampler\_response.py

class SaveWeightsForSamplerResponseInternal(BaseModel):

&nbsp;   path: str | None = None

&nbsp;   sampling\_session\_id: str | None = None

&nbsp;   type: Optional\[Literal\["save\_weights\_for\_sampler"]] = None



class SaveWeightsForSamplerResponse(BaseModel):

&nbsp;   path: str

```



So the \*\*public\*\* type only exposes `path`; `sampling\_session\_id` is hidden behind an internal model.



Your Elixir mapping in several places talks as if both `path` and `sampling\_session\_id` are on the main response; if you want feature parity with the Python public API, the user-facing type should expose only `path` (you can still parse and keep `sampling\_session\_id` internally if you need it).



Not a correctness bug, but it’s a behavioral divergence from Python.



---



\### 4. HTTP “Retry-After” date parsing



You say:



> \*\*Retry-After HTTP Date\*\*: Added support for HTTP Date format parsing (not just integers)



And show:



```elixir

defp parse\_http\_date\_delay(date\_string) do

&nbsp; # Parse HTTP Date and calculate delay from now

&nbsp; # Format: "Fri, 31 Dec 2025 23:59:59 GMT"

&nbsp; case :calendar.rfc3339\_to\_system\_time(date\_string, \[{:unit, :millisecond}]) do

&nbsp;   {:ok, target\_time} ->

&nbsp;     now = System.system\_time(:millisecond)

&nbsp;     max(target\_time - now, 1000)



&nbsp;   {:error, \_} ->

&nbsp;     1000

&nbsp; end

rescue

&nbsp; \_ -> 1000

end

```



But HTTP `Retry-After` \*\*date\*\* is in RFC 7231 “IMF-fixdate” format (`"Wed, 21 Oct 2015 07:28:00 GMT"`), \*not\* RFC3339. `:calendar.rfc3339\_to\_system\_time/2` will simply fail for valid HTTP dates, and you always fall back to 1000 ms.



So:



\* Either implement actual HTTP-date parsing (like the Python client does with `email.utils.parsedate\_tz`), or

\* Explicitly state you only support `retry-after-ms` / `retry-after: <seconds>` and drop the “HTTP Date” claim.



Right now, the doc claims you support dates but the code sketch doesn’t.



---



\## B. Architectural / consistency issues in the Elixir design



These are “your own docs disagree with themselves” or “multi-tenancy story breaks in edge cases”.



\### 5. Config vs Finch pools: multi-tenancy not actually supported



You say:



> `Tinkex.Config` supports different `base\_url` per client for multi-tenancy.



And your HTTP layer uses:



```elixir

Finch.request(request, pool\_name,

&nbsp; receive\_timeout: timeout,

&nbsp; pool: Tinkex.PoolKey.build(config.base\_url, pool\_type)

)

```



But in `Application.start/2` you build Finch pools once using a \*\*single\*\* base URL, read from `Application.get\_env(:tinkex, :base\_url, ...)`:



```elixir

base\_url = Application.get\_env(:tinkex, :base\_url, "https://...")



children = \[

&nbsp; {Finch, name: Tinkex.HTTP.Pool, pools: %{

&nbsp;   {normalized\_base, :training} => \[...],

&nbsp;   {normalized\_base, :sampling} => \[...],

&nbsp;   ...

&nbsp; }}

]

```



If a client uses `config.base\_url` that differs from the app-wide base\_url, `Tinkex.PoolKey.build(config.base\_url, :training)` will reference a Finch pool that was never defined → you’ll get runtime errors.



So \*\*right now, the design is “one base\_url per BEAM node”\*\*, not per client. That’s fine, but then:



\* Either drop “multi-tenancy by base\_url” from the docs and constrain base\_url to global config, \*\*or\*\*

\* Rework pool strategy so pools are keyed purely by `:training | :sampling | ...` (no base\_url), or

\* Dynamically create per-base\_url pools (more complex).



Same issue for the \*\*RateLimiter\*\*: you key it only by `api\_key`:



```elixir

:ets.lookup(:tinkex\_rate\_limiters, {:limiter, api\_key})

```



If you ever \*do\* allow different base URLs with the same API key (e.g. staging vs prod), those clients would share backoff state even if the upstreams have independent limits. Keying by `{base\_url, api\_key}` would be safer and more in line with the Python “per-client-holder” behavior.



\### 6. RateLimiter API and SamplingClient snippets are out of sync



You introduce:



```elixir

defmodule Tinkex.RateLimiter do

&nbsp; def for\_api\_key(api\_key), do: ...

end

```



But later, your “Updated SamplingClient.init/1” example still uses the old API:



```elixir

rate\_limiter = Tinkex.RateLimiter.new()

...

:ok = Tinkex.SamplingRegistry.register(self(), config)

```



There’s no `new/0` in the latest RateLimiter sketch.



This is mostly documentation drift, but if you copy-paste code from the doc you’ll hit undefined function errors. Worth cleaning so there’s one canonical API (probably `for\_api\_key/1` or better `for\_key({base\_url, api\_key})`).



\### 7. SamplingClient + RateLimiter + with\_retries: double responsibility



Right now:



\* `Tinkex.API.post/4` has `with\_retries/3` that \*\*retries on 5xx / 408 / 429\*\*, using `retry\_after\_ms` for 429.

\* `Tinkex.SamplingClient.sample/5` also does \*\*429-specific backoff\*\* via `RateLimiter` and then calls `Tinkex.API.Sampling.asample(... max\_retries: 0)`.



That’s okay for sampling because you explicitly zero out retries there, but for other API modules (training, futures) you’re relying solely on `with\_retries`.



Make sure this is explicit:



\* “Sampling is special: no HTTP-level retries; we handle 429 via RateLimiter + caller-level retry.”

\* “Training/futures use HTTP-level retries; no RateLimiter.”



Right now the plan is consistent but that split of responsibilities is subtle and easy to accidentally break later (e.g. someone removes `max\_retries: 0` from sampling and now 429 is retried twice at two layers).



\### 8. ServiceClient \& Config: mixed patterns



You have two different patterns in the docs:



\* Older `ServiceClient.init/1` using `Application.get\_env/3` directly to build a config map.

\* Newer pattern with `Tinkex.Config` being passed in and threaded everywhere.



It’s easy to end up with:



```elixir

config = opts\[:config] || Tinkex.Config.new(opts)

state = %{config: config, ...}

```



in some places and a custom map in others, and then your HTTP layer expects a `Tinkex.Config.t` struct but receives a plain map.



I’d strongly recommend:



\* Make `Tinkex.Config` the \*\*only\*\* config struct, and

\* Ensure all examples (ServiceClient, API layer, SamplingClient) show that, not the older “bare map” style.



Right now the text still mixes both.



---



\## C. Edge cases and behavioral gaps



These aren’t “bugs” yet, but they’re things you probably want to tighten before calling v1.0 “solid”.



\### 9. Cancellation \& caller death with `Task.start + GenServer.reply`



Pattern used in `TrainingClient.handle\_call/3`:



```elixir

Task.start(fn ->

&nbsp; reply =

&nbsp;   try do

&nbsp;     # poll futures

&nbsp;     {:ok, combined}

&nbsp;   rescue

&nbsp;     e -> {:error, ...}

&nbsp;   end



&nbsp; GenServer.reply(from, reply)

end)



{:noreply, new\_state}

```



This fixes the “Task crash ⇒ no reply” problem (good), but there are still a couple of edge cases:



\* If the \*\*caller process dies or times out\*\* before the polling task finishes, `GenServer.reply/2` will raise `ArgumentError` (`badarg`). You don’t handle that, so you’ll see noisy errors in logs. It might be worth wrapping `GenServer.reply/2` itself in a `try/rescue` and just ignoring `:badarg`.

\* There’s no way for the caller to \*cancel\* a long-running training operation; they can kill their own Task, but the GenServer + background Task will keep going and still hit the server. That might be acceptable for v1.0, but it’s worth documenting (“there is no cancellation; operations run to completion on the server”).



Not show-stoppers, but very much the kind of thing that bites you in production.



\### 10. Telemetry → HTTP layer drift



Your Telemetry reporter example still calls something like:



```elixir

Tinkex.API.Telemetry.send(request, pool)

```



But the final HTTP layer API requires a `config` in `opts`:



```elixir

Tinkex.API.post(path, body, pool\_name, opts ++ \[config: config])

```



So in actual implementation you’ll need to thread a `Tinkex.Config` into the telemetry reporter as well. Right now, the docs assume the pre-Config signature.



Same for any other “fire and forget” calls that don’t pass config.



\### 11. Streaming section vs actual SSE implementation



You explicitly mark streaming as “SKETCH ONLY / NOT PRODUCTION READY”, which is good, but the project still has a full SSE implementation in `tinker/\_streaming.py` in the Python repo.



Two things to be careful about:



\* Your Elixir docs currently underplay how tricky it is to do SSE properly: you need a buffer across chunks, and your sketch currently discards that problem.

\* If you later port the Python SSE logic, you’ll probably want parity with `AsyncStream` semantics (one consumption only, `StreamAlreadyConsumed` behavior, etc.) to avoid surprising users.



Not a v1.0 blocker since you’ve explicitly scoped it out, but I’d keep the warnings very prominent in the README, not just in the internal design doc.



---



\## 12. Summary of “fix these before you code” items



If I had to prioritize:



1\. \*\*Fix type mismatches\*\* in `01\_type\_system.md`



&nbsp;  \* Correct `ImageChunk` \& `ImageAssetPointerChunk` field names and shapes.

&nbsp;  \* Correct `SampleRequest.prompt\_logprobs` to be `boolean | nil` with default `nil` to match Python.

2\. \*\*Clarify multi-tenancy story\*\*



&nbsp;  \* Either constrain `base\_url` to a single global value or rework Finch pool keys so per-client base URLs are actually supported.

&nbsp;  \* Probably key RateLimiter by `{base\_url, api\_key}` rather than just `api\_key`.

3\. \*\*Align RateLimiter \& SamplingClient docs\*\*



&nbsp;  \* Decide on RateLimiter API (`for\_api\_key/1` vs `new/0`) and make all snippets consistent.

4\. \*\*Fix Retry-After date parsing claim\*\*



&nbsp;  \* Either implement real HTTP-date parsing or explicitly drop it and say “we only support numeric delays”.

5\. \*\*Clean up config threading examples\*\*



&nbsp;  \* Use `Tinkex.Config` everywhere (ServiceClient, Telemetry, HTTP layer) in the docs; avoid direct `Application.get\_env` in hot paths.



Everything else is more “nice to have” or “document more clearly” than “this will definitely blow up”, but those five are the ones I’d address before you start serious implementation so you’re not refactoring foundational pieces mid-port.



