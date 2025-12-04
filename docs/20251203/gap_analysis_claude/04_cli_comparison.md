# CLI Comparison

## Overview

The Elixir CLI has **more features** than Python CLI. Python focuses on asset management while Elixir adds training/inference capabilities.

## Command Matrix

| Command | Python | Elixir | Winner |
|---------|--------|--------|--------|
| `version` | Yes | Yes + `--json`, `--deps` | Elixir |
| `checkpoint list` | Yes | Yes + `--offset` | Elixir |
| `checkpoint info` | Yes | Yes | Parity |
| `checkpoint download` | Yes (with extraction) | Yes (URL only) | Python |
| `checkpoint publish` | Yes | Yes | Parity |
| `checkpoint unpublish` | Yes | Yes | Parity |
| `checkpoint delete` | Yes (single) | Yes (batch) | Elixir |
| `checkpoint save` | **No** | Yes | Elixir |
| `run list` | Yes | Yes + `--offset` | Elixir |
| `run info` | Yes | Yes | Parity |
| `run sample` | **No** | Yes | Elixir |

## Python-Only Features

### 1. Progress Bars (Intentionally Excluded)

**Python Implementation:**
```python
# Uses click.progressbar() for:
# - Checkpoint listing (large result sets)
# - Checkpoint download
# - Archive extraction
```

**Elixir Status:** Not implemented (per requirements)

**Note:** Intentionally excluded from parity scope.

### 2. Automatic Archive Extraction

**Python Implementation:**
```python
# checkpoint.py
def download(tinker_path, output_dir, force):
    url = client.get_checkpoint_archive_url(...)
    with tempfile.NamedTemporaryFile() as f:
        download_with_progress(url, f)
        extract_tar(f, output_dir)
        # Auto-cleanup temp file
```

**Elixir Status:** Returns download URL only

**Implementation Recommendation:**
```elixir
def download_and_extract(tinker_path, output_dir, opts \\ []) do
  with {:ok, url} <- get_archive_url(tinker_path),
       {:ok, tar_path} <- download_file(url),
       :ok <- extract_tar(tar_path, output_dir) do
    File.rm(tar_path)
    {:ok, output_dir}
  end
end
```

## Elixir-Only Features

### 1. Checkpoint Save Command

```bash
tinkex checkpoint save \
  --base-model Qwen/Qwen2.5-7B \
  --output ./checkpoints \
  --rank 32 \
  --train-mlp \
  --train-attn
```

**Creates checkpoints from trained models with LoRA configuration.**

### 2. Run Sample Command

```bash
tinkex run sample \
  --base-model Qwen/Qwen2.5-7B \
  --prompt "Hello, world" \
  --max-tokens 100 \
  --temperature 0.7 \
  --num-samples 3
```

**Generates text from models directly from CLI.**

### 3. Batch Checkpoint Deletion

```bash
tinkex checkpoint delete path1 path2 path3 --yes
```

**Deletes multiple checkpoints in single operation.**

### 4. Extended Pagination

```bash
tinkex checkpoint list --limit 50 --offset 100
tinkex run list --limit 20 --offset 40
```

**Both list commands support offset for pagination.**

## Options Comparison

### Global Options

| Option | Python | Elixir |
|--------|--------|--------|
| `--format` | Global (table/json) | Per-command |
| `--json` | No | Per-command shorthand |
| `--api-key` | In config | Per-command |
| `--base-url` | In config | Per-command |
| `--timeout` | No | Per-command |
| `--http-pool` | No | Per-command |

### Checkpoint Options

| Option | Python | Elixir | Context |
|--------|--------|--------|---------|
| `--run-id` | list | list | Filter |
| `--limit` | list | list | Pagination |
| `--offset` | No | list | Pagination |
| `--yes` | delete | delete | Skip confirm |
| `--force` | download | download | Overwrite |
| `--output` | download | save, download | Output path |
| `--rank` | No | save | LoRA rank |
| `--seed` | No | save | Random seed |
| `--train-mlp` | No | save | LoRA layers |
| `--train-attn` | No | save | LoRA layers |
| `--train-unembed` | No | save | LoRA layers |

### Sampling Options (Elixir Only)

| Option | Default | Description |
|--------|---------|-------------|
| `--prompt` | - | Text prompt |
| `--prompt-file` | - | File with prompt (text or JSON tokens) |
| `--max-tokens` | - | Max generation length |
| `--temperature` | 1.0 | Sampling temperature |
| `--top-k` | -1 | Top-k sampling |
| `--top-p` | 1.0 | Nucleus sampling |
| `--num-samples` | 1 | Number of samples |

## Output Format Comparison

### Python (Rich Tables)
```
┌──────────────────────────────────────┬─────────────────────┐
│ Checkpoint ID                        │ Type                │
├──────────────────────────────────────┼─────────────────────┤
│ ckpt-001                             │ training            │
└──────────────────────────────────────┴─────────────────────┘
```

### Elixir (Tab-Separated)
```
Checkpoint ID	Type
ckpt-001	training
```

**Note:** Elixir output is machine-parseable. Rich formatting excluded per requirements.

## Error Handling

### Python
```python
@handle_api_errors
def command(...):
    # Decorator catches and formats errors
```

### Elixir
```elixir
with {:ok, result} <- operation(),
     ... do
  output(result)
else
  {:error, reason} -> log_error(reason)
end
```

## Architecture

| Aspect | Python | Elixir |
|--------|--------|--------|
| Framework | Click | Custom OptionParser |
| Lazy loading | LazyGroup | N/A (compiled) |
| Output classes | OutputBase ABC | Direct IO |
| Testability | Decorator-based | Dependency injection |

## Recommendations

### To Achieve Full Python Parity:
1. Add archive extraction to `checkpoint download`

### To Maintain Elixir Advantages:
- Keep `checkpoint save` command
- Keep `run sample` command
- Keep batch delete support
- Keep `--offset` pagination

## Files Reference

- Python: `tinker/cli/__main__.py`, `tinker/cli/commands/*.py`
- Elixir: `lib/tinkex/cli.ex`, `lib/tinkex/cli/*.ex`
