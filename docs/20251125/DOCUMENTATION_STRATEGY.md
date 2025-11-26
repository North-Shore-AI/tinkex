# Documentation Strategy for TinKex

This document outlines the practical approach for implementing documentation in TinKex to achieve parity with the Python Tinker SDK.

## Executive Summary

**Approach:** Use ExDoc exclusively with comprehensive @moduledoc/@doc strings.

**Why Not Custom Generator:** The Python SDK uses `generate_docs.py` with `pydoc-markdown`. Elixir's ExDoc provides equivalent or better functionality out-of-the-box:
- Automatic module navigation
- Cross-reference support
- Hex.pm integration
- IDE doc preview

## Python Documentation Infrastructure

### What Python Has

```
docs/
├── README.md                 # Generation instructions
├── api/
│   ├── _meta.json           # Nextra navigation
│   ├── apifuture.md         # Generated: APIFuture
│   ├── exceptions.md        # Generated: Exceptions
│   ├── restclient.md        # Generated: RestClient
│   ├── samplingclient.md    # Generated: SamplingClient
│   ├── serviceclient.md     # Generated: ServiceClient
│   ├── trainingclient.md    # Generated: TrainingClient
│   └── types.md             # Generated: All types
scripts/
└── generate_docs.py         # Custom generator (231 lines)
pydoc-markdown.yml           # Generator config
```

### How It Works

1. `generate_docs.py` uses `pydoc-markdown` to extract docstrings
2. Generates markdown per-module
3. Creates `_meta.json` for Nextra navigation
4. Generated files are checked into repo

## TinKex Equivalent Approach

### Current ExDoc Configuration

```elixir
# mix.exs
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
      # ... guides
    ],
    groups_for_extras: [
      Guides: ~r/docs\/guides\/.*/
    ]
  ]
end
```

### Enhanced ExDoc Configuration

```elixir
# mix.exs
defp docs do
  [
    main: "overview",
    source_ref: "v#{@version}",
    source_url: @source_url,
    homepage_url: @docs_url,
    assets: %{"assets" => "assets"},
    logo: "assets/logo.png",  # If available

    # Main pages
    extras: [
      {"README.md", [filename: "overview", title: "Overview"]},
      {"CHANGELOG.md", [filename: "changelog", title: "Changelog"]},
      {"LICENSE", [filename: "license", title: "License"]},
      {"examples/README.md", [filename: "examples", title: "Examples"]},
      "docs/guides/getting_started.md",
      "docs/guides/api_reference.md",
      "docs/guides/training_loop.md",
      "docs/guides/tokenization.md",
      "docs/guides/troubleshooting.md"
    ],

    # Group guides
    groups_for_extras: [
      "Getting Started": [
        "docs/guides/getting_started.md",
        "docs/guides/api_reference.md"
      ],
      Workflows: [
        "docs/guides/training_loop.md",
        "docs/guides/tokenization.md"
      ],
      Support: [
        "docs/guides/troubleshooting.md"
      ]
    ],

    # Group modules (matches Python navigation)
    groups_for_modules: [
      "Public API": [
        Tinkex,
        Tinkex.API.Service,
        Tinkex.API.Training,
        Tinkex.API.Sampling,
        Tinkex.API.Rest
      ],
      Futures: [
        Tinkex.Future,
        Tinkex.API.Futures
      ],
      Types: ~r/Tinkex\.Types\..*/,
      Errors: [
        Tinkex.Error
      ],
      Internal: [
        Tinkex.API.API,
        Tinkex.HTTP,
        Tinkex.QueueStateObserver
      ]
    ],

    # Nest types under common prefix
    nest_modules_by_prefix: [
      Tinkex.Types
    ]
  ]
end
```

## Module-to-Python Mapping

| Python Doc Page | Elixir Module | ExDoc Group |
|-----------------|---------------|-------------|
| `serviceclient.md` | `Tinkex.API.Service` | Public API |
| `trainingclient.md` | `Tinkex.API.Training` | Public API |
| `samplingclient.md` | `Tinkex.API.Sampling` | Public API |
| `restclient.md` | `Tinkex.API.Rest` | Public API |
| `apifuture.md` | `Tinkex.Future` | Futures |
| `types.md` | `Tinkex.Types.*` | Types |
| `exceptions.md` | `Tinkex.Error` | Errors |

## Documentation Templates

### Main Module (@moduledoc)

```elixir
defmodule Tinkex.API.Service do
  @moduledoc """
  The ServiceClient is the main entry point for the Tinkex API.

  This module provides methods to:
  - Query server capabilities and health status
  - Create `Tinkex.API.Training` clients for model training workflows
  - Create `Tinkex.API.Sampling` clients for text generation and inference
  - Create `Tinkex.API.Rest` clients for REST API operations

  ## Quick Start

      {:ok, service} = Tinkex.API.Service.create()

      # Create a training client
      {:ok, training} = Service.create_lora_training_client(service,
        base_model: "Qwen/Qwen3-8B"
      )

      # Create a sampling client
      {:ok, sampling} = Service.create_sampling_client(service,
        base_model: "Qwen/Qwen3-8B"
      )

      # Create a REST client
      {:ok, rest} = Service.create_rest_client(service)

  ## Client Initialization Time

  - `create/0` - Near-instant
  - `create_lora_training_client/2` - Takes a moment (model initialization)
  - `create_sampling_client/2` - Near-instant
  - `create_rest_client/1` - Near-instant

  ## See Also

  - `Tinkex.API.Training` - Training operations
  - `Tinkex.API.Sampling` - Inference operations
  - `Tinkex.API.Rest` - REST API queries
  """
end
```

