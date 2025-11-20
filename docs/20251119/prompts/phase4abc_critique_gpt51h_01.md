Overall these look quite strong and line up with the earlier Phase 1–3 prompts and port docs, but there are a few important mismatches with the current repo and some small places where an “agent” could go off the rails.

I’ll go prompt by prompt.

---

## Phase 4A – Runtime Foundations

### What’s working well

* Clear, bounded scope:

  * Application supervision tree.
  * SamplingRegistry as the ETS + monitor layer.
  * RateLimiter with `{normalized_base_url, api_key}` scoping and `:ets.insert_new/2`.
* You explicitly tie behaviour to the port docs:

  * Multi-tenancy, ETS table ownership, and RateLimiter semantics from `02_client_architecture` / `07_porting_strategy`.
  * Finch pool layout from `04_http_layer`.
* Constraints are good:

  * “No `Application.get_env` inside hot paths.”
  * ETS table options `(named_table, public, read_concurrency)` are spelled out.
  * RateLimiter keys must use `Tinkex.PoolKey.normalize_base_url/1`.

### Mismatches / missing details

1. **`Tinkex.Application` isn’t a stub in the repo**

   In the code snapshot you shared earlier, `lib/tinkex/application.ex` already:

   * Reads `:tinkex, :base_url`.
   * Normalizes it via `Tinkex.PoolKey`.
   * Starts a Finch supervisor with *exactly* the per-pool config you want (default, training, sampling, session, futures, telemetry).

   The prompt says:

   > `lib/tinkex/application.ex         # replace stub with full supervisor tree`

   That’s a bit misleading: the file is not a stub, it’s already doing the Finch work. The real work for 4A is:

   * **Extend** the existing Application to:

     * Create ETS tables (`:tinkex_sampling_clients`, `:tinkex_rate_limiters`, `:tinkex_tokenizers`) *before* children start.
     * Add `Tinkex.SamplingRegistry` and `Tinkex.ClientSupervisor` to the children list.

   If an agent “replaces” the file from scratch they might accidentally discard the carefully tuned pool configuration and `:enable_http_pools` flag logic. I’d change the wording to “extend/complete the Application” rather than “replace stub”.

2. **Who creates ETS tables vs who uses them**

   You correctly say:

   > Create ETS tables (…) in `Tinkex.Application`.

   And:

   > RateLimiter keys: `{Tinkex.PoolKey.normalize_base_url(base_url), api_key}`.
   > Tests must clean up ETS entries (not tables).

   That’s good, but two gotchas are worth making explicit:

   * **Tests that call `Tinkex.RateLimiter` or `SamplingRegistry` directly must ensure the app is started.** If a test calls `Tinkex.RateLimiter.for_key` before `Tinkex.Application.start/2` has run, they’ll get `:badarg` on `:ets.insert_new/2`.

     You can either:

     * Require tests to call `Application.ensure_all_started(:tinkex)`, or
     * Make RateLimiter lazily create the ETS table if missing (but your docs favour “centralized creation in Application”).

   * “Tests must clean up ETS entries” → clarify that they should remove rows from the named tables, not destroy / recreate the tables themselves, since those are shared across the app.

3. **Finch pool config duplication**

   You call out:

   > Finch pools must match doc table (sizes/timeouts).

   The current `application.ex` already sets sizes and `max_idle_time` in a way that matches the port docs; this is good, but it also means the prompt can easily get out of sync if you ever tweak the code.

   Small improvement: instead of restating sizes in the prompt, say “reuse the existing pool configuration in `Tinkex.Application` and only add ETS and additional children” to avoid drift.

Overall: 4A is in good shape; the main thing is to make sure implementers extend the existing Application rather than overwriting it.

---

## Phase 4B – SessionManager & ServiceClient

### Good parts

* Clear separation of concerns:

  * `SessionManager` owns session lifecycle + heartbeat.
  * `ServiceClient` is the high-level entry point that uses `SessionManager` and `DynamicSupervisor`.
