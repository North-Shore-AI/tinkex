Alright, CLI + docs phase — this is the “make it real for users” layer. These prompts are already quite cohesive with everything you’ve done so far; the issues now are mostly around small UX/details and making sure they don’t accidentally undercut the runtime design.

I’ll go one by one.

---

## Phase 7A – CLI Scaffold & Command Routing

### What’s strong

* Clear separation of concerns:

  * `Tinkex.CLI.main/1` as the entry point.
  * Subcommands: `checkpoint`, `run`, `version`.
* You call out all the right pieces:

  * escript config (`escript: [main_module: Tinkex.CLI]`).
  * Option parsing via `OptionParser` or a library.
  * Basic tests for parsing and `--help`.
* You explicitly forbid `Mix.*` at runtime, which is critical for escript.

### Things to tighten

1. **Exit codes & System.halt**

   7A’s constraints mention “independent of Mix”, but not how the CLI should exit. Later prompts mention non-zero exit on failure (7B), but 7A doesn’t set that expectation.

   I’d add in 7A:

   > `main/1` must call `System.halt/1` with 0 on success and non-zero for any error. The scaffold can simply map `{:ok, _}` → `0` and `{:error, _}` → `1` for now.

   That gives a clear contract to build upon in 7B/7C/7D.

2. **Help routing for subcommands**

   You say:

   > Each command should have help text accessible via `--help`.

   You might want to be explicit about:

   * How `tinkex --help` vs `tinkex checkpoint --help` behave, e.g.:

     * `tinkex --help` → global usage + list of commands.
     * `tinkex checkpoint --help` → command-specific help.

   It’s obvious to humans, but small clarifications like this prevent wildly different implementations.

3. **Tests and IO vs return values**

   Right now tests are described as “cover parsing + help output.” It might help to note that tests should *capture* stdout/stderr and not depend on actual `System.halt/1`:

   > For tests, call `Tinkex.CLI.main/1` in a wrapper that doesn’t actually halt the VM (e.g., factor core logic into a `run/1` function returning `{:ok, _} | {:error, _}` and keep `main/1` as a thin wrapper that calls `System.halt/1`).

   That pattern will make tests much easier to write and will be reused in 7B/7C/7D.

---

## Phase 7B – CLI Checkpoint Command

### What’s working well

* The flow maps nicely onto your SDK:

  1. Parse CLI opts → build `Tinkex.Config`.
  2. Start `Tinkex.ServiceClient`.
  3. Create TrainingClient (base model + LoRA options).
  4. Call `save_weights_for_sampler/2` (or equivalent).
  5. Write checkpoint metadata/output.

* The supported flags are sensible and match your type system:

  * `--base-model`, `--model-path`, `--rank`, `--seed`, `--train-mlp/attn/unembed`, `--output`, `--api-key`, `--base-url`, `--timeout`.

* You explicitly require:

  * Non-zero exit on failure.
  * No network in tests (mock via Mox/stubs).

### Subtle issues / clarifications

1. **Config defaults vs CLI**

   You say:

   > Avoid global env lookups; use CLI options + defaults from `Tinkex.Config`.

   That’s good, but a little ambiguous. The actual intended behaviour is:

   * CLI → build `%Tinkex.Config{}` via `Tinkex.Config.new(opts)`.
   * `Tinkex.Config.new/1` is allowed to use `Application.get_env` / `System.get_env` for API key / base URL defaults.

   You might explicitly say:

   > CLI code should not call `Application.get_env/3` directly. Instead pass CLI options to `Tinkex.Config.new/1` and let that module apply defaults (including env-based values).

2. **Blocking / awaiting the command’s Tasks**

   The TrainingClient API returns Tasks (per earlier phases), so the CLI needs to:

   * Call `forward_backward/4` / `optim_step/2` / `save_weights_for_sampler/2`.
   * Await those tasks with `Tinkex.Future.await/2` or `Task.await/2` before exiting.

   7B currently just says “Run `save_weights_for_sampler/2` or equivalent.” You could be explicit:

   > The command must synchronously await any `Task.t` returned by TrainingClient (using `Tinkex.Future.await/2` or `Task.await/2`) and exit only after the async operations complete.

3. **Where “download checkpoints” fits**

   The intro says “optionally downloads checkpoints”, but the Scope only mentions:

   > Write checkpoint metadata/output to specified path.

   If you don’t actually plan to *download* a binary from the remote API (just maybe a path or metadata), I’d either:

   * Drop “downloads checkpoints” from the target line, or
   * Specify what “download” would mean (e.g., `save_weights` returns a URL, then CLI does an HTTP GET).

   Right now it suggests bigger functionality than the spec actually covers.

---

## Phase 7C – CLI Run Command (Sampling)

### Good points

* Behaviour is mapped clearly:

  1. Parse model + prompt + sampling params.
  2. Create ServiceClient + SamplingClient.
  3. Encode prompt via `ModelInput.from_text/2` (or from tokens file).
  4. Call `SamplingClient.sample/4`, await, and print result.