### Function (@doc)

```elixir
@doc """
Create a TrainingClient for LoRA fine-tuning.

## Parameters

- `service` - The service client
- `opts` - Configuration options:
  - `:base_model` (required) - Name of the base model (e.g., "Qwen/Qwen2.5-7B")
  - `:rank` - LoRA rank (default: 32)
  - `:seed` - Random seed (default: random)
  - `:train_mlp` - Train MLP layers (default: true)
  - `:train_attn` - Train attention layers (default: true)
  - `:train_unembed` - Train unembedding layers (default: true)
  - `:user_metadata` - Optional user metadata map

## Returns

- `{:ok, %Training{}}` - On success
- `{:error, reason}` - On failure

## Examples

    iex> {:ok, training} = Service.create_lora_training_client(service,
    ...>   base_model: "Qwen/Qwen2.5-7B",
    ...>   rank: 32
    ...> )

    iex> {:ok, training} = Service.create_lora_training_client(service,
    ...>   base_model: "Qwen/Qwen2.5-7B",
    ...>   train_mlp: true,
    ...>   train_attn: true,
    ...>   train_unembed: false,
    ...>   user_metadata: %{"experiment" => "lora-test"}
    ...> )
"""
@spec create_lora_training_client(t(), keyword()) :: {:ok, Training.t()} | {:error, term()}
def create_lora_training_client(service, opts) do
  # ...
end
```

### Type Module (@moduledoc)

```elixir
defmodule Tinkex.Types.WeightsInfoResponse do
  @moduledoc """
  Minimal information for loading public checkpoints.

  Mirrors Python `tinker.types.WeightsInfoResponse`.

  ## Fields

  | Field | Type | Description |
  |-------|------|-------------|
  | `base_model` | `String.t()` | The base model name |
  | `is_lora` | `boolean()` | Whether checkpoint uses LoRA |
  | `lora_rank` | `non_neg_integer() \\| nil` | LoRA rank if applicable |

  ## Wire Format

  ```json
  {
    "base_model": "Qwen/Qwen2.5-7B",
    "is_lora": true,
    "lora_rank": 32
  }
  ```

  ## Examples

      # Parse from JSON
      iex> json = %{"base_model" => "Qwen", "is_lora" => true, "lora_rank" => 32}
      iex> WeightsInfoResponse.from_json(json)
      %WeightsInfoResponse{base_model: "Qwen", is_lora: true, lora_rank: 32}

      # Encode to JSON
      iex> resp = %WeightsInfoResponse{base_model: "Qwen", is_lora: false}
      iex> Jason.encode!(resp)
      ~s({"base_model":"Qwen","is_lora":false})
  """
end
```

## Verification Process

### 1. Build Documentation

```bash
mix docs
```

### 2. Check for Warnings

```bash
mix docs 2>&1 | grep -i warning
```

### 3. Open and Review

```bash
open doc/index.html  # macOS
xdg-open doc/index.html  # Linux
```

### 4. CI Integration

```yaml
# .github/workflows/ci.yml
- name: Generate docs
  run: mix docs

- name: Check for doc warnings
  run: |
    output=$(mix docs 2>&1)
    if echo "$output" | grep -i "warning"; then
      echo "Documentation warnings found!"
      exit 1
    fi
```

## Migration Checklist

### High Priority (P0)
- [ ] Update `mix.exs` with enhanced `docs()` config
- [ ] Add @moduledoc to all public modules
- [ ] Add @doc to all public functions
- [ ] Verify ExDoc output matches Python doc structure

### Medium Priority (P1)
- [ ] Add examples to all @doc strings
- [ ] Add cross-references between related modules
- [ ] Update guides to reference new types/methods

### Low Priority (P2)
- [ ] Add logo to docs
- [ ] Create additional guide pages if needed
- [ ] Consider custom ExDoc themes

## Comparison: Python vs ExDoc

| Feature | Python (pydoc-markdown) | Elixir (ExDoc) |
|---------|------------------------|----------------|
| Navigation | Manual `_meta.json` | Automatic |
| Cross-refs | Manual | Automatic via backticks |
| Versioning | Manual | Via `source_ref` |
| Hex.pm | N/A | Built-in |
| IDE Preview | Limited | Full support |
| Source Links | Config | Automatic |
| Search | Via Nextra | Built-in |
| Typespecs | Via typing | Native @spec |

## Conclusion

ExDoc provides everything needed to match Python documentation quality:
1. **No custom scripts** - ExDoc handles generation
2. **Better navigation** - Automatic module grouping
3. **Better types** - Native @spec integration
4. **Better DX** - IDE preview, Hex.pm integration

Focus effort on **comprehensive @moduledoc and @doc strings**, not tooling.
