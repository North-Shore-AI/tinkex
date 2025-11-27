# Gap #9: REST / CLI Ergonomics and Output Formatting

**Investigation Date:** November 27, 2025
**Status:** Comprehensive Analysis Complete
**Priority:** Medium-High (User Experience Impact)

---

## Executive Summary

The Python SDK (tinker) provides a rich, user-friendly CLI experience with sophisticated output formatting, while the Elixir SDK (tinkex) implements functional CLI coverage but lacks the UX polish that makes the Python CLI exceptional. This gap primarily affects developer ergonomics rather than functionality.

**Key Findings:**
- Python CLI uses `rich` library for beautiful tables with colors and alignment
- Python CLI includes progress bars for long-running operations (downloads, pagination)
- Python CLI has dual output modes: `--format table` (default) and `--format json` for *all* commands
- Elixir CLI outputs plain text; only `run --json` and `version --json` support JSON (management commands are text-only)
- Elixir CLI has no table formatting, no progress bars, no color/styling
- Command parity is ~90% complete (both support checkpoint/run management)

---

## Table of Contents

1. [Python SDK Deep Dive](#1-python-sdk-deep-dive)
2. [Elixir SDK Deep Dive](#2-elixir-sdk-deep-dive)
3. [Granular Differences](#3-granular-differences)
4. [Command Parity Analysis](#4-command-parity-analysis)
5. [TDD Implementation Plan](#5-tdd-implementation-plan)
6. [Recommended Libraries](#6-recommended-libraries)
7. [Implementation Roadmap](#7-implementation-roadmap)

---

## 1. Python SDK Deep Dive

### 1.1 Architecture Overview

**Location:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinker\src\tinker\cli\`

**Key Components:**
```
cli/
├── __main__.py          # Entry point with lazy loading
├── output.py            # OutputBase + formatting utilities
├── context.py           # CLIContext dataclass for state sharing
├── exceptions.py        # TinkerCliError for graceful exits
├── lazy_group.py        # Lazy command loading (fast startup)
├── client.py            # REST client creation helpers
└── commands/
    ├── run.py           # Training run commands
    ├── checkpoint.py    # Checkpoint management commands
    └── version.py       # Version command
```

### 1.2 Output Formatting Architecture

#### OutputBase Abstract Class

**File:** `tinker/cli/output.py`

```python
class OutputBase(ABC):
    """Virtual base class for all command outputs."""

    @abstractmethod
    def to_dict(self) -> Dict[str, Any]:
        """Convert output to dictionary for JSON serialization."""
        pass

    @abstractmethod
    def get_table_columns(self) -> List[str]:
        """Return list of column names for table output."""
        pass

    @abstractmethod
    def get_table_rows(self) -> List[List[str]]:
        """Return list of rows for table output."""
        pass

    def get_title(self) -> str | None:
        """Optional title for the output display."""
        return None

    def print(self, format: str = "table") -> None:
        """Print the output in the specified format."""
        if format == "json":
            self._print_json()
        else:
            self._print_table()
```

**Key Features:**
1. **Dual Output Modes:** Every command output can be rendered as table or JSON
2. **Rich Table Rendering:** Uses `rich.console.Console` and `rich.table.Table`
3. **First Column Styling:** Special cyan highlighting for ID columns
4. **Lazy Imports:** Rich is imported only when needed (fast startup)

#### Table Rendering Implementation

```python
def _print_table(self) -> None:
    """Print output as a rich table."""
    from rich.console import Console
    from rich.table import Table

    console = Console()

    # Create table with optional title
    title = self.get_title()
    table = Table(title=title) if title else Table()

    # Add columns
    columns = self.get_table_columns()
    for col in columns:
        # First column (usually ID) gets special styling
        if col == columns[0]:
            table.add_column(col, style="bright_cyan", no_wrap=True)
        else:
            table.add_column(col)

    # Add rows
    rows = self.get_table_rows()
    for row in rows:
        table.add_row(*row)

    # Print the table
    console.print(table)
```

#### Formatting Utilities

**File:** `tinker/cli/output.py`

```python
def format_size(bytes: int) -> str:
    """Format bytes as human-readable size (e.g., "1.2 GB")."""
    # Returns: "1.2 GB", "345 MB", "12.5 KB", etc.

def format_timestamp(dt: Union[datetime, str, None]) -> str:
    """Format datetime as relative time or absolute date."""
    # Returns: "2 hours ago", "3 days ago", "2024-01-15"
    # Smart: Recent = relative, Old = absolute date

def format_bool(value: bool) -> str:
    """Format boolean for display."""
    # Returns: "Yes" or "No"

def format_optional(value: Any, formatter: Callable[[Any], str] | None = None) -> str:
    """Format an optional value."""
    # Returns: formatted value or "N/A" if None
```

### 1.3 Progress Bar Implementation

**Location:** `tinker/cli/commands/run.py` (lines 206-230)

```python
# If we need to fetch more runs, paginate with a progress bar
if len(all_runs) < target_count:
    with click.progressbar(
        length=target_count,
        label=f"Fetching {'all' if limit == 0 else str(target_count)} training runs",
        show_percent=True,
        show_pos=True,
        show_eta=True,
    ) as bar:
        bar.update(len(all_runs))

        # Fetch remaining runs in batches
        while len(all_runs) < target_count:
            offset = len(all_runs)
            remaining = target_count - len(all_runs)
            next_batch_size = min(batch_size, remaining)

            response = client.list_training_runs(
                limit=next_batch_size, offset=offset
            ).result()
            all_runs.extend(response.training_runs)
            bar.update(len(response.training_runs))

            # Break if we got fewer than requested (reached the end)
            if len(response.training_runs) < next_batch_size:
                break
```

**Features:**
- Percentage completion display
- Position counter (e.g., "152/500")
- ETA (estimated time remaining)
- Label explaining what's being fetched
- Conditional display (only for multi-batch operations)

**Used In:**
1. `tinker run list` - When fetching paginated training runs
2. `tinker checkpoint list` - When fetching paginated checkpoints
3. `tinker checkpoint download` - For archive download progress
4. `tinker checkpoint download` - For archive extraction progress

### 1.4 Command Structure Examples

#### Run List Command

**File:** `tinker/cli/commands/run.py`

```python
class RunListOutput(OutputBase):
    """Output for 'tinker run list' command."""

    def __init__(self, runs: List["TrainingRun"],
                 total_count: int | None = None,
                 shown_count: int | None = None):
        self.runs = runs
        self.total_count = total_count
        self.shown_count = shown_count

    def get_title(self) -> str | None:
        """Return title for table output."""
        count = len(self.runs)
        if count == 0:
            return "No training runs found"

        # Build the base title
        if count == 1:
            title = "1 training run"
        else:
            title = f"{count} training runs"

        # Add information about remaining runs if available
        if self.total_count is not None and self.total_count > self.shown_count:
            remaining = self.total_count - self.shown_count
            if remaining == 1:
                title += f" (1 more not shown, use --limit to see more)"
            else:
                title += f" ({remaining} more not shown, use --limit to see more)"

        return title

    def get_table_columns(self) -> List[str]:
        """Return column headers for table output."""
        return ["Run ID", "Base Model", "Owner", "LoRA", "Last Update", "Status"]

    def get_table_rows(self) -> List[List[str]]:
        """Return rows for table output."""
        rows = []
        for run in self.runs:
            # Format LoRA information
            if run.is_lora and run.lora_rank:
                lora_info = f"Rank {run.lora_rank}"
            elif run.is_lora:
                lora_info = "Yes"
            else:
                lora_info = "No"

            rows.append([
                run.training_run_id,
                run.base_model,
                run.model_owner,
                lora_info,
                format_timestamp(run.last_request_time),
                "Failed" if run.corrupted else "Active",
            ])

        return rows
```

**Example Output (Table Mode):**
```
                        3 training runs (47 more not shown, use --limit to see more)
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━┓
┃ Run ID                               ┃ Base Model          ┃ Owner      ┃ LoRA     ┃ Last Update ┃ Status ┃
┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━┩
│ 0478a1ab-95af-5eae-bd70-d3d3b441c021 │ Qwen/Qwen2.5-0.5B   │ user@ex.ai │ Rank 32  │ 2 hours ago │ Active │
│ 5a3335fe-65fe-5afa-a6b4-d1294887e5bc │ Qwen/Qwen2.5-0.5B   │ user@ex.ai │ Rank 32  │ 3 days ago  │ Active │
│ f620a60b-7b30-5e7e-bc11-da12b0fb0765 │ meta-llama/Llama-3B │ user@ex.ai │ No       │ 1 week ago  │ Failed │
└──────────────────────────────────────┴─────────────────────┴────────────┴──────────┴─────────────┴────────┘
```

**Example Output (JSON Mode):**
```json
{
  "runs": [
    {
      "training_run_id": "0478a1ab-95af-5eae-bd70-d3d3b441c021",
      "base_model": "Qwen/Qwen2.5-0.5B",
      "model_owner": "user@example.ai",
      "is_lora": true,
      "lora_rank": 32,
      "last_request_time": "2025-11-27T10:30:00Z",
      "corrupted": false
    }
  ]
}
```

#### Checkpoint Download Command

**File:** `tinker/cli/commands/checkpoint.py` (lines 564-640)

Shows TWO progress bars:
1. Download progress bar (with file size, percent, ETA)
2. Extraction progress bar (with file count, percent)

```python
# Download with progress bar
if format != "json":
    with click.progressbar(
        length=total_size,
        label="Downloading archive",
        show_percent=True,
        show_pos=True,
        show_eta=True,
    ) as bar:
        with open(archive_path, "wb") as f:
            while True:
                chunk = response.read(8192)
                if not chunk:
                    break
                f.write(chunk)
                bar.update(len(chunk))

# Extract with progress bar
if format != "json":
    with click.progressbar(
        members,
        label="Extracting archive ",
        show_percent=True,
        show_pos=True,
    ) as bar:
        for member in bar:
            tar.extract(member, path=extract_dir)
```

### 1.5 Dependencies

**File:** `tinker/pyproject.toml`

```toml
dependencies = [
    "rich>=13.0.0",      # Tables, colors, styling
    "click>=8.0.0",      # CLI framework with progress bars
    # ... other dependencies
]
```

**Key Libraries:**
- **rich:** Beautiful terminal formatting
  - Tables with borders, colors, alignment
  - Console rendering
  - Syntax highlighting support
- **click:** CLI framework
  - Built-in `click.progressbar()` context manager
  - Option parsing, help generation
  - Command groups and lazy loading support

---

## 2. Elixir SDK Deep Dive

### 2.1 Architecture Overview

**Location:** `\\wsl.localhost\ubuntu-dev\home\home\p\g\North-Shore-AI\tinkex\lib\tinkex\cli.ex`

**Structure:**
- **Single Module:** `Tinkex.CLI` (1,387 lines)
- **Deployment:** escript binary (configured in `mix.exs`)
- **Entry Point:** `main/1` function (calls `run/1` internally)

```elixir
defmodule Tinkex.CLI do
  @moduledoc """
  Command-line interface entrypoint for the Tinkex escript.
  """

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    exit_code = case run(argv) do
      {:ok, _} -> 0
      {:error, _} -> 1
    end
    System.halt(exit_code)
  end

  @spec run([String.t()]) :: {:ok, term()} | {:error, term()}
  def run(argv) do
    case parse(argv) do
      {:help, message} ->
        IO.puts(message)
        {:ok, :help}

      {:error, message} ->
        IO.puts(:stderr, message)
        {:error, :invalid_args}

      {:command, command, options} ->
        dispatch(command, options)
    end
  end
end
```

### 2.2 Current Output Implementation

#### Plain Text Output (Default)

**Checkpoint List Example:**

```elixir
defp checkpoint_list(config, options, deps) do
  limit = Map.get(options, :limit, 20)
  offset = Map.get(options, :offset, 0)

  case deps.rest_api_module.list_user_checkpoints(config, limit, offset) do
    {:ok, %CheckpointsListResponse{} = resp} ->
      Enum.each(resp.checkpoints, fn ckpt ->
        IO.puts("#{ckpt.checkpoint_id}\t#{ckpt.tinker_path}")
      end)

      {:ok, %{command: :checkpoint, action: :list, count: length(resp.checkpoints)}}

    {:error, %Error{} = error} ->
      IO.puts(:stderr, "Checkpoint list failed: #{Error.format(error)}")
      {:error, error}
  end
end
```

**Output:**
```
checkpoint_001    tinker://run-123/weights/001
checkpoint_002    tinker://run-123/weights/002
checkpoint_003    tinker://run-456/weights/001
```

**Issues:**
- Tab-separated columns (not aligned)
- No headers
- No borders
- No colors
- No metadata (total count, pagination info)
- No JSON output mode for list/info/download (text-only)

#### JSON Output Mode

**Version Command Example:**

```elixir
defp dispatch(:version, options) do
  deps = version_deps()
  version = current_version(deps)
  commit = current_commit(deps)
  payload = %{"version" => version, "commit" => commit}

  case Map.get(options, :json, false) do
    true ->
      IO.puts(deps.json_module.encode!(payload))

    false ->
      IO.puts(format_version(version, commit))
  end

  {:ok, %{command: :version, version: version, commit: commit, options: options}}
end
```

**Output (Plain):**
```
tinkex 0.1.11 (a1b2c3d)
```

**Output (JSON):**
```json
{"version":"0.1.11","commit":"a1b2c3d"}
```

*Note:* Only `version --json` and `run --json` support JSON today; checkpoint/run management subcommands currently emit plain text only.

### 2.3 Command Implementation Examples

#### Run List Command

**Implementation:**

```elixir
defp run_list(config, options, deps) do
  limit = Map.get(options, :limit, 20)
  offset = Map.get(options, :offset, 0)

  case deps.rest_api_module.list_training_runs(config, limit, offset) do
    {:ok, %TrainingRunsResponse{} = resp} ->
      Enum.each(resp.training_runs, fn run ->
        IO.puts("#{run.training_run_id}\t#{run.base_model}")
      end)

      {:ok, %{command: :run, action: :list, count: length(resp.training_runs)}}

    {:ok, data} ->
      resp = TrainingRunsResponse.from_map(data)

      Enum.each(resp.training_runs, fn run ->
        IO.puts("#{run.training_run_id}\t#{run.base_model}")
      end)

      {:ok, %{command: :run, action: :list, count: length(resp.training_runs)}}

    {:error, %Error{} = error} ->
      IO.puts(:stderr, "Run list failed: #{Error.format(error)}")
      {:error, error}
  end
end
```

**Output:**
```
0478a1ab-95af-5eae-bd70-d3d3b441c021    Qwen/Qwen2.5-0.5B
5a3335fe-65fe-5afa-a6b4-d1294887e5bc    Qwen/Qwen2.5-0.5B
f620a60b-7b30-5e7e-bc11-da12b0fb0765    meta-llama/Llama-3B
```

**Missing:**
- Column headers
- Owner information
- LoRA status
- Last update timestamp
- Corrupted status
- Total count / pagination info
- Progress bar for pagination
- JSON output flag (`--format json` equivalent)

#### Checkpoint Info Command

**Implementation:**

```elixir
defp checkpoint_info(config, options, deps) do
  path = Map.fetch!(options, :path)

  case deps.rest_api_module.get_weights_info_by_tinker_path(config, path) do
    {:ok, %WeightsInfoResponse{} = info} ->
      IO.puts("Base model: #{info.base_model}")
      IO.puts("LoRA: #{info.is_lora}")
      if info.lora_rank, do: IO.puts("LoRA rank: #{info.lora_rank}")
      {:ok, %{command: :checkpoint, action: :info, path: path}}

    {:error, %Error{} = error} ->
      IO.puts(:stderr, "Checkpoint info failed: #{Error.format(error)}")
      {:error, error}
  end
end
```

**Output:**
```
Base model: Qwen/Qwen2.5-0.5B
LoRA: true
LoRA rank: 32
```

**Missing:**
- Formatted table layout
- Size information
- Creation timestamp
- Public/private status
- JSON output mode
- Tinker path display

### 2.4 Dependencies

**File:** `tinkex/mix.exs`

```elixir
defp deps do
  [
    # Core dependencies
    {:finch, "~> 0.18"},       # HTTP/2 client
    {:jason, "~> 1.4"},        # JSON encoding/decoding
    {:nx, "~> 0.7"},           # Numerical computing
    {:exla, "~> 0.7"},         # GPU/CPU backend
    {:tokenizers, "~> 0.5"},   # Tokenization

    # Development/Testing
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.30", only: :dev, runtime: false},
    {:mox, "~> 1.0", only: :test},
    {:bypass, "~> 2.1", only: :test},
    {:supertester, "~> 0.3.1", only: :test}
  ]
end
```

**Notable:**
- `credo` depends on `bunt` for colored output (already available)
- **NO** table formatting library
- **NO** progress bar library
- **NO** dedicated CLI styling library

### 2.5 Testing Approach

**File:** `tinkex/test/tinkex/cli_test.exs`

```elixir
defmodule Tinkex.CLITest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureIO

  alias Tinkex.CLI

  describe "help output" do
    test "shows global help with --help" do
      output = capture_io(fn ->
        assert {:ok, :help} = CLI.run(["--help"])
      end)

      assert output =~ "Usage:"
      assert output =~ "checkpoint"
      assert output =~ "version"
    end
  end

  describe "routing and parsing" do
    test "supports JSON version output" do
      output = capture_io(fn ->
        assert {:ok, %{command: :version, options: %{json: true}}} =
                 CLI.run(["version", "--json"])
      end)

      assert %{"version" => version} = Jason.decode!(output)
      assert is_binary(version)
    end
  end
end
```

**Testing Strategy:**
- Uses `ExUnit.CaptureIO` to capture stdout/stderr
- Tests command routing and parsing logic
- Validates JSON output structure
- Tests help text content
- Full isolation per test (via Supertester)

---

## 3. Granular Differences

### 3.1 Output Formatting Capabilities

| Feature | Python (tinker) | Elixir (tinkex) | Gap Impact |
|---------|----------------|-----------------|------------|
| **Table Rendering** | ✅ Rich tables with borders | ❌ Tab-separated text | High |
| **Column Alignment** | ✅ Auto-aligned columns | ❌ No alignment | Medium |
| **Color/Styling** | ✅ Cyan IDs, styled headers | ❌ No colors | Medium |
| **Progress Bars** | ✅ For downloads & pagination | ❌ No progress bars | Medium |
| **JSON Output** | ✅ `--format json` (all commands) | ⚠️ Partial (`run --json`, `version --json` only; lists/info/download are text-only) | Medium |
| **Human-Readable Sizes** | ✅ "1.2 GB", "345 MB" | ❌ Raw bytes or N/A | Low |
| **Relative Timestamps** | ✅ "2 hours ago", "3 days ago" | ❌ ISO strings or missing | Low |
| **Pagination Info** | ✅ Shows count + remaining | ❌ No metadata shown | Medium |
| **Table Titles** | ✅ Descriptive titles | ❌ No titles | Low |
| **Boolean Formatting** | ✅ "Yes" / "No" | ✅ "true" / "false" | Low |

### 3.2 CLI Architecture Patterns

| Aspect | Python (tinker) | Elixir (tinkex) | Analysis |
|--------|----------------|-----------------|----------|
| **Structure** | Multiple modules (output.py, commands/*.py) | Single module (cli.ex) | Python: Better separation of concerns |
| **Output Classes** | Abstract `OutputBase` + subclasses | Inline formatting functions | Python: Better extensibility |
| **Lazy Loading** | ✅ LazyGroup for fast startup | ✅ Single escript (already fast) | Both: Optimized startup |
| **Error Handling** | Custom `TinkerCliError` | Pattern matching + `Error` struct | Both: Graceful error handling |
| **Context Passing** | `CLIContext` dataclass | Options map + dependency injection | Both: Clean state management |
| **Testing** | `pytest` with `respx` mocking | `ExUnit` with `Mox` | Both: Comprehensive testing |

### 3.3 User Experience Comparison

**Scenario: List 50 checkpoints out of 500 total**

**Python (tinker):**
```
$ tinker checkpoint list --limit 50

Fetching 50 checkpoints ━━━━━━━━━━━━━━━━━━━━ 100% 50/50 0:00:02

                      50 checkpoints (450 more not shown, use --limit to see more)
┏━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Checkpoint ID  ┃ Type     ┃ Size   ┃ Public ┃ Created        ┃ Path                   ┃
┡━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ckpt_001       │ weights  │ 2.3 GB │ Yes    │ 2 hours ago    │ tinker://run-1/w/001   │
│ ckpt_002       │ weights  │ 2.3 GB │ No     │ 5 hours ago    │ tinker://run-1/w/002   │
│ ...            │ ...      │ ...    │ ...    │ ...            │ ...                    │
└────────────────┴──────────┴────────┴────────┴────────────────┴────────────────────────┘
```

**Elixir (tinkex):**
```
$ tinkex checkpoint list --limit 50
ckpt_001    tinker://run-1/w/001
ckpt_002    tinker://run-1/w/002
ckpt_003    tinker://run-1/w/003
...
```

**UX Gaps:**
1. No progress bar during fetch
2. No table formatting
3. No size, type, public status, creation time
4. No indication of total count or remaining items
5. No column headers
6. No visual alignment

---

## 4. Command Parity Analysis

### 4.1 Command Coverage Matrix

| Command | Python (tinker) | Elixir (tinkex) | Parity Status |
|---------|----------------|-----------------|---------------|
| **Global** |
| `--version` | ✅ | ✅ | ✅ Complete |
| `--help` | ✅ | ✅ | ✅ Complete |
| **Checkpoint Commands** |
| `checkpoint save` | ❌ (N/A) | ✅ | Elixir-only |
| `checkpoint list` | ✅ | ✅ | ✅ Complete (output differs) |
| `checkpoint info <path>` | ✅ | ✅ | ✅ Complete (output differs) |
| `checkpoint publish <path>` | ✅ | ✅ | ✅ Complete |
| `checkpoint unpublish <path>` | ✅ | ✅ | ✅ Complete |
| `checkpoint delete <path>` | ✅ | ✅ | ✅ Complete |
| `checkpoint download <path>` | ✅ | ✅ | ✅ Complete (no progress in Elixir) |
| **Run Commands** |
| `run sample` | ❌ (N/A) | ✅ | Elixir-only |
| `run list` | ✅ | ✅ | ✅ Complete (output differs) |
| `run info <run_id>` | ✅ | ✅ | ✅ Complete (output differs) |
| **Version** |
| `version` | ✅ | ✅ | ✅ Complete |
| `version --json` | ✅ | ✅ | ✅ Complete |

### 4.2 Option Parity Analysis

**Checkpoint List Options:**

| Option | Python | Elixir | Notes |
|--------|--------|--------|-------|
| `--limit <int>` | ✅ (default: 20) | ✅ (default: 20) | ✅ Parity |
| `--offset <int>` | ❌ (uses cursor internally) | ✅ (default: 0) | Elixir has explicit offset |
| `--run-id <id>` | ✅ (filter by run) | ❌ | Python only |
| `--format table/json` | ✅ | ❌ | Python only |
| `--json` | ✅ (`--format json`) | ❌ | Missing in Elixir (text-only) |

**Checkpoint Download Options:**

| Option | Python | Elixir | Notes |
|--------|--------|--------|-------|
| `--output <dir>` | ✅ (parent dir) | ✅ (parent dir) | ✅ Parity |
| `--force` | ✅ (overwrite) | ✅ (overwrite) | ✅ Parity |

**Run List Options:**

| Option | Python | Elixir | Notes |
|--------|--------|--------|-------|
| `--limit <int>` | ✅ (default: 20, 0=all) | ✅ (default: 20) | Similar |
| `--format table/json` | ✅ | ❌ | Python only |
| `--json` | ✅ (`--format json`) | ❌ | Missing in Elixir (text-only) |

### 4.3 Unique Elixir Commands

**Checkpoint Save:**
```bash
tinkex checkpoint --base-model <id> --output <path> [options]
```

Options:
- `--base-model <id>` - Base model identifier (required)
- `--model-path <path>` - Local model path
- `--output <path>` - Path to write checkpoint metadata (required)
- `--rank <int>` - LoRA rank (default: 32)
- `--seed <int>` - Random seed
- `--train-mlp` - Enable MLP training
- `--train-attn` - Enable attention training
- `--train-unembed` - Enable unembedding training

**Run Sample:**
```bash
tinkex run --base-model <id> --prompt <text> [options]
```

Options:
- `--base-model <id>` - Base model identifier (required)
- `--model-path <path>` - Local model path
- `--prompt <text>` - Prompt text
- `--prompt-file <path>` - Path to prompt file (text or JSON tokens)
- `--max-tokens <int>` - Maximum tokens to generate
- `--temperature <float>` - Sampling temperature
- `--top-k <int>` - Top-k sampling parameter
- `--top-p <float>` - Nucleus sampling parameter
- `--num-samples <int>` - Number of samples to return
- `--output <path>` - Write output to file
- `--json` - Output JSON (full response)

These commands interact with the training/sampling service clients, which the Python SDK handles differently (as library functions, not CLI commands).

---

## 5. TDD Implementation Plan

### 5.1 Overview

Implement output formatting enhancements for Elixir CLI using Test-Driven Development approach with the following libraries:

**Recommended Stack:**
- **table_rex** - Table rendering with borders and alignment
- **owl** - Progress bars and spinners
- **IO.ANSI** - Built-in color/styling (already available)

### 5.2 Phase 1: Table Formatting

#### 5.2.1 Create OutputFormatter Module

**File:** `lib/tinkex/cli/output_formatter.ex`

**Tests First:**

```elixir
# test/tinkex/cli/output_formatter_test.exs
defmodule Tinkex.CLI.OutputFormatterTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Tinkex.CLI.OutputFormatter

  describe "render_table/3" do
    test "renders empty table with headers" do
      output = capture_io(fn ->
        OutputFormatter.render_table(
          ["ID", "Name", "Status"],
          [],
          title: "Empty Table"
        )
      end)

      assert output =~ "Empty Table"
      assert output =~ "ID"
      assert output =~ "Name"
      assert output =~ "Status"
      assert output =~ "┃"  # Table border
    end

    test "renders table with data rows" do
      rows = [
        ["001", "checkpoint_1", "Active"],
        ["002", "checkpoint_2", "Failed"]
      ]

      output = capture_io(fn ->
        OutputFormatter.render_table(["ID", "Name", "Status"], rows)
      end)

      assert output =~ "001"
      assert output =~ "checkpoint_1"
      assert output =~ "Active"
      assert output =~ "002"
      assert output =~ "checkpoint_2"
    end

    test "applies color to first column" do
      rows = [["001", "test", "ok"]]

      output = capture_io(fn ->
        OutputFormatter.render_table(["ID", "Name", "Status"], rows)
      end)

      # Check for ANSI color codes around ID
      assert output =~ IO.ANSI.bright() <> IO.ANSI.cyan()
    end

    test "handles wide unicode characters correctly" do
      rows = [["测试", "テスト", "🎉"]]

      output = capture_io(fn ->
        OutputFormatter.render_table(["中文", "日本語", "Emoji"], rows)
      end)

      assert output =~ "测试"
      assert output =~ "テスト"
      assert output =~ "🎉"
    end
  end

  describe "format_size/1" do
    test "formats bytes correctly" do
      assert OutputFormatter.format_size(0) == "0 B"
      assert OutputFormatter.format_size(1023) == "1023 B"
      assert OutputFormatter.format_size(1024) == "1.0 KB"
      assert OutputFormatter.format_size(1_048_576) == "1.0 MB"
      assert OutputFormatter.format_size(1_234_567_890) == "1.1 GB"
    end

    test "handles negative values" do
      assert OutputFormatter.format_size(-100) == "N/A"
    end

    test "handles nil" do
      assert OutputFormatter.format_size(nil) == "N/A"
    end
  end

  describe "format_timestamp/1" do
    test "formats recent times as relative" do
      now = DateTime.utc_now()
      two_hours_ago = DateTime.add(now, -2, :hour)

      assert OutputFormatter.format_timestamp(two_hours_ago) == "2 hours ago"
    end

    test "formats old times as absolute dates" do
      old_date = ~U[2024-01-15 10:30:00Z]
      assert OutputFormatter.format_timestamp(old_date) == "2024-01-15"
    end

    test "handles ISO strings" do
      iso_string = "2025-11-27T10:30:00Z"
      result = OutputFormatter.format_timestamp(iso_string)
      assert result =~ ~r/(hours?|days?|weeks?) ago|^\d{4}-\d{2}-\d{2}$/
    end

    test "handles nil" do
      assert OutputFormatter.format_timestamp(nil) == "N/A"
    end
  end

  describe "format_bool/1" do
    test "formats booleans" do
      assert OutputFormatter.format_bool(true) == "Yes"
      assert OutputFormatter.format_bool(false) == "No"
    end
  end

  describe "to_json/1" do
    test "encodes maps to JSON" do
      data = %{"key" => "value", "number" => 42}
      json = OutputFormatter.to_json(data)

      assert is_binary(json)
      assert Jason.decode!(json) == data
    end

    test "handles structs by converting to maps" do
      defmodule SampleStruct do
        defstruct [:field1, :field2]
      end

      struct = %SampleStruct{field1: "a", field2: "b"}
      json = OutputFormatter.to_json(struct)

      decoded = Jason.decode!(json)
      assert decoded["field1"] == "a"
      assert decoded["field2"] == "b"
    end
  end
end
```

**Implementation:**

```elixir
defmodule Tinkex.CLI.OutputFormatter do
  @moduledoc """
  Output formatting utilities for the Tinkex CLI.

  Provides table rendering, formatting helpers, and JSON output.
  """

  @doc """
  Renders a table with the given columns and rows.

  ## Options

    * `:title` - Optional table title
    * `:highlight_first` - Apply color to first column (default: true)

  ## Examples

      iex> render_table(["ID", "Name"], [["1", "test"]], title: "Results")
      # Prints formatted table with borders
  """
  def render_table(columns, rows, opts \\ []) do
    title = Keyword.get(opts, :title)
    highlight_first = Keyword.get(opts, :highlight_first, true)

    # Apply color to first column if requested
    styled_rows = if highlight_first do
      Enum.map(rows, fn [first | rest] ->
        [colorize_id(first) | rest]
      end)
    else
      rows
    end

    # Build table with TableRex
    table = TableRex.Table.new(styled_rows, columns, title)

    # Render and print
    {:ok, rendered} = TableRex.Table.render(table, horizontal_style: :all)
    IO.puts(rendered)
  end

  @doc """
  Formats bytes as human-readable size.

  ## Examples

      iex> format_size(1024)
      "1.0 KB"

      iex> format_size(1_234_567_890)
      "1.1 GB"
  """
  def format_size(nil), do: "N/A"
  def format_size(bytes) when bytes < 0, do: "N/A"

  def format_size(bytes) do
    units = [
      {1_125_899_906_842_624, "PB"},
      {1_099_511_627_776, "TB"},
      {1_073_741_824, "GB"},
      {1_048_576, "MB"},
      {1024, "KB"}
    ]

    case Enum.find(units, fn {size, _unit} -> bytes >= size end) do
      {size, unit} ->
        value = bytes / size
        "#{Float.round(value, 1)} #{unit}"

      nil when bytes == 0 ->
        "0 B"

      nil ->
        "#{bytes} B"
    end
  end

  @doc """
  Formats datetime as relative time or absolute date.

  ## Examples

      iex> two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)
      iex> format_timestamp(two_hours_ago)
      "2 hours ago"
  """
  def format_timestamp(nil), do: "N/A"

  def format_timestamp(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt, :second)

    cond do
      diff_seconds < 60 ->
        "just now"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes} #{pluralize("minute", minutes)} ago"

      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        "#{hours} #{pluralize("hour", hours)} ago"

      diff_seconds < 604_800 ->
        days = div(diff_seconds, 86400)
        "#{days} #{pluralize("day", days)} ago"

      diff_seconds < 2_592_000 ->
        weeks = div(diff_seconds, 604_800)
        "#{weeks} #{pluralize("week", weeks)} ago"

      true ->
        Calendar.strftime(dt, "%Y-%m-%d")
    end
  end

  def format_timestamp(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> format_timestamp(dt)
      {:error, _} -> iso_string
    end
  end

  def format_timestamp(other), do: to_string(other)

  @doc """
  Formats boolean for display.

  ## Examples

      iex> format_bool(true)
      "Yes"

      iex> format_bool(false)
      "No"
  """
  def format_bool(true), do: "Yes"
  def format_bool(false), do: "No"

  @doc """
  Converts data to JSON string.

  ## Examples

      iex> to_json(%{key: "value"})
      "{\"key\":\"value\"}"
  """
  def to_json(data) do
    data
    |> normalize_for_json()
    |> Jason.encode!(pretty: true)
  end

  # Private helpers

  defp colorize_id(id) do
    IO.ANSI.bright() <> IO.ANSI.cyan() <> to_string(id) <> IO.ANSI.reset()
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"

  defp normalize_for_json(%_struct{} = struct) do
    Map.from_struct(struct)
  end

  defp normalize_for_json(data), do: data
end
```

#### 5.2.2 Create Output Behaviour

**File:** `lib/tinkex/cli/output.ex`

**Tests:**

```elixir
# test/tinkex/cli/output_test.exs
defmodule Tinkex.CLI.OutputTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  defmodule TestOutput do
    @behaviour Tinkex.CLI.Output

    @impl true
    def to_map do
      %{"test" => "data", "count" => 42}
    end

    @impl true
    def to_table do
      {
        ["Column 1", "Column 2"],
        [["Value 1", "Value 2"], ["Value 3", "Value 4"]],
        [title: "Test Table"]
      }
    end
  end

  describe "print/2" do
    test "renders table by default" do
      output = capture_io(fn ->
        Tinkex.CLI.Output.print(TestOutput, :table)
      end)

      assert output =~ "Test Table"
      assert output =~ "Column 1"
      assert output =~ "Value 1"
    end

    test "renders JSON when requested" do
      output = capture_io(fn ->
        Tinkex.CLI.Output.print(TestOutput, :json)
      end)

      data = Jason.decode!(output)
      assert data["test"] == "data"
      assert data["count"] == 42
    end
  end
end
```

**Implementation:**

```elixir
defmodule Tinkex.CLI.Output do
  @moduledoc """
  Behaviour for CLI command outputs.

  Commands should implement this behaviour to support both table and JSON output.
  """

  alias Tinkex.CLI.OutputFormatter

  @doc """
  Convert output to a map for JSON serialization.
  """
  @callback to_map() :: map()

  @doc """
  Convert output to table format: {columns, rows, opts}.

  Returns a tuple of:
    * columns - List of column header strings
    * rows - List of row lists
    * opts - Keyword list of options (e.g., title)
  """
  @callback to_table() :: {[String.t()], [[String.t()]], keyword()}

  @doc """
  Print the output in the specified format.
  """
  def print(output_module, format \\ :table)

  def print(output_module, :table) do
    {columns, rows, opts} = output_module.to_table()
    OutputFormatter.render_table(columns, rows, opts)
  end

  def print(output_module, :json) do
    data = output_module.to_map()
    json = OutputFormatter.to_json(data)
    IO.puts(json)
  end
end
```

#### 5.2.3 Refactor Checkpoint List Command

**Tests:**

```elixir
# test/tinkex/cli/outputs/checkpoint_list_test.exs
defmodule Tinkex.CLI.Outputs.CheckpointListTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Tinkex.CLI.Outputs.CheckpointList
  alias Tinkex.Types.Checkpoint

  describe "to_table/0" do
    test "returns properly formatted table data" do
      checkpoints = [
        %Checkpoint{
          checkpoint_id: "ckpt_001",
          checkpoint_type: "weights",
          size_bytes: 2_500_000_000,
          public: true,
          time: ~U[2025-11-27 10:00:00Z],
          tinker_path: "tinker://run-1/weights/001"
        },
        %Checkpoint{
          checkpoint_id: "ckpt_002",
          checkpoint_type: "sampler",
          size_bytes: 1_500_000_000,
          public: false,
          time: ~U[2025-11-25 15:30:00Z],
          tinker_path: "tinker://run-1/sampler/002"
        }
      ]

      output = CheckpointList.new(checkpoints, total_count: 50, shown_count: 2)
      {columns, rows, opts} = output.to_table()

      assert columns == ["Checkpoint ID", "Type", "Size", "Public", "Created", "Path"]
      assert length(rows) == 2
      assert opts[:title] =~ "2 checkpoints"
      assert opts[:title] =~ "48 more not shown"

      [row1, row2] = rows
      assert row1 == [
        "ckpt_001",
        "weights",
        "2.3 GB",
        "Yes",
        "2 hours ago",  # Assuming test runs around same time
        "tinker://run-1/weights/001"
      ]
    end

    test "handles empty checkpoint list" do
      output = CheckpointList.new([], total_count: 0, shown_count: 0)
      {_columns, rows, opts} = output.to_table()

      assert rows == []
      assert opts[:title] == "No checkpoints found"
    end
  end

  describe "to_map/0" do
    test "returns properly structured JSON data" do
      checkpoints = [
        %Checkpoint{
          checkpoint_id: "ckpt_001",
          tinker_path: "tinker://run-1/weights/001"
        }
      ]

      output = CheckpointList.new(checkpoints)
      map = output.to_map()

      assert map["checkpoints"]
      assert length(map["checkpoints"]) == 1
      assert hd(map["checkpoints"])["checkpoint_id"] == "ckpt_001"
    end
  end
end
```

**Implementation:**

```elixir
defmodule Tinkex.CLI.Outputs.CheckpointList do
  @moduledoc """
  Output for 'tinkex checkpoint list' command.
  """

  @behaviour Tinkex.CLI.Output

  alias Tinkex.CLI.OutputFormatter
  alias Tinkex.Types.Checkpoint

  defstruct [:checkpoints, :total_count, :shown_count, :run_id]

  def new(checkpoints, opts \\ []) do
    %__MODULE__{
      checkpoints: checkpoints,
      total_count: Keyword.get(opts, :total_count),
      shown_count: Keyword.get(opts, :shown_count, length(checkpoints)),
      run_id: Keyword.get(opts, :run_id)
    }
  end

  @impl true
  def to_map(%__MODULE__{} = output) do
    result = %{
      "checkpoints" => Enum.map(output.checkpoints, &Map.from_struct/1)
    }

    if output.run_id do
      Map.put(result, "run_id", output.run_id)
    else
      result
    end
  end

  @impl true
  def to_table(%__MODULE__{} = output) do
    columns = ["Checkpoint ID", "Type", "Size", "Public", "Created", "Path"]

    rows = Enum.map(output.checkpoints, fn ckpt ->
      [
        ckpt.checkpoint_id,
        ckpt.checkpoint_type,
        OutputFormatter.format_size(ckpt.size_bytes),
        OutputFormatter.format_bool(ckpt.public),
        OutputFormatter.format_timestamp(ckpt.time),
        ckpt.tinker_path
      ]
    end)

    title = build_title(output)

    {columns, rows, [title: title]}
  end

  defp build_title(%{checkpoints: []} = output) do
    if output.run_id do
      "No checkpoints found for run #{output.run_id}"
    else
      "No checkpoints found"
    end
  end

  defp build_title(%{checkpoints: ckpts, total_count: total, shown_count: shown} = output) do
    count = length(ckpts)

    base = if output.run_id do
      if count == 1 do
        "1 checkpoint for run #{output.run_id}"
      else
        "#{count} checkpoints for run #{output.run_id}"
      end
    else
      if count == 1 do
        "1 checkpoint"
      else
        "#{count} checkpoints"
      end
    end

    # Add pagination info if applicable
    if total && total > shown do
      remaining = total - shown
      suffix = if remaining == 1 do
        " (1 more not shown, use --limit to see more)"
      else
        " (#{remaining} more not shown, use --limit to see more)"
      end

      base <> suffix
    else
      base
    end
  end
end
```

### 5.3 Phase 2: Progress Bars

#### 5.3.1 Progress Bar Module

**Tests:**

```elixir
# test/tinkex/cli/progress_test.exs
defmodule Tinkex.CLI.ProgressTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Tinkex.CLI.Progress

  describe "progress_bar/3" do
    test "creates and updates progress bar" do
      output = capture_io(fn ->
        Progress.progress_bar(100, "Downloading", fn bar ->
          Progress.update(bar, 50)
          Progress.update(bar, 50)
        end)
      end)

      assert output =~ "Downloading"
      assert output =~ "100%"
    end

    test "shows percentage and position" do
      output = capture_io(fn ->
        Progress.progress_bar(1000, "Processing", fn bar ->
          Enum.each(1..10, fn _ ->
            Progress.update(bar, 100)
            Process.sleep(10)
          end)
        end)
      end)

      assert output =~ "1000/1000"
    end
  end

  describe "spinner/2" do
    test "shows spinner for indeterminate tasks" do
      output = capture_io(fn ->
        Progress.spinner("Loading", fn ->
          Process.sleep(100)
          :ok
        end)
      end)

      assert output =~ "Loading"
    end
  end
end
```

**Implementation:**

```elixir
defmodule Tinkex.CLI.Progress do
  @moduledoc """
  Progress bars and spinners for CLI operations.
  """

  @doc """
  Display a progress bar for a task with known total.

  ## Examples

      Progress.progress_bar(1000, "Downloading", fn bar ->
        Enum.each(chunks, fn chunk ->
          # Process chunk
          Progress.update(bar, byte_size(chunk))
        end)
      end)
  """
  def progress_bar(total, label, opts \\ [], fun) do
    show_percent = Keyword.get(opts, :show_percent, true)
    show_pos = Keyword.get(opts, :show_pos, true)
    show_eta = Keyword.get(opts, :show_eta, true)

    bar = Owl.ProgressBar.new(
      id: :default,
      total: total,
      label: label,
      bar_width_ratio: 0.5,
      timer: show_eta,
      absolute_values: show_pos,
      percent: show_percent
    )

    Owl.LiveScreen.add_block(bar)
    Owl.LiveScreen.await_render()

    result = fun.(bar)

    Owl.LiveScreen.remove_block(bar)

    result
  end

  @doc """
  Update progress bar with increment.
  """
  def update(bar, increment) do
    Owl.ProgressBar.inc(bar, inc: increment)
  end

  @doc """
  Display a spinner for indeterminate tasks.

  ## Examples

      Progress.spinner("Loading model", fn ->
        # Long running task
        load_model()
      end)
  """
  def spinner(label, fun) do
    spinner = Owl.Spinner.new(id: :default, label: label)

    Owl.LiveScreen.add_block(spinner)
    Owl.LiveScreen.await_render()

    result = fun.()

    Owl.LiveScreen.remove_block(spinner)

    result
  end
end
```

#### 5.3.2 Integrate Progress Bars into Commands

**Tests:**

```elixir
# test/tinkex/cli/checkpoint_download_test.exs (additions)
describe "checkpoint download with progress" do
  test "shows progress bar during download" do
    # Mock HTTP client to return chunks
    # ...

    output = capture_io(fn ->
      CLI.run(["checkpoint", "download", "tinker://run-1/w/001"])
    end)

    assert output =~ "Downloading archive"
    assert output =~ "100%"
    assert output =~ "Extracting archive"
  end

  test "no progress bar in JSON mode" do
    output = capture_io(fn ->
      CLI.run(["checkpoint", "download", "tinker://run-1/w/001", "--json"])
    end)

    refute output =~ "Downloading"
    assert Jason.decode!(output)["destination"]
  end
end
```

**Implementation (updated checkpoint_download/3):**

```elixir
defp checkpoint_download(config, options, deps) do
  path = Map.fetch!(options, :path)
  output_dir = Map.get(options, :output)
  force = Map.get(options, :force, false)
  json_mode = Map.get(options, :json, false)

  rest_client = deps.rest_client_module.new("cli", config)

  # Get download URL
  {:ok, url_response} = deps.checkpoint_download_module.get_archive_url(rest_client, path)

  # Download with progress bar
  archive_path = download_with_progress(url_response.url, json_mode)

  # Extract with progress bar
  destination = extract_with_progress(archive_path, output_dir, force, json_mode)

  unless json_mode do
    IO.puts("Downloaded to #{destination}")
  else
    result = %{
      command: "checkpoint",
      action: "download",
      path: path,
      destination: destination
    }
    IO.puts(Jason.encode!(result))
  end

  {:ok, %{destination: destination}}
end

defp download_with_progress(url, json_mode) do
  # Get file size from HEAD request
  {:ok, size} = get_content_length(url)

  # Create temp file
  tmp_path = Path.join(System.tmp_dir!(), "checkpoint_#{:rand.uniform(10000)}.tar")

  if json_mode do
    # Silent download
    download_file(url, tmp_path, nil)
  else
    # Download with progress bar
    Progress.progress_bar(size, "Downloading archive", fn bar ->
      download_file(url, tmp_path, fn chunk_size ->
        Progress.update(bar, chunk_size)
      end)
    end)
  end

  tmp_path
end

defp extract_with_progress(archive_path, output_dir, force, json_mode) do
  # Determine extraction directory
  dest = determine_extraction_dir(archive_path, output_dir, force)

  # Get list of files in archive
  {:ok, files} = list_tar_contents(archive_path)
  file_count = length(files)

  if json_mode do
    # Silent extraction
    extract_tar(archive_path, dest, nil)
  else
    # Extract with progress bar
    Progress.progress_bar(file_count, "Extracting archive", fn bar ->
      extract_tar(archive_path, dest, fn ->
        Progress.update(bar, 1)
      end)
    end)
  end

  # Clean up temp file
  File.rm!(archive_path)

  dest
end
```

### 5.4 Phase 3: Enhanced Run List

**Tests:**

```elixir
# test/tinkex/cli/outputs/run_list_test.exs
defmodule Tinkex.CLI.Outputs.RunListTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Tinkex.CLI.Outputs.RunList
  alias Tinkex.Types.TrainingRun

  test "formats training run table with all columns" do
    runs = [
      %TrainingRun{
        training_run_id: "0478a1ab-95af-5eae-bd70-d3d3b441c021",
        base_model: "Qwen/Qwen2.5-0.5B",
        model_owner: "user@example.ai",
        is_lora: true,
        lora_rank: 32,
        last_request_time: ~U[2025-11-27 08:00:00Z],
        corrupted: false
      }
    ]

    output = RunList.new(runs, total_count: 100, shown_count: 1)
    {columns, rows, opts} = output.to_table()

    assert columns == ["Run ID", "Base Model", "Owner", "LoRA", "Last Update", "Status"]
    assert opts[:title] =~ "1 training run"
    assert opts[:title] =~ "99 more not shown"

    [row] = rows
    assert row == [
      "0478a1ab-95af-5eae-bd70-d3d3b441c021",
      "Qwen/Qwen2.5-0.5B",
      "user@example.ai",
      "Rank 32",
      "4 hours ago",
      "Active"
    ]
  end

  test "handles runs without LoRA" do
    runs = [
      %TrainingRun{
        training_run_id: "abc123",
        base_model: "model/test",
        model_owner: "user",
        is_lora: false,
        lora_rank: nil,
        last_request_time: ~U[2025-11-20 00:00:00Z],
        corrupted: false
      }
    ]

    output = RunList.new(runs)
    {_columns, [row], _opts} = output.to_table()

    [_id, _model, _owner, lora, _time, _status] = row
    assert lora == "No"
  end

  test "shows failed status for corrupted runs" do
    runs = [
      %TrainingRun{
        training_run_id: "failed-run",
        base_model: "model/test",
        model_owner: "user",
        is_lora: false,
        lora_rank: nil,
        last_request_time: ~U[2025-11-20 00:00:00Z],
        corrupted: true
      }
    ]

    output = RunList.new(runs)
    {_columns, [row], _opts} = output.to_table()

    [_id, _model, _owner, _lora, _time, status] = row
    assert status == "Failed"
  end
end
```

**Implementation:**

```elixir
defmodule Tinkex.CLI.Outputs.RunList do
  @moduledoc """
  Output for 'tinkex run list' command.
  """

  @behaviour Tinkex.CLI.Output

  alias Tinkex.CLI.OutputFormatter
  alias Tinkex.Types.TrainingRun

  defstruct [:runs, :total_count, :shown_count]

  def new(runs, opts \\ []) do
    %__MODULE__{
      runs: runs,
      total_count: Keyword.get(opts, :total_count),
      shown_count: Keyword.get(opts, :shown_count, length(runs))
    }
  end

  @impl true
  def to_map(%__MODULE__{runs: runs}) do
    %{"runs" => Enum.map(runs, &Map.from_struct/1)}
  end

  @impl true
  def to_table(%__MODULE__{} = output) do
    columns = ["Run ID", "Base Model", "Owner", "LoRA", "Last Update", "Status"]

    rows = Enum.map(output.runs, fn run ->
      lora_info = if run.is_lora do
        if run.lora_rank do
          "Rank #{run.lora_rank}"
        else
          "Yes"
        end
      else
        "No"
      end

      status = if run.corrupted, do: "Failed", else: "Active"

      [
        run.training_run_id,
        run.base_model,
        run.model_owner,
        lora_info,
        OutputFormatter.format_timestamp(run.last_request_time),
        status
      ]
    end)

    title = build_title(output)

    {columns, rows, [title: title]}
  end

  defp build_title(%{runs: []}), do: "No training runs found"

  defp build_title(%{runs: runs, total_count: total, shown_count: shown}) do
    count = length(runs)

    base = if count == 1 do
      "1 training run"
    else
      "#{count} training runs"
    end

    if total && total > shown do
      remaining = total - shown
      suffix = if remaining == 1 do
        " (1 more not shown, use --limit to see more)"
      else
        " (#{remaining} more not shown, use --limit to see more)"
      end

      base <> suffix
    else
      base
    end
  end
end
```

### 5.5 Phase 4: Pagination with Progress

**Tests:**

```elixir
# test/tinkex/cli/checkpoint_list_pagination_test.exs
defmodule Tinkex.CLI.CheckpointListPaginationTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Tinkex.CLI

  setup do
    # Mock API to return paginated results
    # ...
  end

  test "shows progress bar when fetching multiple pages" do
    output = capture_io(fn ->
      CLI.run(["checkpoint", "list", "--limit", "500"])
    end)

    # Should show progress bar
    assert output =~ "Fetching 500 checkpoints"
    assert output =~ "100%"

    # Should show table after progress completes
    assert output =~ "Checkpoint ID"
    assert output =~ "500 checkpoints"
  end

  test "no progress bar for single page fetch" do
    output = capture_io(fn ->
      CLI.run(["checkpoint", "list", "--limit", "20"])
    end)

    # Should NOT show progress bar (single batch)
    refute output =~ "Fetching"

    # Should show table directly
    assert output =~ "Checkpoint ID"
  end

  test "respects --json flag and skips progress bar" do
    output = capture_io(fn ->
      CLI.run(["checkpoint", "list", "--limit", "500", "--json"])
    end)

    refute output =~ "Fetching"
    assert Jason.decode!(output)["checkpoints"]
  end
end
```

**Implementation (updated checkpoint_list/3):**

```elixir
defp checkpoint_list(config, options, deps) do
  limit = Map.get(options, :limit, 20)
  offset = Map.get(options, :offset, 0)
  json_mode = Map.get(options, :json, false)
  run_id = Map.get(options, :run_id)

  if run_id do
    # Single run - no pagination
    list_checkpoints_for_run(config, run_id, deps, json_mode)
  else
    # All checkpoints - with pagination
    list_all_checkpoints(config, limit, offset, deps, json_mode)
  end
end

defp list_all_checkpoints(config, limit, offset, deps, json_mode) do
  batch_size = 1000

  # First fetch
  {:ok, first_resp} = deps.rest_api_module.list_user_checkpoints(
    config,
    min(batch_size, limit),
    offset
  )

  all_checkpoints = first_resp.checkpoints
  total_count = first_resp.cursor.total_count
  target_count = if limit == 0, do: total_count, else: min(limit, total_count)

  # Fetch remaining with progress bar if needed
  all_checkpoints = if length(all_checkpoints) < target_count and not json_mode do
    fetch_with_progress(
      config,
      all_checkpoints,
      target_count,
      batch_size,
      deps,
      "Fetching #{if limit == 0, do: "all", else: limit} checkpoints"
    )
  else
    all_checkpoints
  end

  # Output results
  output = CheckpointList.new(
    all_checkpoints,
    total_count: total_count,
    shown_count: length(all_checkpoints)
  )

  if json_mode do
    Output.print(output, :json)
  else
    Output.print(output, :table)
  end

  {:ok, %{command: :checkpoint, action: :list, count: length(all_checkpoints)}}
end

defp fetch_with_progress(config, initial_items, target_count, batch_size, deps, label) do
  Progress.progress_bar(target_count, label, fn bar ->
    # Update with initial batch
    Progress.update(bar, length(initial_items))

    # Fetch remaining
    fetch_batches(
      config,
      initial_items,
      target_count,
      batch_size,
      deps,
      bar
    )
  end)
end

defp fetch_batches(config, items, target_count, batch_size, deps, bar) do
  if length(items) >= target_count do
    items
  else
    offset = length(items)
    remaining = target_count - length(items)
    next_batch = min(batch_size, remaining)

    {:ok, resp} = deps.rest_api_module.list_user_checkpoints(
      config,
      next_batch,
      offset
    )

    new_items = items ++ resp.checkpoints
    Progress.update(bar, length(resp.checkpoints))

    # Continue if we got a full batch
    if length(resp.checkpoints) == next_batch do
      fetch_batches(config, new_items, target_count, batch_size, deps, bar)
    else
      new_items
    end
  end
end
```

### 5.6 Test Coverage Summary

**Required Test Files:**

1. **test/tinkex/cli/output_formatter_test.exs** - 100+ assertions
   - Table rendering (empty, data, colors, unicode)
   - Size formatting (all units, edge cases)
   - Timestamp formatting (relative, absolute, ISO strings)
   - Boolean formatting
   - JSON encoding (maps, structs, edge cases)

2. **test/tinkex/cli/output_test.exs** - 20+ assertions
   - Behaviour implementation tests
   - Table/JSON mode switching
   - Integration with OutputFormatter

3. **test/tinkex/cli/outputs/checkpoint_list_test.exs** - 50+ assertions
   - Empty lists
   - Single/multiple checkpoints
   - Pagination metadata
   - Run filtering
   - Column formatting

4. **test/tinkex/cli/outputs/run_list_test.exs** - 40+ assertions
   - LoRA formatting variations
   - Corrupted status handling
   - Timestamp formatting
   - Pagination metadata

5. **test/tinkex/cli/outputs/checkpoint_info_test.exs** - 30+ assertions
   - Property-value table layout
   - Optional fields handling
   - JSON structure

6. **test/tinkex/cli/outputs/run_info_test.exs** - 30+ assertions
   - Nested checkpoint information
   - Metadata display
   - JSON structure

7. **test/tinkex/cli/progress_test.exs** - 20+ assertions
   - Progress bar creation
   - Update mechanics
   - Spinner display
   - Completion handling

8. **test/tinkex/cli/checkpoint_download_test.exs** - 30+ assertions (additions)
   - Download progress display
   - Extraction progress display
   - JSON mode (no progress)
   - Error handling

9. **test/tinkex/cli/checkpoint_list_pagination_test.exs** - 25+ assertions
   - Multi-page progress bars
   - Single-page (no progress)
   - JSON mode behavior
   - Batch fetching logic

**Total:** ~350+ new test assertions

---

## 6. Recommended Libraries

### 6.1 Table Formatting: TableRex

**Repository:** https://github.com/djm/table_rex
**Hex:** https://hex.pm/packages/table_rex
**Version:** 3.1.1 (stable)

**Pros:**
- Pure Elixir (no NIFs/ports)
- Comprehensive border styles (`:all`, `:header`, `:off`)
- Column alignment (`:left`, `:center`, `:right`)
- Cell padding configuration
- Unicode support
- Well-tested (96%+ coverage)
- Active maintenance

**Cons:**
- No built-in color support (need to combine with IO.ANSI)
- Manual width calculations for complex layouts

**Example Usage:**

```elixir
# Add to mix.exs
{:table_rex, "~> 3.1"}

# Usage
alias TableRex.Table

rows = [
  ["001", "checkpoint_1", "2.3 GB"],
  ["002", "checkpoint_2", "1.5 GB"]
]

Table.new(rows, ["ID", "Name", "Size"], "My Checkpoints")
|> Table.put_column_meta(0, align: :left)
|> Table.put_column_meta(1, align: :left)
|> Table.put_column_meta(2, align: :right)
|> Table.render!(horizontal_style: :all)
|> IO.puts()
```

**Output:**
```
+-----+--------------+--------+
|                My Checkpoints |
+-----+--------------+--------+
| ID  | Name         |   Size |
+=====+==============+========+
| 001 | checkpoint_1 | 2.3 GB |
+-----+--------------+--------+
| 002 | checkpoint_2 | 1.5 GB |
+-----+--------------+--------+
```

### 6.2 Progress Bars: Owl

**Repository:** https://github.com/fuelen/owl
**Hex:** https://hex.pm/packages/owl
**Version:** 0.12.0

**Pros:**
- Rich progress bars with percentage, ETA, position
- Spinners for indeterminate tasks
- Multi-bar support (multiple simultaneous progress bars)
- Customizable appearance
- Works with LiveView
- No polling (event-driven updates)
- Well-documented

**Cons:**
- Requires TTY (no-op in non-interactive environments)
- Slightly heavier than simpler alternatives

**Example Usage:**

```elixir
# Add to mix.exs
{:owl, "~> 0.12"}

# Progress bar
alias Owl.{LiveScreen, ProgressBar}

bar = ProgressBar.new(
  id: :download,
  total: 1000,
  label: "Downloading",
  timer: true,
  absolute_values: true
)

LiveScreen.add_block(bar)

Enum.each(1..10, fn _ ->
  # Simulate work
  Process.sleep(100)
  ProgressBar.inc(bar, inc: 100)
end)

LiveScreen.remove_block(bar)

# Spinner
alias Owl.Spinner

spinner = Spinner.new(id: :loading, label: "Loading model")
LiveScreen.add_block(spinner)

# Long task
load_model()

LiveScreen.remove_block(spinner)
```

### 6.3 Colors: IO.ANSI (Built-in)

**Documentation:** https://hexdocs.pm/elixir/IO.ANSI.html

**Already Available** - No dependency needed!

**Example Usage:**

```elixir
# Bright cyan for IDs
id_colored = IO.ANSI.bright() <> IO.ANSI.cyan() <> "ckpt_001" <> IO.ANSI.reset()

# Green success message
success = IO.ANSI.green() <> "✓ Download complete" <> IO.ANSI.reset()

# Red error
error = IO.ANSI.red() <> "✗ Download failed" <> IO.ANSI.reset()

# Convenience functions
IO.puts([IO.ANSI.bright(), IO.ANSI.cyan(), "Header", IO.ANSI.reset()])
```

**Available Colors:**
- Basic: black, red, green, yellow, blue, magenta, cyan, white
- Bright versions: `bright() <> color()`
- Background colors: `*_background()`
- Styles: bold, faint, italic, underline, blink

### 6.4 Alternative: ProgressBar (Simpler Option)

**Repository:** https://github.com/henrik/progress_bar
**Hex:** https://hex.pm/packages/progress_bar
**Version:** 3.0.0

**Pros:**
- Extremely simple API
- Lightweight
- Auto-updates in background task
- Good for basic needs

**Cons:**
- Less feature-rich than Owl
- No multi-bar support
- Basic styling only

**Example:**

```elixir
# Add to mix.exs
{:progress_bar, "~> 3.0"}

# Usage
ProgressBar.render(0, 1000, suffix: "Downloading")

Enum.each(1..10, fn i ->
  Process.sleep(100)
  ProgressBar.render(i * 100, 1000)
end)

ProgressBar.render(1000, 1000, suffix: "Complete")
```

**Recommendation:** Use **Owl** for consistency with rich output formatting.

### 6.5 Dependency Summary

**Minimal Implementation:**

```elixir
# mix.exs additions
defp deps do
  [
    # ... existing deps

    # CLI Output Formatting
    {:table_rex, "~> 3.1"},
    {:owl, "~> 0.12"}
  ]
end
```

**Total New Dependencies:** 2
**Impact:** Both are pure Elixir, well-maintained, with good test coverage

---

## 7. Implementation Roadmap

### 7.1 Sprint 1: Foundation (Week 1)

**Goals:**
- Table formatting infrastructure
- Basic output system
- All tests passing

**Tasks:**
1. Add dependencies (table_rex, owl)
2. Implement `Tinkex.CLI.OutputFormatter` module
3. Implement `Tinkex.CLI.Output` behaviour
4. Write comprehensive tests (100+ assertions)
5. Verify test coverage >90%

**Deliverables:**
- [ ] `lib/tinkex/cli/output_formatter.ex`
- [ ] `lib/tinkex/cli/output.ex`
- [ ] `test/tinkex/cli/output_formatter_test.exs`
- [ ] `test/tinkex/cli/output_test.exs`
- [ ] All tests green

### 7.2 Sprint 2: Checkpoint Commands (Week 2)

**Goals:**
- Refactor checkpoint list/info to use new output system
- Rich table formatting for checkpoints
- JSON mode parity

**Tasks:**
1. Implement `Tinkex.CLI.Outputs.CheckpointList`
2. Implement `Tinkex.CLI.Outputs.CheckpointInfo`
3. Update `checkpoint_list/3` to use new output
4. Update `checkpoint_info/3` to use new output
5. Write output-specific tests (80+ assertions)
6. Integration testing

**Deliverables:**
- [ ] `lib/tinkex/cli/outputs/checkpoint_list.ex`
- [ ] `lib/tinkex/cli/outputs/checkpoint_info.ex`
- [ ] Updated `lib/tinkex/cli.ex` (checkpoint commands)
- [ ] `test/tinkex/cli/outputs/checkpoint_list_test.exs`
- [ ] `test/tinkex/cli/outputs/checkpoint_info_test.exs`
- [ ] All existing tests still passing

### 7.3 Sprint 3: Run Commands (Week 3)

**Goals:**
- Refactor run list/info commands
- Parity with Python SDK output
- Additional metadata display

**Tasks:**
1. Implement `Tinkex.CLI.Outputs.RunList`
2. Implement `Tinkex.CLI.Outputs.RunInfo`
3. Update `run_list/3` to use new output
4. Update `run_info/3` to use new output
5. Write output-specific tests (70+ assertions)

**Deliverables:**
- [ ] `lib/tinkex/cli/outputs/run_list.ex`
- [ ] `lib/tinkex/cli/outputs/run_info.ex`
- [ ] Updated `lib/tinkex/cli.ex` (run commands)
- [ ] `test/tinkex/cli/outputs/run_list_test.exs`
- [ ] `test/tinkex/cli/outputs/run_info_test.exs`

### 7.4 Sprint 4: Progress Bars (Week 4)

**Goals:**
- Progress bar infrastructure
- Checkpoint download progress
- Pagination progress

**Tasks:**
1. Implement `Tinkex.CLI.Progress` module
2. Add download progress to `checkpoint_download/3`
3. Add extraction progress to `checkpoint_download/3`
4. Add pagination progress to `checkpoint_list/3`
5. Add pagination progress to `run_list/3`
6. Write progress tests (45+ assertions)
7. Handle JSON mode (no progress bars)

**Deliverables:**
- [ ] `lib/tinkex/cli/progress.ex`
- [ ] Updated checkpoint download with 2 progress bars
- [ ] Updated list commands with pagination progress
- [ ] `test/tinkex/cli/progress_test.exs`
- [ ] `test/tinkex/cli/checkpoint_download_test.exs` (additions)
- [ ] `test/tinkex/cli/checkpoint_list_pagination_test.exs`
- [ ] `test/tinkex/cli/run_list_pagination_test.exs`

### 7.5 Sprint 5: Polish & Documentation (Week 5)

**Goals:**
- Final UX polish
- Comprehensive documentation
- Example updates

**Tasks:**
1. Add --format option (table/json) for consistency with Python
2. Color refinements and styling
3. Update CLI guide with screenshots
4. Update CHANGELOG.md
5. Update examples in README
6. Manual testing across platforms (Linux, macOS, Windows/WSL)
7. Performance testing (large datasets)

**Deliverables:**
- [ ] Updated `docs/guides/cli_guide.md`
- [ ] Updated `CHANGELOG.md`
- [ ] Updated `README.md` examples
- [ ] Cross-platform verification
- [ ] Performance benchmarks documented

### 7.6 Success Metrics

**Functional:**
- [ ] All checkpoint commands output rich tables
- [ ] All run commands output rich tables
- [ ] Progress bars for downloads (2 bars: download + extract)
- [ ] Progress bars for pagination (when >1 batch needed)
- [ ] JSON mode works for all commands
- [ ] Color highlighting on ID columns
- [ ] Human-readable sizes (GB, MB, KB)
- [ ] Relative timestamps (hours/days/weeks ago)
- [ ] Pagination metadata (X of Y shown, Z more available)

**Quality:**
- [ ] Test coverage >90% for new modules
- [ ] All existing tests pass
- [ ] 350+ new test assertions
- [ ] Zero dialyzer warnings
- [ ] Zero compiler warnings
- [ ] Credo checks pass

**UX:**
- [ ] Output matches Python SDK information density
- [ ] Tables are visually aligned and bordered
- [ ] Progress bars show % + position + ETA
- [ ] No progress bars in JSON mode
- [ ] Error messages remain clear
- [ ] Help text updated appropriately

### 7.7 Optional Enhancements (Post-MVP)

**Priority 2:**
- [ ] Add `--format` option (alias for `--json`, matches Python style)
- [ ] Colored status indicators (green=Active, red=Failed)
- [ ] Emoji support (✓ ✗ ⚠ symbols for status)
- [ ] Wide unicode character support testing
- [ ] Table column auto-sizing based on terminal width

**Priority 3:**
- [ ] Interactive mode (select checkpoint from list)
- [ ] Pager integration for long lists (pipe to less)
- [ ] Export to CSV option
- [ ] Customizable table styles via config
- [ ] Live-updating progress (streaming downloads)

---

## Appendix A: File Structure After Implementation

```
lib/tinkex/cli/
├── output_formatter.ex        # NEW: Table rendering, formatting utilities
├── output.ex                   # NEW: Output behaviour
├── progress.ex                 # NEW: Progress bars and spinners
└── outputs/                    # NEW: Command-specific outputs
    ├── checkpoint_list.ex
    ├── checkpoint_info.ex
    ├── run_list.ex
    └── run_info.ex

test/tinkex/cli/
├── output_formatter_test.exs   # NEW: 100+ assertions
├── output_test.exs             # NEW: 20+ assertions
├── progress_test.exs           # NEW: 20+ assertions
├── checkpoint_download_test.exs # UPDATED: +30 assertions
├── checkpoint_list_pagination_test.exs  # NEW: 25+ assertions
├── run_list_pagination_test.exs         # NEW: 25+ assertions
└── outputs/                    # NEW: Output-specific tests
    ├── checkpoint_list_test.exs  # 50+ assertions
    ├── checkpoint_info_test.exs  # 30+ assertions
    ├── run_list_test.exs         # 40+ assertions
    └── run_info_test.exs         # 30+ assertions
```

---

## Appendix B: Comparison Screenshots

### Before (Current Elixir)

```
$ tinkex checkpoint list --limit 5
ckpt_001    tinker://run-1/weights/001
ckpt_002    tinker://run-1/weights/002
ckpt_003    tinker://run-2/weights/001
ckpt_004    tinker://run-2/weights/002
ckpt_005    tinker://run-3/sampler/001
```

### After (With Implementation)

```
$ tinkex checkpoint list --limit 5

                5 checkpoints (495 more not shown, use --limit to see more)
┏━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Checkpoint ID┃ Type     ┃ Size   ┃ Public ┃ Created     ┃ Path                       ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━╇━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ ckpt_001     │ weights  │ 2.3 GB │ Yes    │ 2 hours ago │ tinker://run-1/weights/001 │
│ ckpt_002     │ weights  │ 2.3 GB │ No     │ 3 hours ago │ tinker://run-1/weights/002 │
│ ckpt_003     │ weights  │ 1.8 GB │ Yes    │ 1 day ago   │ tinker://run-2/weights/001 │
│ ckpt_004     │ weights  │ 1.8 GB │ No     │ 2 days ago  │ tinker://run-2/weights/002 │
│ ckpt_005     │ sampler  │ 890 MB │ Yes    │ 1 week ago  │ tinker://run-3/sampler/001 │
└──────────────┴──────────┴────────┴────────┴─────────────┴────────────────────────────┘
```

(Note: In actual terminal, "ckpt_001", "ckpt_002", etc. would be bright cyan)

---

## Appendix C: Python vs Elixir CLI Command Reference

| Command | Python Invocation | Elixir Invocation | Notes |
|---------|------------------|-------------------|-------|
| List runs | `tinker run list` | `tinkex run list` | ✅ Same |
| Run info | `tinker run info <id>` | `tinkex run info <id>` | ✅ Same |
| List checkpoints | `tinker checkpoint list` | `tinkex checkpoint list` | ✅ Same |
| Checkpoint info | `tinker checkpoint info <path>` | `tinkex checkpoint info <path>` | ✅ Same |
| Download | `tinker checkpoint download <path>` | `tinkex checkpoint download <path>` | ✅ Same |
| Publish | `tinker checkpoint publish <path>` | `tinkex checkpoint publish <path>` | ✅ Same |
| Unpublish | `tinker checkpoint unpublish <path>` | `tinkex checkpoint unpublish <path>` | ✅ Same |
| Delete | `tinker checkpoint delete <path>` | `tinkex checkpoint delete <path>` | ✅ Same |
| Version | `tinker version` | `tinkex version` | ✅ Same |
| JSON output | `tinker <cmd> --format json` (all commands) | `tinkex run --json`, `tinkex version --json` (management commands are text-only) | Elixir missing JSON for list/info/download |
| Save checkpoint | N/A | `tinkex checkpoint --output <path>` | Elixir-only |
| Run sampling | N/A | `tinkex run --prompt <text>` | Elixir-only |

---

## Conclusion

This comprehensive analysis reveals that the Elixir CLI has **functional parity** with the Python CLI (~90% command coverage) but lacks the **UX polish** that makes the Python CLI exceptional. The gap is entirely addressable through:

1. **Table formatting** (TableRex) - Structured, aligned output
2. **Progress bars** (Owl) - Visual feedback for long operations
3. **Formatting utilities** (OutputFormatter) - Human-readable sizes, timestamps
4. **Output abstraction** (Output behaviour) - Clean separation of concerns

The proposed TDD implementation plan provides a clear roadmap for achieving UX parity while maintaining code quality through comprehensive testing (350+ new assertions). With an estimated 5-week timeline, the Elixir CLI can match and potentially exceed the Python CLI's user experience.

**Recommendation:** Proceed with implementation following the phased approach, starting with table formatting infrastructure and progressing through commands in priority order.

---

**Document Version:** 1.0
**Last Updated:** November 27, 2025
**Author:** Claude (Anthropic)
**Review Status:** Ready for Technical Review
