These are in very solid shape now. At this point it’s mostly about tiny UX details and cross-prompt consistency rather than any big design problems.

I’ll go through 7A–7E and point out the last few things you might want to tighten.

---

## Phase 7A – CLI Scaffold & Command Routing

### What’s working well

* `main/1` vs `run/1` separation is spelled out:

  * `main/1` calls `System.halt/1`.
  * `run/1` (or similar) returns `{:ok, _} | {:error, _}` for testability.
* You’ve defined *how* help should work:

  * `tinkex --help` → global usage + commands.
  * `tinkex <cmd> --help` → command-specific help.
* You explicitly forbid `Mix.*` at runtime and call out escript config in `mix.exs`.

### Minor suggestions

1. **`--version` vs `tinkex version`**

   7A says:

   > Provide `--help` and `--version` with the global vs subcommand behavior described above.

   And 7D later defines `tinkex version` as a subcommand. That’s fine, but you might want to state explicitly here that:

   * `tinkex --version` is an alias for `tinkex version`.

   That way you don’t end up with two separate implementations or behaviour drift.

2. **Testing shape**

   You already say:

   > Prefer a thin `main/1` wrapper … and a `run/1` … so tests can capture stdout/stderr without halting the VM.

   That’s perfect. For future you, it might help to mention a pattern like:

   * `run(argv) :: {:ok, code} | {:error, code}` and have tests assert on both the tuple and captured IO.

Nothing major; 7A reads as an implementable spec.

---

## Phase 7B – CLI Checkpoint Command

### What’s working well

* Flow aligns with your SDK:

  1. Parse CLI options → `Tinkex.Config.new/1`.
  2. `Tinkex.ServiceClient.start_link/1`.
  3. Create TrainingClient.
  4. `save_weights_for_sampler/2` and await its Task.
  5. Write output/metadata.

* You explicitly call out:

  * “Await TrainingClient operations before exiting.”
  * No direct `Application.get_env` in CLI; go through `Tinkex.Config`.

### Minor suggestions

1. **Exit codes + mapping from `run/1`**

   7A sets up `main/1` to map `{:ok, _}`/`{:error, _}` to `0`/`1`. In 7B, you say:

   > CLI must exit with status 0 on success, non-zero on failure.

   It might be worth reminding implementers to:

   * Keep that mapping consistent in `run/1` → `{:ok, _}` | `{:error, _}` and *not* sprinkle `System.halt/1` inside the checkpoint code.

2. **Specific error mapping**

   You tell the CLI to:

   > Handle errors with friendly messages (user vs server).

   Since `Tinkex.Error` already has `user_error?/1` and `retryable?/1`, this is a nice place to say:

   > Use `Tinkex.Error.user_error?/1` to decide whether to print “fix your inputs” vs “server/transient error, try again.”

   That will keep error messaging consistent with the rest of your library.

3. **What “output” actually is**

   You’ve removed the confusing “downloads checkpoints” phrasing, which is good. You might give a tiny hint about what gets written:

   * Is it just the JSON response as-is?
   * Or a small metadata JSON (model_id, path, timestamp)?

   Not required for implementation, but good to lock down so two people don’t invent different formats.

---

## Phase 7C – CLI Run Command (Sampling)

### What’s working well

* Behaviour is clear and correctly tied into your APIs:

  * `ModelInput.from_text/2` (tuple return).
  * `SamplingClient.sample/4` → Task → `Tinkex.Future.await/2` or `Task.await/2`.
* Options list is comprehensive and you called out the `--prompt` vs `--prompt-file` policy explicitly (“pick a consistent policy”).
* You explicitly treat tokenizer failures as **user errors**, which matches your type-level design.

### Suggestions

1. **Prompt/Prompt-file resolution policy**

   Right now you leave it as:

   > either prefer `--prompt` with a warning or treat as an error—pick a consistent policy.

   For a spec, you may want to choose one to avoid divergence. E.g.:

   * “If both are given, treat it as an error and exit non-zero with a clear message.”
     (This is easier to reason about and test.)

   Or:

   * “If both are given, prefer `--prompt` and log a warning.”

   Just nail one down.

2. **Exit codes again**

   7C doesn’t explicitly mention exit codes, but 7A/7B already establish the pattern. You might still add a one-liner:

   > Ensure `run/1` returns `{:ok, _} | {:error, _}` so `main/1` can map to appropriate exit codes as in Phase 7A.

3. **Output format spec**

   You say:

   > Support output to stdout or file (JSON).

   You might want to define:

   * Whether “plain” mode prints just the text or includes metadata (logprobs, stop_reason).
   * Whether JSON mode outputs exactly the `SampleResponse` shape or a simplified schema.

   It’s easy to over-spec here, but a short line like:

   > In JSON mode, output the `SampleResponse` as a JSON-encoded map; in plain mode, print just the generated text sequences.

   would be enough.

---

## Phase 7D – CLI Version & Packaging

### What’s working well

* Clear behaviour:

  * Text and JSON modes.
  * Git commit where available, omitted or `null` otherwise.
* You’re explicit about not using Mix at runtime and using `Application.spec/2` for version.
* QA & packaging bits:

  * `mix escript.build`.
  * QA script/Makefile target.

### Small tweaks

1. **Deps flag: implement now or explicitly defer**

   You give two choices:

   > Optionally show dependency versions (`--deps`); define the shape (…) or explicitly defer the feature.

   For an agent, that’s a bit open. If you don’t plan to implement it now, I’d *explicitly* say in the prompt:

   * “For this phase, do **not** implement `--deps`—just reserve the flag for a future version.”

   or:

   * “Implement `--deps` as: …” and give a concrete format.

2. **Version retrieval details**

   `Application.spec(:tinkex, :vsn)` returns a charlist. It’s obvious to Elixir devs to wrap with `to_string/1`, but a small note like:

   > Remember to convert the `:vsn` charlist to string before printing/JSON-encoding.

   would prevent someone from accidentally printing `'0.1.0'`.

---

## Phase 7E – Documentation Suite

### What’s working well

* The deliverables map cleanly to what you’ve built:

  * ExDoc configuration.
  * Guides (getting started, API overview, troubleshooting).
  * README updates.
  * Parity note with Python.
* You now explicitly distinguish public API docs vs internal helpers (`@doc false`), which is good.

### Minor suggestions

1. **Guide–README overlap**

   You require both:

   * README CLI usage summary.
   * Guides with detailed flows.

   That’s perfect; maybe just remind yourself to avoid duplicating *too much* text between README and guides—link from README into guides rather than duplicating big sections.

2. **Parity snippet expectation**

   You already say “emphasize checking for similar outputs/logprobs rather than bit-identical text.” That’s a good guardrail; you may want to also encourage:

   * Using the same seed if the API supports it, to control randomness in comparison tests.

   Not required, but helpful for users.

---

## Overall

These Phase 7 prompts are now:

* Internally consistent with each other.
* Consistent with all the earlier phases (config threading, error semantics, Task-based APIs, no Mix at runtime).
* Specific enough that an implementer doesn’t need to guess about exit codes, help routing, or how to hook into the SDK.

The remaining suggestions are mostly about picking a firm policy where you’ve left a choice (e.g. how to handle both `--prompt` and `--prompt-file`, whether to implement `--deps` now or later) and giving yourself tiny hints about details like JSON format and version charlists.

From a spec/agent perspective, these are ready to drive implementation.