* Options include all the important sampling knobs:

  * `--max-tokens`, `--temperature`, `--top-k`, `--top-p`, `--num-samples`.
  * `--prompt`, `--prompt-file`, `--base-model` / `--model-path`, etc.
* You emphasise error semantics:

  * Distinguish user vs server errors.
  * Helpful message if tokenizer not available.

### Things to refine

1. **Task awaiting + progress**

   You say:

   > Keep CLI responsive: show waiting/progress text while awaiting Task.

   Good requirement, but be explicit how you expect it:

   * e.g. print “Waiting for sampling result…” and then block on `Task.await/2`.
   * Or implement a small “spinner” that periodically prints dots (but that can complicate tests).

   For tests, you probably want something simpler like:

   > For now, a single “Starting sampling…” and “Done.” line is enough. Avoid spinners or long-running loops that complicate tests.

2. **Tokenizer error handling**

   You say:

   > Show helpful message if tokenizer not available.

   Given that `ModelInput.from_text/2` uses the `{:ok, value} | {:error, reason}` contract, the CLI should:

   * Pattern match on `{:error, %Tinkex.Error{type: :validation, message: m}}` (or some explicit type) and log that as a user error.

   It might help to call out:

   > Treat tokenizer failures as user errors and exit with a clear message like “Failed to load tokenizer <id>: …”.

3. **Input source precedence**

   You allow `--prompt` and `--prompt-file`. You might want to define how conflicts are handled:

   * If both are provided, which wins, or is it an error?
   * If neither is provided, CLI should exit with a clear usage error.

   A one-liner in options:

   > If both `--prompt` and `--prompt-file` are given, prefer `--prompt` and warn, or treat it as an error (pick one).

---

## Phase 7D – CLI Version & Packaging

### What’s strong

* You cover both:

  * Behaviour (`tinkex version` with `--json`, optional `--deps`).
  * Packaging (escript and maybe releases).
  * Continuous verification docs.

* You correctly forbid Mix modules at runtime and push toward using:

  * `Application.spec(:tinkex, :vsn)` for version.
  * Guarded `System.cmd("git", ...)` for commit.

### Small issues / clarifications

1. **Git commit behaviour outside a repo**

   You correctly say “guarded so CLI runs even outside repo.” I’d explicitly suggest the behaviour:

   * If `git` or `rev-parse` fails, omit the commit from JSON or show `"commit": null`.

   That makes testing easier and sets expectations for users who install the CLI from Hex/archives.

2. **Where to put QA scripts**

   You mention “Makefile or script snippet.” You might specify:

   * `Makefile` target `qa` that runs all four commands.
   * Or a shell script under `scripts/qa.sh`.

   Just so implementers don’t put this in random places.

3. **`--deps` output shape**

   You allow an optional `--deps` flag. If you intend to implement it, it’s worth specifying:

   * Is it plain text (`dep name - version` per line)?
   * Or JSON list?

   If you don’t actually need this feature now, consider punting it to a later iteration; it’s easy to add but not required for v1.

---

## Phase 7E – Documentation Suite

### Strong parts

* Very good scope: ExDoc config, guides, README, troubleshooting, parity notes.

* You properly anchor docs back to the porting doc:

  * Getting started.
  * Troubleshooting (429, timeouts, NIF, CLI issues).
  * Behavioral parity with Python.

* You call out the need for QA commands in the README and (optionally) CI.

### Minor refinements

1. **Module doc coverage**

   You say:

   > Ensure every public module has `@moduledoc` and functions have `@doc`.

   That’s ideal, but sometimes small internal helpers are `@doc false`. Maybe tweak to:

   > Ensure all public-facing modules and functions (as part of the user API) have `@moduledoc` / `@doc`; internal helpers can be marked `@doc false` as appropriate.

2. **Parity test snippet**

   You mention:

   > Document how to compare Elixir vs Python results (test template snippet).

   It might help to push one step further: explicitly mention:

   * Using the same base model, prompt, and sampling params.
   * Checking that outputs are “similar” (logprobs / tokens) rather than bit-identical.

   This can help head off unrealistic expectations from users reading the docs.

3. **`mix docs` in CI**

   You say:

   > Add `mix docs` to CI or Makefile instructions.

   That’s great, but if `mix docs` needs extra deps (e.g. `ex_doc` only in `:dev`), tests/instructions should mention:

   * It may require dev deps in CI.
   * It shouldn’t be run in production environments.

   Not a huge issue, just something to be aware of.

---

## Overall

Across 7A–7E:

* The CLI prompts are consistent with your runtime design:

  * They respect `Tinkex.Config` threading.
  * They acknowledge Task-based APIs.
  * They avoid `Mix` at runtime.
* The docs prompt is nicely aligned with the broader porting effort and QA story.

The remaining tweaks are small:

* Make exit codes and Task-await patterns explicit in CLI.
* Clarify a few UX edge cases (prompt input precedence; tokenizer errors).
* Tighten expectations around optional features like `--deps`.

From an implementer’s perspective, you’ve reached the point where they can wire the CLI and docs without needing to reverse-engineer your design intent.