* The public API surface is well sketched:

  * `SessionManager.start_session/1` & `stop_session/1`.
  * `ServiceClient.start_link/1` taking a `Tinkex.Config` or building one.
  * `create_lora_training_client/2`, `create_sampling_client/2`, etc.
* You tie behaviour to port docs:

  * Heartbeat intervals and session lifecycle from `02_client_architecture` / `07_porting_strategy`.
  * Config threading and multi-tenancy from `Tinkex.Config`.

### Issues / inconsistencies

1. **Heartbeat endpoint path vs existing API module**

   The prompt says:

   > Sends heartbeat via `Tinkex.API.post("/api/v1/session/heartbeat", ...)` on interval (e.g., 10s).

   But your repo already has `lib/tinkex/api/session.ex`:

   * `create/2` → `"/api/v1/create_session"`.
   * `heartbeat/2` → `"/api/v1/heartbeat"` (no `session/` segment).

   And tests for this module already expect `"/api/v1/heartbeat"`.

   So for consistency, `SessionManager` should:

   * Call `Tinkex.API.Session.create/2` or `create_typed/2` to open sessions.
   * Call `Tinkex.API.Session.heartbeat/2` (not raw `Tinkex.API.post("/api/v1/session/heartbeat")`).

   Otherwise you’ll have two parallel notions of “session heartbeat” with different paths. I’d update the prompt to explicitly reuse the `Session` API submodule and path that already exist.

2. **Assumption about who starts `SessionManager`**

   4B says:

   > `SessionManager` should be supervised (already started in Phase 4A).

   But 4A’s deliverables don’t list `SessionManager` among the children; they list:

   * ETS tables.
   * Finch.
   * `Tinkex.SamplingRegistry`.
   * `Tinkex.ClientSupervisor`.

   So right now the documents disagree:

   * Either 4A also needs to include `Tinkex.SessionManager` in the Application’s children, or
   * 4B needs to say “add `SessionManager` to `Tinkex.Application`’s children”.

   I’d fix this in *one* place (probably 4A, as the “runtime foundations” where all long-lived processes are wired up) and cross-reference it here.

3. **Reuse of existing API submodules is underplayed**

   The “Required Reading” correctly points to `lib/tinkex/api/api.ex`, and you mention “if API submodules don’t exist, create stubs”. But in your repo we *already* have:

   * `Tinkex.API.Session` (sessions),
   * `Tinkex.API.Service` (model creation, sampling session),
   * `Tinkex.API.Training`, `Tinkex.API.Sampling`, `Tinkex.API.Weights`.

   It would be less error-prone to say:

   > Reuse the existing `Tinkex.API.Session` and `Tinkex.API.Service` modules for session creation and heartbeats. Do not bypass them unless you are also updating those modules.

   That keeps your API surface coherent and avoids accidental duplication.

4. **Error-handling semantics for heartbeats are underspecified**

   You say:

   > Handles expired sessions (if heartbeat fails with user error, remove entry).

   Good start, but someone implementing this will have questions:

   * What about `5xx` or `:server` category errors—do we retry, or leave the session and try again at the next interval?
   * Should we stop heartbeating on `:user` errors only, or also on repeated `:server` errors after some limit?

   Since you already have a clean error categorization story (`Tinkex.Error` + `RequestErrorCategory`), it’d help to encode it here, e.g.:

   > If heartbeat fails with a user error (4xx excluding 408/429, or category `:user`), treat the session as expired and remove it. For transient errors (`:server`/`:unknown`, or 5xx/408/429), keep the session and log; let the next heartbeat retry.

5. **Session cardinality & multi-tenancy**

   The prompt says:

   > Maintains active sessions (session_id, heartbeat interval, config).

   But doesn’t state whether:

   * One `SessionManager` can host multiple sessions per different configs, or
   * It is “one session per ServiceClient” and the manager just tracks them as an internal map.

   The tests do mention a “multi-config” scenario for ServiceClient, so you probably *do* want `SessionManager` to handle multiple `config` values concurrently. A short clarification like:

   > SessionManager must support multiple concurrent sessions keyed by session_id (potentially with different configs), since multiple ServiceClients may be running at once.

   would nail that down.

