# ADR-001: Documentation Strategy for TinKex

**Status:** Proposed
**Date:** 2025-11-25
**Decision Makers:** TBD
**Technical Story:** Porting Python Tinker SDK documentation infrastructure to Elixir

## Context

The Python Tinker SDK has implemented a custom documentation generation system using:
- `pydoc-markdown` for generating markdown from Python docstrings
- `scripts/generate_docs.py` (231 lines) for orchestrating doc generation
- `docs/api/_meta.json` for Nextra navigation metadata
- Generated markdown files checked into the repository

TinKex needs to decide how to handle documentation to maintain parity with the Python SDK while following Elixir conventions.

## Decision Drivers

1. **Parity with Python SDK** - Documentation should cover the same content
2. **Elixir Conventions** - Should follow Elixir ecosystem standards
3. **Maintainability** - Documentation should be easy to update
4. **Hex.pm Compatibility** - Library published to Hex should have good docs
5. **Custom Site Support** - May need to publish to a custom documentation site
6. **CI Integration** - Should be verifiable in CI

## Considered Options

### Option 1: ExDoc Only (Recommended)

Use ExDoc exclusively, relying on comprehensive `@moduledoc` and `@doc` strings.

**Pros:**
- Standard Elixir tooling
- Automatic Hex.pm integration
- Built-in cross-referencing
- Automatic API navigation
- No custom scripts to maintain
- IDE support for doc preview

**Cons:**
- Different output format than Python
- No custom markdown artifacts in repo
- Less control over navigation structure

### Option 2: ExDoc + Custom Markdown Export

Use ExDoc but also generate markdown files for custom site integration.

**Pros:**
- Best of both worlds
- Can publish to Hex and custom site
- Markdown artifacts for review

**Cons:**
- Additional complexity
- Two places to update docs
- Risk of drift between sources

### Option 3: Custom Generator (Like Python)

Build an Elixir equivalent of `generate_docs.py`.

**Pros:**
- Exact parity with Python output
- Full control over format
- Can generate `_meta.json` equivalent

**Cons:**
- Significant development effort
- Non-standard approach
- Must maintain custom tooling
- Loses ExDoc benefits

## Decision

**Option 1: ExDoc Only** is recommended.

### Rationale

1. **Elixir Ecosystem Standards**: ExDoc is the de-facto standard for Elixir documentation. Fighting this creates maintenance burden.

2. **Hex.pm Integration**: TinKex is published to Hex.pm. ExDoc provides seamless integration.

3. **Automatic Benefits**: ExDoc automatically provides:
   - Module grouping
   - Cross-references (`t:Tinkex.Types.ModelInput.t/0`)
   - Search functionality
   - Source code links
   - Version support

4. **Documentation as Code**: `@moduledoc` and `@doc` strings are verified by the compiler, ensuring they stay in sync with code.

5. **Lower Maintenance**: No custom scripts to maintain, debug, or update.

### Implementation Details

#### 1. Enhance mix.exs docs() Configuration

```elixir
defp docs do
  [
    main: "overview",
    source_ref: "v#{@version}",
    source_url: @source_url,
    homepage_url: @docs_url,
    assets: %{"assets" => "assets"},
    extras: [
      {"README.md", [filename: "overview", title: "Overview"]},
      {"CHANGELOG.md", [filename: "changelog", title: "Changelog"]},
      {"LICENSE", [filename: "license", title: "License"]},
      {"examples/README.md", [filename: "examples", title: "Examples"]},
      "docs/guides/getting_started.md",
      "docs/guides/api_reference.md",
      "docs/guides/troubleshooting.md",
      "docs/guides/training_loop.md",
      "docs/guides/tokenization.md"
    ],
    groups_for_extras: [
      Guides: ~r/docs\/guides\/.*/
    ],
    groups_for_modules: [
      "Public API": [
        Tinkex,
        Tinkex.API.Service,
        Tinkex.API.Training,
        Tinkex.API.Sampling,
        Tinkex.API.Rest
      ],
      Types: ~r/Tinkex\.Types\..*/,
      Futures: [
        Tinkex.Future,
        Tinkex.API.Futures
      ],
      Internal: ~r/Tinkex\.API\..*/
    ],
    nest_modules_by_prefix: [
      Tinkex.Types
    ]
  ]
end
```

#### 2. Documentation Quality Standards

All public modules must have:
- `@moduledoc` with overview, usage examples, and field descriptions
- `@doc` on all public functions with parameters, returns, and examples
- `@spec` typespecs for all public functions

#### 3. CI Verification

Add to CI pipeline:
```yaml
- name: Check docs
  run: |
    mix docs
    # Optionally check for doc warnings
    mix docs 2>&1 | grep -i "warning" && exit 1 || true
```

#### 4. Future Custom Site Support

If a custom documentation site is needed in the future:
1. Create a mix task that extracts doc content from compiled modules
2. Generate JSON/Markdown as needed
3. Keep ExDoc as the source of truth

## Consequences

### Positive
- Standard tooling, lower maintenance
- Hex.pm ready out of the box
- IDE integration for doc preview
- Compile-time verification of doc strings

### Negative
- Different doc structure than Python SDK
- Less control over generated HTML/CSS
- Cannot check generated markdown into repo

### Neutral
- Documentation approach differs from Python (acceptable for Elixir port)
- Need to translate Python doc format to Elixir conventions

## Links

- [ExDoc Documentation](https://hexdocs.pm/ex_doc)
- [Python pydoc-markdown](https://pydoc-markdown.readthedocs.io/)
- [Hex.pm Publishing Guide](https://hex.pm/docs/publish)