Otherwise 4B is structurally sound; the main fixes are using the existing `Session` API and ensuring the supervision story is consistent.

---

## Phase 4C – Training & Sampling Clients

This is the most complex and the most tightly coupled to port docs, and it’s *mostly* right. There are a few important mismatches with the existing `Tinkex.API.Training` / `Tinkex.API.Sampling` modules though.

### Strong aspects

* TrainingClient’s sequencing model matches the docs:

  * GenServer state includes `model_id`, `config`, `request_id_counter`, `http_pool`.
  * `forward_backward/4` chunks data and performs **synchronous sends** in `handle_call`, then spawns a background Task to poll concurrently.
  * Background Task:

    * wraps in `try/rescue`,
    * uses `Tinkex.Future.poll/2`,
    * combines via `combine_forward_backward_results/1`,
    * calls `GenServer.reply/2` and rescues `ArgumentError`.
  * Safety checklist matches the earlier design in `02_client_architecture` and `03_async_model` (try/rescue, reply safety, reduce_while on send errors).

* SamplingClient design matches the ETS + RateLimiter plan:

  * GenServer only for init/cleanup.
  * `SamplingRegistry.register/2` owns ETS + monitors.
  * Public `sample/…` API reads from ETS, uses `Tinkex.RateLimiter.for_key/1`, increments an atomics counter, and calls the sampling API **without** going through the GenServer.
  * On 429, uses `error.retry_after_ms` to set backoff; no automatic retry (matches doc).

* Safety checklist is explicit and actionable:

  * “Never uses GenServer.call for sample; purely ETS + Task.”
  * “Always inject entry.config into API opts” to avoid `Keyword.fetch!` crashes.
  * “Use RateLimiter.for_key/1 with normalized base url + api_key.”

### Important mismatches / things to clarify

1. **Training API arity & semantics vs current repo**

   The prompt says:

   > Each call to `Tinkex.API.Training.forward_backward/3` returns `%{request_id: ...}`.

   But in your current repo, `lib/tinkex/api/training.ex` has:

   ```elixir
   @spec forward_backward(map(), keyword()) ::
           {:ok, map()} | {:error, Tinkex.Error.t()}
   def forward_backward(request, opts) do
     Tinkex.API.post("/api/v1/forward_backward", request, Keyword.put(opts, :pool_type, :training))
   end
   ```

   And tests assert that `forward_backward/2` returns a map with `metrics`, not a future:

   ```elixir
   {:ok, result} = Training.forward_backward(%{model_id: "test"}, config: config)
   assert result["metrics"]["loss"] == 0.5
   ```

   For Phase 4C’s design (“forward_backward returns futures, and TrainingClient uses `Future.poll/2` to get results”), you need to decide and document:

   * Are we changing the semantics of `Tinkex.API.Training.forward_backward/2` to return an *untyped future* (`%{"request_id" => "… "}`) instead of final metrics? If so, earlier tests must be updated accordingly.
   * Or are we introducing a **new** function (e.g. `forward_backward_future/2`) that TrainingClient uses, while the existing synchronous helper remains for low-level use?

   Right now the prompt assumes a future-returning API function that doesn’t exist and doesn’t mention the required test changes. That’s a significant implementation detail that should be called out.

   Same issue for `optim_step`: if the Python SDK uses futures there too, you may want the API to return `request_id` + use `Future.poll/2` for result, not a plain metrics map.

2. **Sampling API naming and arity mismatch**

   The prompt says:

   > Calls `Tinkex.API.Sampling.asample/3` with opts merged + `config: entry.config`.

   But in your repo, the sampling module is:

   ```elixir
   defmodule Tinkex.API.Sampling do
     @spec sample_async(map(), keyword()) ::
             {:ok, map()} | {:error, Tinkex.Error.t()}
     def sample_async(request, opts) do
       opts =
         opts
         |> Keyword.put(:pool_type, :sampling)
         |> Keyword.put(:max_retries, 0)

       Tinkex.API.post("/api/v1/asample", request, opts)
     end
   end
   ```

   So:

   * The function is `sample_async/2`, not `asample/3`.
   * The config is already passed via `opts[:config]`.

   For 4C, you probably want:

   * `SamplingClient.sample/…` to call `Tinkex.API.Sampling.sample_async(request, opts_with_config)` where `opts_with_config = opts |> Keyword.put(:config, entry.config)`.
   * And keep the existing sampling API module name + arity.

   I’d update the prompt to refer to `sample_async/2` and “opts + `config: entry.config`”, rather than `asample/3`.

3. **`sample/3` vs `sample/4` naming**

   In the “SamplingClient Requirements” you say:

   > Public API `sample(pid, prompt, opts)` returns `Task.t()`.

   In the Tests section you say:

   > `sample/4` fetches config, uses RateLimiter…

   Minor, but for an agent this is ambiguous: is `sample(pid, prompt, sampling_params, opts)` or `sample(pid, prompt, opts)`? Given `SampleRequest` has `prompt`, `sampling_params`, and other options, it’s worth pinning the shape down.

   Something like:

   > Public API: `sample(client_pid, prompt, sampling_params, opts \\ []) :: Task.t({:ok, SampleResponse.t()} | {:error, Tinkex.Error.t()})`.

   would remove guesswork.

4. **Return type of TrainingClient & SamplingClient functions**

   You describe TrainingClient’s internals nicely, but don’t explicitly say what *its* public functions return.

   E.g. “`forward_backward/4`”:

   * Should it return a `Task.t({:ok, ForwardBackwardOutput.t()} | {:error, Tinkex.Error.t()})` (as your Phase 3 design suggests for client APIs)?
   * Or should it return `{:ok, ForwardBackwardOutput.t()} | {:error, Tinkex.Error.t()}` directly?

   Given the rest of the design, the Task-returning approach is more consistent (TrainingClient operations = “future of result”), and aligns with `Future.poll/2` and `Future.await/2`. Worth stating the spec explicitly.

   Similarly for SamplingClient:

   * The prompt says “returns `Task.t()`” but doesn’t define the inner value. I’d tighten it to:

   > `sample/…` returns a Task whose result is `{:ok, SampleResponse.t()} | {:error, Tinkex.Error.t()}`.

5. **Integration with `Tinkex.Future.Combiner` & `await_many`**

   You reference `metrics_reduction.ex` and `future.ex` as required reading, but it might help to explicitly connect the dots:

   * TrainingClient’s background polling Task should:

     * Start a list of polling tasks with `Tinkex.Future.poll/2`.
     * Use `Tinkex.Future.await_many/2` to collect them.
     * Pass the resulting list of `ForwardBackwardOutput` results into `Tinkex.Future.Combiner.combine_forward_backward_results/1`.

   That makes it clear you’re reusing the Phase 3C machinery rather than rolling a second combiner in TrainingClient.

---

## Summary

* **4A**: Very solid; just make sure it says “extend Application” instead of “replace stub”, and mention the interplay between app startup and ETS tables in tests.
* **4B**: Conceptually aligned with the docs, but should:

  * Reuse `Tinkex.API.Session` and its `"/api/v1/heartbeat"` path.
  * Clarify who starts `SessionManager` (4A vs 4B).
  * Tighten heartbeat error semantics using your existing `Tinkex.Error` categories.
* **4C**: Matches the high-level design from the port docs well, but:

  * Needs to reconcile Training API arity/semantics with the current repo (future-returning vs metrics-returning).
  * Needs to fix the sampling API function name/arity (`sample_async/2` vs `asample/3`).
  * Should pin down exact signatures and result types for TrainingClient/SamplingClient APIs.

Once those are addressed, the Phase 4 prompts will be as coherent and “implementation-safe” as the Phase 3 set you just refined.
