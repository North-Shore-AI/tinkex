# CLI Module Gap Analysis
**Date**: 2025-11-26
**Domain**: Command-Line Interface (CLI)
**Python Source**: `tinker/cli/`
**Elixir Destination**: `lib/tinkex/cli.ex`

---

## Executive Summary

### Overall Assessment
- **Completeness**: ~35%
- **Critical Gaps**: 12
- **High Priority Gaps**: 8
- **Medium Priority Gaps**: 6
- **Low Priority Gaps**: 4

### Key Findings
The Elixir CLI implementation covers only the basic `checkpoint`, `run`, and `version` commands with minimal options. The Python CLI is a comprehensive Click-based application with:
- 3 command groups (checkpoint, run, version)
- 10 subcommands total
- Rich table output and JSON formatting
- Lazy loading for fast startup
- Extensive error handling
- Progress bars and interactive prompts
- Output formatting utilities

The Elixir implementation is a basic escript with hardcoded argument parsing and minimal output formatting. It lacks the modular architecture, rich output, and comprehensive command coverage of Python.

---

## 1. Architecture Comparison

### Python Architecture

**Framework**: Click (decorative command framework)
- `LazyGroup` for fast startup (lazy command loading)
- Context object (`CLIContext`) for shared state
- Decorative error handling (`@handle_api_errors`)
- Modular command structure (separate files per command)
- Abstract output base class (`OutputBase`)

**File Structure**:
```
tinker/cli/
├── __main__.py          # Entry point with LazyGroup
├── client.py            # REST client creation & error handling
├── context.py           # CLIContext dataclass
├── exceptions.py        # TinkerCliError exception
├── lazy_group.py        # LazyGroup for lazy loading
├── output.py            # OutputBase and formatting utilities
└── commands/
    ├── __init__.py
    ├── checkpoint.py    # 7 subcommands
    ├── run.py           # 2 subcommands
    └── version.py       # 1 subcommand
```

### Elixir Architecture

**Framework**: escript with OptionParser
- Single module (`Tinkex.CLI`)
- Manual argument parsing with `OptionParser.parse/2`
- Inline command implementations
- Basic error handling
- Minimal output formatting

**File Structure**:
```
lib/tinkex/
└── cli.ex              # All CLI logic in one file (1013 lines)
```

### Gap Analysis: Architecture

| Component | Python | Elixir | Status |
|-----------|--------|--------|--------|
| **Command Framework** | Click with decorators | OptionParser | ❌ MISSING |
| **Lazy Loading** | LazyGroup | None | ❌ MISSING |
| **Context Object** | CLIContext dataclass | Options map | ⚠️ PARTIAL |
| **Modular Commands** | Separate files per command | Single file | ❌ MISSING |
| **Output Abstraction** | OutputBase class | Inline formatting | ❌ MISSING |
| **Error Handling** | Decorator + custom exception | Inline error messages | ⚠️ PARTIAL |
| **File Organization** | 7 files, ~1200 LOC | 1 file, 1013 LOC | ⚠️ PARTIAL |

---

## 2. Command Coverage Analysis

### Python Commands (10 total)

**Main CLI Group** (`tinker`)
- Global options: `--format/-f` (table/json), `--help/-h`

**1. version** (1 subcommand)
- `tinker version` - Show version information
  - Options: `--json`

**2. checkpoint** (7 subcommands)
- `tinker checkpoint list` - List all checkpoints or by run
  - Options: `--run-id`, `--limit`
- `tinker checkpoint info <path>` - Show checkpoint details
- `tinker checkpoint publish <path>` - Make checkpoint public
- `tinker checkpoint unpublish <path>` - Make checkpoint private
- `tinker checkpoint delete <path>` - Delete checkpoint permanently
  - Options: `--yes/-y`
- `tinker checkpoint download <path>` - Download and extract checkpoint
  - Options: `--output/-o`, `--force`

**3. run** (2 subcommands)
- `tinker run list` - List all training runs
  - Options: `--limit`
- `tinker run info <run_id>` - Show run details

### Elixir Commands (3 total)

**Main CLI** (`tinkex`)
- Global options: `--help/-h`, `--version`

**1. version**
- `tinkex version` - Show version information
  - Options: `--json`, `--deps` (reserved)

**2. checkpoint**
- `tinkex checkpoint` - Save checkpoint metadata
  - Options: `--base-model`, `--model-path`, `--output`, `--rank`, `--seed`, `--train-mlp`, `--train-attn`, `--train-unembed`, `--api-key`, `--base-url`, `--timeout`

**3. run**
- `tinkex run` - Generate text with sampling client
  - Options: `--base-model`, `--model-path`, `--prompt`, `--prompt-file`, `--max-tokens`, `--temperature`, `--top-k`, `--top-p`, `--num-samples`, `--api-key`, `--base-url`, `--timeout`, `--http-pool`, `--output`, `--json`

### Command Comparison Table

| Python Command | Subcommands | Options | Elixir Equivalent | Gap Status |
|----------------|-------------|---------|-------------------|------------|
| **version** | 1 | --json | `tinkex version --json` | ✅ COMPLETE |
| **checkpoint list** | 1 | --run-id, --limit | None | ❌ MISSING |
| **checkpoint info** | 1 | (path arg) | None | ❌ MISSING |
| **checkpoint publish** | 1 | (path arg) | None | ❌ MISSING |
| **checkpoint unpublish** | 1 | (path arg) | None | ❌ MISSING |
| **checkpoint delete** | 1 | --yes/-y, (path arg) | None | ❌ MISSING |
| **checkpoint download** | 1 | --output/-o, --force, (path arg) | None | ❌ MISSING |
| **run list** | 1 | --limit | None | ❌ MISSING |
| **run info** | 1 | (run_id arg) | None | ❌ MISSING |
| **checkpoint (save)** | - | (training opts) | `tinkex checkpoint` | ⚠️ DIFFERENT PURPOSE |
| **run (sampling)** | - | (sampling opts) | `tinkex run` | ⚠️ DIFFERENT PURPOSE |

**Note**: The Elixir `checkpoint` and `run` commands have completely different purposes than the Python equivalents:
- Python: Management commands (list, info, download, etc.)
- Elixir: Execution commands (create checkpoint, perform sampling)

---

## 3. Detailed Gap Analysis

### GAP-CLI-001: Missing Checkpoint List Command
**Severity**: CRITICAL
**Category**: Command Coverage

**Python Feature**:
```python
@cli.command()
@click.option("--run-id", help="Training run ID")
@click.option("--limit", type=int, default=20, help="Maximum number of checkpoints...")
def list(cli_context: CLIContext, run_id: str | None, limit: int):
    """List checkpoints."""
```

Features:
- List all user checkpoints with pagination
- Filter by specific training run (`--run-id`)
- Batch fetching (1000 at a time)
- Progress bar for large lists
- Rich table output with: ID, Type, Size, Public, Created, Path
- JSON output support

**Elixir Status**: Not implemented

**What's Missing**:
- Entire checkpoint listing functionality
- Pagination logic with progress bars
- Run-specific filtering
- Table/JSON output formatting

**Implementation Notes**:
1. Call `RestClient.list_user_checkpoints/1` (if exists in Elixir)
2. Implement pagination with cursor support
3. Add progress bar using IO.ANSI or external library
4. Format output as table or JSON based on `--format` flag

---

### GAP-CLI-002: Missing Checkpoint Info Command
**Severity**: CRITICAL
**Category**: Command Coverage

**Python Feature**:
```python
@cli.command()
@click.argument("checkpoint_path")
def info(cli_context: CLIContext, checkpoint_path: str):
    """Show details of a specific checkpoint."""
```

Features:
- Display detailed checkpoint information
- Parse tinker:// paths
- Property table: ID, Type, Path, Size, Public, Created, Training Run ID
- JSON output support

**Elixir Status**: Not implemented

**What's Missing**:
- Checkpoint detail retrieval
- Tinker path parsing
- Property formatting

**Implementation Notes**:
1. Parse `tinker://run-id/weights/0001` format
2. Call appropriate API to fetch checkpoint details
3. Format as key-value table or JSON

---

### GAP-CLI-003: Missing Checkpoint Download Command
**Severity**: CRITICAL
**Category**: Command Coverage

**Python Feature**:
```python
@cli.command()
@click.argument("checkpoint_path")
@click.option("--output", "-o", type=click.Path(), help="Parent directory...")
@click.option("--force", is_flag=True, help="Overwrite existing directory")
def download(cli_context, checkpoint_path, output, force):
    """Download and extract a checkpoint archive."""
```

Features:
- Download checkpoint archive from URL
- Progress bar for download (with size, ETA)
- Extract tar archive with progress bar
- Automatic cleanup of archive after extraction
- Force overwrite option
- Validate tinker:// paths
- Error handling for network/IO failures

**Elixir Status**: Not implemented

**What's Missing**:
- HTTP download with progress
- Tar extraction
- Temp file management
- Progress indicators

**Implementation Notes**:
1. Use HTTPoison or Finch for HTTP download
2. Use `:erl_tar` for extraction
3. Implement progress bar (manual IO or library)
4. Handle temp directories properly

---

### GAP-CLI-004: Missing Checkpoint Publish/Unpublish Commands
**Severity**: HIGH
**Category**: Command Coverage

**Python Features**:
```python
@cli.command()
def publish(cli_context: CLIContext, checkpoint_path: str):
    """Publish a checkpoint to make it publicly accessible."""

@cli.command()
def unpublish(cli_context: CLIContext, checkpoint_path: str):
    """Unpublish a checkpoint to make it private again."""
```

Features:
- Change checkpoint visibility
- Path validation
- API integration

**Elixir Status**: Not implemented

**What's Missing**:
- Publish/unpublish API calls
- Path validation
- Success/error messaging

**Implementation Notes**:
1. Add API client methods for publish/unpublish
2. Parse and validate tinker paths
3. Display confirmation messages

---

### GAP-CLI-005: Missing Checkpoint Delete Command
**Severity**: HIGH
**Category**: Command Coverage

**Python Feature**:
```python
@cli.command()
@click.argument("checkpoint_path")
@click.option("--yes", "-y", is_flag=True, help="Skip confirmation prompt")
def delete(cli_context, checkpoint_path, yes):
    """Delete a checkpoint permanently. WARNING: Permanent."""
```

Features:
- Interactive confirmation prompt (unless `--yes`)
- Display checkpoint info before deletion
- Permanent deletion warning
- API integration

**Elixir Status**: Not implemented

**What's Missing**:
- Delete API call
- Interactive confirmation
- Warning messages

**Implementation Notes**:
1. Add `IO.gets/1` for confirmation prompt
2. Display checkpoint info first
3. Call delete API endpoint
4. Handle errors gracefully

---

### GAP-CLI-006: Missing Run List Command
**Severity**: CRITICAL
**Category**: Command Coverage

**Python Feature**:
```python
@cli.command()
@click.option("--limit", type=int, default=20, help="Maximum runs...")
def list(cli_context: CLIContext, limit: int):
    """List all training runs."""
```

Features:
- List all training runs with pagination
- Batch fetching (100 at a time)
- Progress bar for large lists
- Table columns: Run ID, Base Model, Owner, LoRA, Last Update, Status
- Total count with "X more not shown" message
- JSON output support

**Elixir Status**: Not implemented

**What's Missing**:
- Training run listing
- Pagination with cursor
- Progress bars
- Rich table output

**Implementation Notes**:
1. Call `RestClient.list_training_runs/1`
2. Implement pagination loop
3. Format output table
4. Add progress indicators

---

### GAP-CLI-007: Missing Run Info Command
**Severity**: CRITICAL
**Category**: Command Coverage

**Python Feature**:
```python
@cli.command()
@click.argument("run_id")
def info(cli_context: CLIContext, run_id: str):
    """Show details of a specific run."""
```

Features:
- Display detailed training run information
- Property table: Run ID, Base Model, Owner, LoRA info, Status, Checkpoints, Metadata
- Last checkpoint details (training & sampler)
- User metadata display
- JSON output support

**Elixir Status**: Not implemented

**What's Missing**:
- Run detail retrieval
- Metadata formatting
- Checkpoint display

**Implementation Notes**:
1. Call `RestClient.get_training_run/1`
2. Format as property table
3. Display nested checkpoint info
4. Show user metadata if present

---

### GAP-CLI-008: Missing Output Abstraction Layer
**Severity**: HIGH
**Category**: Architecture

**Python Feature** (`output.py`):
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

    def print(self, format: str = "table") -> None:
        """Print the output in the specified format."""
        if format == "json":
            self._print_json()
        else:
            self._print_table()
```

Features:
- Abstract base class for all outputs
- Automatic format detection (table vs JSON)
- Rich table rendering with styling
- Utility functions: `format_size`, `format_timestamp`, `format_bool`, `format_optional`

Output classes:
1. `CheckpointListOutput`
2. `CheckpointInfoOutput`
3. `CheckpointDownloadOutput`
4. `RunListOutput`
5. `RunInfoOutput`

**Elixir Status**: Inline formatting only

**What's Missing**:
- Abstract output protocol/behavior
- Dedicated output modules per command
- Table formatting utilities
- Consistent styling

**Implementation Notes**:
1. Create `Tinkex.CLI.Output` behavior with callbacks
2. Implement `Tinkex.CLI.Output.Table` for rich tables
3. Implement `Tinkex.CLI.Output.JSON` for JSON formatting
4. Create utility module `Tinkex.CLI.Formatter` with:
   - `format_size/1`
   - `format_timestamp/1`
   - `format_bool/1`
   - `format_optional/2`
5. Create output modules:
   - `Tinkex.CLI.Output.CheckpointList`
   - `Tinkex.CLI.Output.CheckpointInfo`
   - `Tinkex.CLI.Output.RunList`
   - `Tinkex.CLI.Output.RunInfo`

---

### GAP-CLI-009: Missing Rich Table Output
**Severity**: MEDIUM
**Category**: User Experience

**Python Feature**:
Uses `rich.table.Table` for beautiful terminal output:
- Colored headers and cells
- Automatic column sizing
- Table titles
- Styled first column (bright cyan)
- Progress bars with ETA

Example output:
```
╭─────────────────────────────────────────────────────────────╮
│             15 checkpoints for run run-abc123               │
├──────────────┬──────┬────────┬────────┬─────────┬──────────┤
│ Checkpoint   │ Type │ Size   │ Public │ Created │ Path     │
│ ID           │      │        │        │         │          │
├──────────────┼──────┼────────┼────────┼─────────┼──────────┤
│ weights_0001 │ LoRA │ 1.2 GB │ No     │ 2 hours │ tinker://│
│              │      │        │        │ ago     │ ...      │
└──────────────┴──────┴────────┴────────┴─────────┴──────────┘
```

**Elixir Status**: Plain text output only

**What's Missing**:
- Rich table rendering
- Colors and styling
- Progress bars
- Box drawing characters

**Implementation Notes**:
1. Use `IO.ANSI` for colors
2. Consider `TableRex` library for table rendering
3. Implement progress bar module (or use `ProgressBar` library)
4. Add table border options

---

### GAP-CLI-010: Missing Lazy Command Loading
**Severity**: MEDIUM
**Category**: Performance

**Python Feature** (`lazy_group.py`):
```python
class LazyGroup(click.Group):
    """A Click Group that supports lazy loading of subcommands."""

    def __init__(self, *args, lazy_subcommands: Dict[str, str] | None = None, **kwargs):
        super().__init__(*args, **kwargs)
        self.lazy_subcommands = lazy_subcommands or {}

    def get_command(self, ctx, cmd_name):
        """Get a command by name, loading it lazily if necessary."""
        if cmd_name in self.lazy_subcommands:
            return self._lazy_load(cmd_name)
        return super().get_command(ctx, cmd_name)
```

Configuration:
```python
lazy_subcommands={
    "checkpoint": "tinker.cli.commands.checkpoint:cli",
    "run": "tinker.cli.commands.run:cli",
    "version": "tinker.cli.commands.version:cli",
}
```

Benefits:
- Fast CLI startup (~50ms)
- Commands imported only when invoked
- Help text displays all commands without loading them

**Elixir Status**: All commands loaded at compile time

**What's Missing**:
- Dynamic module loading
- Lazy command registration
- Startup time optimization

**Implementation Notes**:
1. Not critical for Elixir (compiled, not interpreted)
2. Could use `Code.ensure_loaded?/1` for runtime checks
3. Consider modular command structure (separate modules)
4. escript compiles everything, so less benefit than Python

---

### GAP-CLI-011: Missing Client Error Handling Decorator
**Severity**: MEDIUM
**Category**: Error Handling

**Python Feature** (`client.py`):
```python
@handle_api_errors
def my_command(...):
    """Command implementation."""
    # Decorated function automatically handles:
    # - NotFoundError -> "Resource not found"
    # - AuthenticationError -> "Authentication failed"
    # - PermissionDeniedError -> "Permission denied"
    # - BadRequestError -> "Invalid request"
    # - UnprocessableEntityError -> "Invalid data provided"
    # - RateLimitError -> "Rate limit exceeded"
    # - InternalServerError -> "Internal server error"
    # - APITimeoutError -> "Request timeout"
    # - APIConnectionError -> "Connection failed"
    # - APIStatusError -> "API error (status X)"
    # - APIError -> Generic API error
```

Features:
- Centralized error handling
- User-friendly error messages
- Automatic error type detection
- Optional traceback in terminal
- Consistent error formatting

**Elixir Status**: Inline error handling per command

**What's Missing**:
- Centralized error handler
- Consistent error messages
- Error type classification
- Decorator pattern (macro)

**Implementation Notes**:
1. Create `Tinkex.CLI.ErrorHandler` module
2. Define macro `handle_api_errors/1` that wraps function
3. Pattern match on `Tinkex.Error` struct
4. Map error types to user-friendly messages
5. Add optional verbose mode with full error details

Example:
```elixir
defmodule Tinkex.CLI.ErrorHandler do
  defmacro handle_api_errors(do: block) do
    quote do
      try do
        unquote(block)
      rescue
        e in Tinkex.Error ->
          format_error(e)
          {:error, e}
      end
    end
  end

  defp format_error(%Tinkex.Error{type: :not_found}), do:
    IO.puts(:stderr, "Error: Resource not found")
  # ... more patterns
end
```

---

### GAP-CLI-012: Missing Progress Bars
**Severity**: LOW
**Category**: User Experience

**Python Feature**:
Uses `click.progressbar()` for:
- Checkpoint list pagination (e.g., "Fetching 5000 checkpoints")
- Run list pagination (e.g., "Fetching all training runs")
- Checkpoint download (with size and ETA)
- Archive extraction (with file count)

Features:
- Shows percent complete
- Shows position (e.g., "1234/5000")
- Shows ETA (estimated time remaining)
- Adaptive width to terminal

Example:
```
Fetching 5000 checkpoints  [################------------]  55%  2750/5000  00:23
Downloading archive        [########################]   100%  1.2GB/1.2GB   00:00
Extracting archive         [####################----]    85%  850/1000
```

**Elixir Status**: No progress indication

**What's Missing**:
- Progress bars
- ETA calculation
- Visual feedback for long operations

**Implementation Notes**:
1. Use `IO.ANSI` for progress rendering
2. Consider `ProgressBar` hex package
3. Implement custom progress module with:
   - `start/2` - Initialize with label and total
   - `update/2` - Update current progress
   - `finish/1` - Complete and clear
4. Add to long operations:
   - Pagination loops
   - HTTP downloads
   - File extraction

---

### GAP-CLI-013: Missing Global Format Option
**Severity**: HIGH
**Category**: User Experience

**Python Feature**:
```python
@click.group(...)
@click.option(
    "--format",
    "-f",
    type=click.Choice(["table", "json"]),
    default="table",
    help="Output format (default: table)",
)
def main_cli(ctx: click.Context, format: str):
    """Tinker management CLI."""
    ctx.obj = CLIContext(format=format)
```

Features:
- Global `--format` flag available to all commands
- Passed via context to all subcommands
- Consistent JSON output across all commands
- Table is default for terminal

**Elixir Status**: `--json` flag on individual commands only

**What's Missing**:
- Global format flag
- Context passing between commands
- Consistent format handling

**Implementation Notes**:
1. Add global `--format` option to parser
2. Create context struct: `%CLI.Context{format: :table | :json}`
3. Pass context to all command handlers
4. Ensure all outputs support both formats

---

### GAP-CLI-014: Missing Context Object Pattern
**Severity**: MEDIUM
**Category**: Architecture

**Python Feature** (`context.py`):
```python
@dataclass
class CLIContext:
    """Context object for sharing state between CLI commands."""
    format: Literal["table", "json"] = "table"
```

Used via Click's context passing:
```python
@click.pass_obj
def command(cli_context: CLIContext, ...):
    format = cli_context.format
    output.print(format=format)
```

**Elixir Status**: Options map passed directly

**What's Missing**:
- Dedicated context struct
- Type safety for context
- Explicit context passing

**Implementation Notes**:
1. Create `Tinkex.CLI.Context` struct
2. Add fields: `format`, `verbose`, `api_key`, `base_url`, etc.
3. Build context from global options
4. Pass to all command handlers

---

### GAP-CLI-015: Missing Custom Exception Class
**Severity**: LOW
**Category**: Error Handling

**Python Feature** (`exceptions.py`):
```python
class TinkerCliError(Exception):
    """Custom exception for CLI errors that should exit gracefully."""

    def __init__(self, message: str, details: str | None = None, exit_code: int = 1):
        self.message = message
        self.details = details
        self.exit_code = exit_code
```

Used for:
- User-facing errors (invalid arguments, missing files)
- API errors (wrapped and formatted)
- Graceful exit with proper codes

**Elixir Status**: Uses `Tinkex.Error` directly

**What's Missing**:
- CLI-specific error struct
- Exit code mapping
- Details field for suggestions

**Implementation Notes**:
1. Create `Tinkex.CLI.Error` struct (or use tagged tuples)
2. Add fields: `message`, `details`, `exit_code`, `category`
3. Map `Tinkex.Error` types to CLI errors
4. Include helpful suggestions in `details`

Example:
```elixir
defmodule Tinkex.CLI.Error do
  defstruct [:message, :details, exit_code: 1, category: :user]

  def from_api_error(%Tinkex.Error{type: :not_found}) do
    %__MODULE__{
      message: "Resource not found",
      details: "Check the ID and try again.",
      category: :user
    }
  end
end
```

---

### GAP-CLI-016: Missing Formatting Utilities
**Severity**: MEDIUM
**Category**: User Experience

**Python Feature** (`output.py`):
```python
def format_size(bytes: int) -> str:
    """Format bytes as human-readable size (e.g., "1.2 GB")."""

def format_timestamp(dt: Union[datetime, str, None]) -> str:
    """Format datetime as relative time or absolute date (e.g., "2 hours ago")."""

def format_bool(value: bool) -> str:
    """Format boolean for display ("Yes" or "No")."""

def format_optional(value: Any, formatter: Callable[[Any], str] | None = None) -> str:
    """Format an optional value ("N/A" if None)."""
```

**Elixir Status**: No formatting utilities

**What's Missing**:
- Size formatting (bytes -> GB)
- Timestamp formatting (datetime -> relative time)
- Boolean formatting
- Optional value handling

**Implementation Notes**:
1. Create `Tinkex.CLI.Formatter` module
2. Implement functions:
   ```elixir
   def format_size(bytes)
   def format_timestamp(%DateTime{})
   def format_bool(boolean)
   def format_optional(value, formatter \\ nil)
   ```
3. Use Timex for relative time formatting
4. Add unit tests for edge cases

---

### GAP-CLI-017: Missing REST Client Factory
**Severity**: MEDIUM
**Category**: Architecture

**Python Feature** (`client.py`):
```python
def create_rest_client() -> "RestClient":
    """Create and configure a RestClient instance with proper error handling."""
    try:
        service_client = ServiceClient()
        return service_client.create_rest_client()
    except ImportError as e:
        raise TinkerCliError(f"Failed to import Tinker SDK: {e}", ...)
    except ValueError as e:
        raise TinkerCliError(f"Configuration error: {e}", ...)
    except Exception as e:
        raise TinkerCliError(f"Failed to connect to Tinker API: {e}", ...)
```

Features:
- Centralized client creation
- Error handling for common failures
- User-friendly error messages

**Elixir Status**: Inline client creation in each command

**What's Missing**:
- Client factory function
- Centralized error handling
- Configuration validation

**Implementation Notes**:
1. Create `Tinkex.CLI.Client` module
2. Add `create_rest_client/1` function
3. Handle common errors:
   - Missing API key
   - Invalid base URL
   - Network failures
4. Return user-friendly errors

---

### GAP-CLI-018: Missing Modular Command Structure
**Severity**: MEDIUM
**Category**: Architecture

**Python Structure**:
```
commands/
├── checkpoint.py   # 651 lines, 7 subcommands
├── run.py          # 258 lines, 2 subcommands
└── version.py      # 19 lines, 1 subcommand
```

Benefits:
- Separation of concerns
- Easy to find specific commands
- Independent testing
- Parallel development

**Elixir Structure**:
```
cli.ex             # 1013 lines, all commands
```

**What's Missing**:
- Separate modules per command group
- Command registration system
- Independent command files

**Implementation Notes**:
1. Create module structure:
   ```
   lib/tinkex/cli/
   ├── cli.ex              # Main entry point
   ├── context.ex          # Context struct
   ├── error_handler.ex    # Error handling
   ├── formatter.ex        # Formatting utilities
   ├── output.ex           # Output behavior
   └── commands/
       ├── checkpoint.ex   # Checkpoint commands
       ├── run.ex          # Run commands
       └── version.ex      # Version command
   ```
2. Each command module implements command callbacks
3. Main CLI dispatches to command modules
4. Use behaviors for consistent interface

---

### GAP-CLI-019: Missing Interactive Prompts
**Severity**: LOW
**Category**: User Experience

**Python Feature**:
Uses `click.confirm()` for destructive operations:
```python
if not click.confirm("Are you sure you want to delete this checkpoint?"):
    click.echo("Deletion cancelled.")
    return
```

Also uses `click.echo()` for formatted output.

**Elixir Status**: No interactive prompts

**What's Missing**:
- Confirmation prompts
- Yes/no prompts
- Input validation

**Implementation Notes**:
1. Use `IO.gets/1` for prompts
2. Create helper function:
   ```elixir
   def confirm?(message) do
     IO.write(message <> " (y/n): ")
     case IO.gets("") |> String.trim() |> String.downcase() do
       "y" -> true
       "yes" -> true
       _ -> false
     end
   end
   ```
3. Add to destructive commands (delete, unpublish)

---

### GAP-CLI-020: Missing Help Text System
**Severity**: LOW
**Category**: User Experience

**Python Feature**:
Uses Click's automatic help generation:
- `--help` on any command shows usage
- Docstrings become help text
- Option descriptions auto-formatted
- Command groups show subcommands

Example:
```bash
$ tinker checkpoint --help
Usage: tinker checkpoint [OPTIONS] COMMAND [ARGS]...

  Manage checkpoints.

Options:
  -h, --help  Show this message and exit.

Commands:
  list       List checkpoints
  info       Show details of a specific checkpoint
  download   Download and extract a checkpoint archive
  publish    Publish a checkpoint to make it publicly accessible
  unpublish  Unpublish a checkpoint to make it private again
  delete     Delete a checkpoint permanently
```

**Elixir Status**: Manual help text in `*_help/0` functions

**What's Missing**:
- Automatic help generation
- Consistent formatting
- Command discovery

**Implementation Notes**:
1. Current implementation is adequate but manual
2. Could use metaprogramming to generate help from option specs
3. Consider `optimus` library for better option parsing and help

---

### GAP-CLI-021: Missing Alias Support
**Severity**: LOW
**Category**: User Experience

**Python Feature**:
```python
aliases = [h: :help]
```

Short flags like `-h`, `-f`, `-o`, `-y`

**Elixir Status**:
- Has `-h` alias for `--help`
- No short flags for other options

**What's Missing**:
- Short option aliases
- Consistent alias system

**Implementation Notes**:
1. Add to `aliases/0`:
   ```elixir
   defp aliases do
     [
       h: :help,
       f: :format,
       o: :output,
       y: :yes
     ]
   end
   ```
2. Update help text to show both forms

---

### GAP-CLI-022: Semantic Difference in Commands
**Severity**: CRITICAL
**Category**: Design Mismatch

**Issue**: The Elixir and Python CLIs use the same command names for completely different purposes:

**Python `checkpoint` command**:
- Purpose: **Manage** existing checkpoints
- Subcommands: list, info, download, publish, unpublish, delete
- Focus: Checkpoint retrieval and management

**Elixir `checkpoint` command**:
- Purpose: **Create** a new checkpoint (save weights)
- Options: Training configuration (base-model, rank, seed, etc.)
- Focus: Checkpoint creation

**Python `run` command**:
- Purpose: **Manage** training runs
- Subcommands: list, info
- Focus: Training run metadata

**Elixir `run` command**:
- Purpose: **Execute** text generation (sampling)
- Options: Sampling parameters (prompt, max-tokens, temperature, etc.)
- Focus: Inference execution

**What's Missing**:
The Elixir CLI needs TWO separate command namespaces:
1. **Management commands** (like Python): `checkpoint list`, `run list`, etc.
2. **Execution commands** (current Elixir): Maybe rename to `train` and `sample`?

**Recommendations**:
1. Rename Elixir commands for clarity:
   - `checkpoint` → `train checkpoint` or `save-checkpoint`
   - `run` → `sample` or `generate`
2. Add new management commands:
   - `checkpoint list/info/download/etc.` (Python parity)
   - `run list/info` (Python parity)
3. Or use subcommand groups:
   - `checkpoint create` (current Elixir checkpoint)
   - `checkpoint list` (Python checkpoint list)
   - `run sample` (current Elixir run)
   - `run list` (Python run list)

---

## 4. CLI Options Analysis

### Version Command Options

| Option | Type | Python Default | Elixir Default | Status |
|--------|------|----------------|----------------|--------|
| `--json` | boolean | false | false | ✅ COMPLETE |
| `--deps` | boolean | N/A | false (reserved) | ⚠️ EXTRA (Elixir) |

### Checkpoint Command Options

**Python** (per subcommand):

**list**:
- `--run-id` (string) - Filter by training run
- `--limit` (integer, default: 20) - Max checkpoints to show

**info**:
- `<checkpoint_path>` (positional arg) - Tinker path

**download**:
- `<checkpoint_path>` (positional arg) - Tinker path
- `--output/-o` (path) - Parent directory
- `--force` (boolean) - Overwrite existing

**delete**:
- `<checkpoint_path>` (positional arg) - Tinker path
- `--yes/-y` (boolean) - Skip confirmation

**publish/unpublish**:
- `<checkpoint_path>` (positional arg) - Tinker path

**Elixir** (single command):
- `--base-model` (string) - Base model ID
- `--model-path` (string) - Local model path
- `--output` (string) - Metadata output path
- `--rank` (integer) - LoRA rank
- `--seed` (integer) - Random seed
- `--train-mlp` (boolean) - Enable MLP training
- `--train-attn` (boolean) - Enable attention training
- `--train-unembed` (boolean) - Enable unembedding training
- `--api-key` (string) - API key
- `--base-url` (string) - API base URL
- `--timeout` (integer) - Request timeout (ms)

**Gap**: Completely different option sets due to different command purposes.

### Run Command Options

**Python** (per subcommand):

**list**:
- `--limit` (integer, default: 20) - Max runs to fetch

**info**:
- `<run_id>` (positional arg) - Training run ID

**Elixir** (single command):
- `--base-model` (string) - Base model ID
- `--model-path` (string) - Local model path
- `--prompt` (string) - Prompt text
- `--prompt-file` (string) - Prompt file path
- `--max-tokens` (integer) - Max tokens to generate
- `--temperature` (float) - Sampling temperature
- `--top-k` (integer) - Top-k sampling
- `--top-p` (float) - Nucleus sampling
- `--num-samples` (integer) - Number of samples
- `--api-key` (string) - API key
- `--base-url` (string) - API base URL
- `--timeout` (integer) - Request timeout (ms)
- `--http-pool` (string) - HTTP pool name
- `--output` (string) - Output file path
- `--json` (boolean) - JSON output

**Gap**: Completely different option sets due to different command purposes.

### Global Options

| Option | Python | Elixir | Status |
|--------|--------|--------|--------|
| `--format/-f` | ✅ (table/json) | ❌ | MISSING |
| `--help/-h` | ✅ | ✅ | COMPLETE |
| `--version` | ✅ | ✅ | COMPLETE |

---

## 5. Output Formatting Analysis

### Python Output System

**Architecture**:
```python
class OutputBase(ABC):
    def to_dict(self) -> Dict[str, Any]           # For JSON
    def get_table_columns(self) -> List[str]      # Table headers
    def get_table_rows(self) -> List[List[str]]   # Table rows
    def get_title(self) -> str | None             # Table title
    def print(self, format: str = "table")        # Render output
```

**Concrete Implementations**:
1. `CheckpointListOutput` - List of checkpoints with pagination info
2. `CheckpointInfoOutput` - Single checkpoint details
3. `CheckpointDownloadOutput` - Download confirmation
4. `RunListOutput` - List of training runs with pagination
5. `RunInfoOutput` - Single run details

**Features**:
- Automatic format detection
- Rich table rendering with `rich.table.Table`
- JSON serialization with `json.dump`
- Utility functions for formatting
- Consistent output across all commands

### Elixir Output System

**Architecture**: Inline string formatting

**Implementations**:
- `checkpoint`: Prints "Checkpoint saved to {path}"
- `run`: Prints plain text sequences or JSON
- `version`: Prints "tinkex {version} ({commit})" or JSON

**Features**:
- Basic string interpolation
- JSON encoding with Jason
- No table rendering
- No styling or colors

### Gap Summary

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Output Abstraction** | ✅ OutputBase class | ❌ Inline | CRITICAL |
| **Table Rendering** | ✅ Rich tables | ❌ Plain text | CRITICAL |
| **JSON Output** | ✅ All commands | ⚠️ Some commands | PARTIAL |
| **Formatting Utils** | ✅ 4 functions | ❌ None | HIGH |
| **Styling/Colors** | ✅ Rich library | ❌ None | MEDIUM |
| **Progress Bars** | ✅ Download/pagination | ❌ None | MEDIUM |
| **Titles** | ✅ Optional titles | ❌ None | LOW |

---

## 6. Error Handling Analysis

### Python Error Handling

**Architecture**: Multi-layered error handling

**Layer 1: Custom Exception**:
```python
class TinkerCliError(Exception):
    message: str
    details: str | None
    exit_code: int
```

**Layer 2: API Error Decorator**:
```python
@handle_api_errors
def command(...):
    # Automatically catches and converts:
    # - NotFoundError
    # - AuthenticationError
    # - PermissionDeniedError
    # - BadRequestError
    # - UnprocessableEntityError
    # - RateLimitError
    # - InternalServerError
    # - APITimeoutError
    # - APIConnectionError
    # - APIStatusError
    # - APIError
    # - Generic Exception (with traceback in terminal)
```

**Layer 3: Top-Level Handler**:
```python
def main():
    try:
        main_cli()
    except TinkerCliError as e:
        print(f"Error: {e.message}", file=sys.stderr)
        if e.details:
            print(e.details, file=sys.stderr)
        sys.exit(e.exit_code)
    except KeyboardInterrupt:
        sys.exit(130)
```

**Features**:
- User-friendly error messages
- Optional details/suggestions
- Proper exit codes
- Traceback in debug mode
- Keyboard interrupt handling

### Elixir Error Handling

**Architecture**: Inline error handling

**Pattern Matching**:
```elixir
case some_function() do
  {:ok, result} -> ...
  {:error, %Error{} = error} ->
    IO.puts(:stderr, "Failed: " <> Error.format(error))
    {:error, error}
  {:error, reason} ->
    IO.puts(:stderr, "Failed: #{inspect(reason)}")
    {:error, reason}
end
```

**Top-Level**:
```elixir
def main(argv) do
  exit_code =
    case run(argv) do
      {:ok, _} -> 0
      {:error, _} -> 1
    end
  System.halt(exit_code)
end
```

**Features**:
- Basic error messages
- Error categorization (user vs server)
- Exit code 0/1
- Keyboard interrupt (exit 130) - MISSING

### Gap Summary

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Custom Exception** | ✅ TinkerCliError | ⚠️ Uses Tinkex.Error | PARTIAL |
| **API Error Mapping** | ✅ @handle_api_errors | ❌ Inline | HIGH |
| **User-Friendly Messages** | ✅ Consistent | ⚠️ Inconsistent | MEDIUM |
| **Exit Codes** | ✅ Configurable | ⚠️ Only 0/1 | MEDIUM |
| **Details/Suggestions** | ✅ Yes | ❌ No | MEDIUM |
| **Keyboard Interrupt** | ✅ Exit 130 | ❌ Not handled | LOW |
| **Debug Traceback** | ✅ In terminal | ❌ No | LOW |

---

## 7. Context/State Management Analysis

### Python Context Management

**Architecture**: Click's context passing

**CLIContext Dataclass**:
```python
@dataclass
class CLIContext:
    """Context object for sharing state between CLI commands."""
    format: Literal["table", "json"] = "table"
```

**Usage**:
```python
# Set in main CLI
@click.pass_context
def main_cli(ctx: click.Context, format: str):
    ctx.obj = CLIContext(format=format)

# Access in subcommands
@click.pass_obj
def list(cli_context: CLIContext, ...):
    format = cli_context.format
    output.print(format=format)
```

**Features**:
- Type-safe context
- Automatic passing via Click
- Immutable dataclass
- Single source of truth

### Elixir Context Management

**Architecture**: Options map passed directly

**Pattern**:
```elixir
defp dispatch(command, options) do
  case command do
    :checkpoint -> run_checkpoint(options)
    :run -> run_sampling(options)
    :version -> ...
  end
end

def run_checkpoint(options, overrides \\ %{})
```

**Features**:
- Simple map passing
- No formal context struct
- Options merged with overrides

### Gap Summary

| Feature | Python | Elixir | Gap |
|---------|--------|--------|-----|
| **Context Struct** | ✅ CLIContext | ❌ Map | MEDIUM |
| **Type Safety** | ✅ Dataclass | ❌ Map | MEDIUM |
| **Global State** | ✅ Format, config | ⚠️ Options only | LOW |
| **Passing Mechanism** | ✅ Click context | ⚠️ Manual | LOW |

**Recommendation**: Create `Tinkex.CLI.Context` struct for type safety and consistency.

---

## 8. Testing Considerations

### Python Testing

Commands are designed for testability:
- Lazy loading allows mocking imports
- Context object is injectable
- Output classes are independently testable
- Decorator pattern enables wrapping for tests

### Elixir Testing

Commands use dependency injection:
- `sampling_deps/1` and `checkpoint_deps/1` allow overrides
- Application.get_env for test configuration
- Mocks injected via overrides map

**Gap**: Python has more granular testability due to modular structure.

---

## 9. Recommendations

### Phase 1: Critical Gaps (Weeks 1-2)
1. **GAP-CLI-022**: Resolve command naming conflict
   - Rename Elixir commands or add subcommand structure
   - Decision: `checkpoint create` vs `checkpoint list` distinction
2. **GAP-CLI-001**: Implement `checkpoint list` command
3. **GAP-CLI-006**: Implement `run list` command
4. **GAP-CLI-008**: Create output abstraction layer
   - Define `Tinkex.CLI.Output` behavior
   - Implement table and JSON renderers

### Phase 2: High Priority (Weeks 3-4)
5. **GAP-CLI-002**: Implement `checkpoint info` command
6. **GAP-CLI-003**: Implement `checkpoint download` command
7. **GAP-CLI-007**: Implement `run info` command
8. **GAP-CLI-013**: Add global `--format` flag
9. **GAP-CLI-016**: Create formatting utilities module

### Phase 3: Medium Priority (Weeks 5-6)
10. **GAP-CLI-009**: Add rich table rendering (TableRex)
11. **GAP-CLI-011**: Create error handling macro
12. **GAP-CLI-012**: Add progress bars
13. **GAP-CLI-014**: Create context struct
14. **GAP-CLI-017**: Create client factory module
15. **GAP-CLI-018**: Split into modular command structure

### Phase 4: Low Priority (Weeks 7-8)
16. **GAP-CLI-004**: Implement `checkpoint publish/unpublish` commands
17. **GAP-CLI-005**: Implement `checkpoint delete` command
18. **GAP-CLI-019**: Add interactive prompts
19. **GAP-CLI-020**: Improve help text system
20. **GAP-CLI-021**: Add short option aliases

### Phase 5: Optional Improvements
21. **GAP-CLI-010**: Lazy command loading (low value for Elixir)
22. **GAP-CLI-015**: Custom CLI error struct

---

## 10. Priority Matrix

### Critical (Must Have)
- [ ] GAP-CLI-022: Resolve command naming conflict
- [ ] GAP-CLI-001: checkpoint list command
- [ ] GAP-CLI-006: run list command
- [ ] GAP-CLI-008: Output abstraction layer

### High (Should Have)
- [ ] GAP-CLI-002: checkpoint info command
- [ ] GAP-CLI-003: checkpoint download command
- [ ] GAP-CLI-007: run info command
- [ ] GAP-CLI-013: Global format flag
- [ ] GAP-CLI-016: Formatting utilities
- [ ] GAP-CLI-011: Error handling decorator

### Medium (Nice to Have)
- [ ] GAP-CLI-009: Rich table rendering
- [ ] GAP-CLI-012: Progress bars
- [ ] GAP-CLI-014: Context struct
- [ ] GAP-CLI-017: Client factory
- [ ] GAP-CLI-018: Modular command structure

### Low (Optional)
- [ ] GAP-CLI-004: publish/unpublish commands
- [ ] GAP-CLI-005: delete command
- [ ] GAP-CLI-019: Interactive prompts
- [ ] GAP-CLI-020: Help text improvements
- [ ] GAP-CLI-021: Short aliases
- [ ] GAP-CLI-010: Lazy loading
- [ ] GAP-CLI-015: Custom exception

---

## 11. Implementation Roadmap

### Week 1-2: Foundation
**Goal**: Resolve architectural issues and create base infrastructure

1. **Decision**: Command naming strategy
   - Option A: Rename Elixir commands (`checkpoint` → `save-checkpoint`, `run` → `sample`)
   - Option B: Add subcommand structure (`checkpoint create`, `checkpoint list`, `run sample`, `run list`)
   - **Recommendation**: Option B (matches Python structure, extensible)

2. **Create Output System**:
   ```elixir
   # lib/tinkex/cli/output.ex
   defmodule Tinkex.CLI.Output do
     @callback to_map(t()) :: map()
     @callback to_table(t()) :: {[String.t()], [[String.t()]]}

     def print(output, format) when format in [:table, :json]
   end

   # lib/tinkex/cli/output/checkpoint_list.ex
   defmodule Tinkex.CLI.Output.CheckpointList do
     @behaviour Tinkex.CLI.Output
     defstruct [:checkpoints, :run_id, :total_count, :shown_count]
   end
   ```

3. **Create Formatter Module**:
   ```elixir
   # lib/tinkex/cli/formatter.ex
   defmodule Tinkex.CLI.Formatter do
     def format_size(bytes)
     def format_timestamp(%DateTime{})
     def format_bool(boolean)
     def format_optional(value, formatter \\ nil)
   end
   ```

### Week 3-4: Core Commands
**Goal**: Implement critical list/info commands

4. **Add checkpoint list**:
   - Call `RestClient.list_user_checkpoints/1`
   - Implement pagination
   - Format output with new output system

5. **Add checkpoint info**:
   - Parse tinker:// paths
   - Fetch checkpoint details
   - Format property table

6. **Add run list**:
   - Call `RestClient.list_training_runs/1`
   - Implement pagination
   - Format output table

7. **Add run info**:
   - Fetch training run details
   - Display nested checkpoint info
   - Show user metadata

### Week 5-6: User Experience
**Goal**: Improve output and error handling

8. **Integrate TableRex** for rich tables
9. **Add progress bars** (ProgressBar library or custom)
10. **Create error handler macro**
11. **Add global --format flag**

### Week 7-8: Remaining Commands
**Goal**: Complete command parity

12. **Add checkpoint download** (HTTP + tar extraction)
13. **Add checkpoint publish/unpublish**
14. **Add checkpoint delete** (with confirmation)
15. **Split into modular structure**

---

## 12. File Structure Recommendation

### Proposed Elixir Structure
```
lib/tinkex/cli/
├── cli.ex                    # Main entry point & dispatcher
├── context.ex                # %Context{format: :table | :json, ...}
├── formatter.ex              # Formatting utilities
├── error_handler.ex          # @handle_api_errors macro
├── client.ex                 # create_rest_client/1
├── output/
│   ├── output.ex             # Behaviour definition
│   ├── checkpoint_list.ex
│   ├── checkpoint_info.ex
│   ├── checkpoint_download.ex
│   ├── run_list.ex
│   └── run_info.ex
└── commands/
    ├── checkpoint.ex         # All checkpoint subcommands
    ├── run.ex                # All run subcommands
    └── version.ex            # Version command
```

### Benefits
- Clear separation of concerns
- Easy to find and modify commands
- Independently testable modules
- Parallel development friendly
- Matches Python structure

---

## 13. Dependencies Needed

### Elixir Libraries
1. **TableRex** (~> 3.0) - Rich table rendering
   ```elixir
   {:table_rex, "~> 3.0"}
   ```

2. **ProgressBar** (~> 3.0) - Terminal progress bars
   ```elixir
   {:progress_bar, "~> 3.0"}
   ```

3. **Timex** (~> 3.7) - Relative time formatting
   ```elixir
   {:timex, "~> 3.7"}
   ```

4. **Optimus** (optional) - Better argument parsing
   ```elixir
   {:optimus, "~> 0.2"}
   ```

### Already Available
- Jason (JSON encoding)
- Finch (HTTP client)
- Tinkex.Error (error handling)

---

## 14. Testing Strategy

### Unit Tests
- Test each output module independently
- Test formatter functions with edge cases
- Test error handler macro
- Test client factory

### Integration Tests
- Test full command workflows
- Test argument parsing
- Test error scenarios
- Test output formats (table vs JSON)

### End-to-End Tests
- Test actual API calls (with mocks)
- Test pagination logic
- Test download/extraction
- Test interactive prompts

---

## 15. Migration Path

For users transitioning from Python to Elixir:

### Breaking Changes
1. Command names changed (if Option B chosen):
   - `tinker checkpoint <path>` → `tinkex checkpoint info <path>`
   - Add new `tinkex checkpoint create` for current Elixir checkpoint
   - `tinker run <id>` → `tinkex run info <id>`
   - Add new `tinkex run sample` for current Elixir run

2. Option changes:
   - Global `--format` replaces per-command `--json`
   - Consistent short flags across commands

### Compatibility Notes
- JSON output format should match Python exactly
- Tinker paths (`tinker://`) are universal
- API client behavior is identical

---

## 16. Documentation Requirements

### User Documentation
1. **CLI Reference**: Complete command reference with examples
2. **Migration Guide**: Python → Elixir CLI differences
3. **Tutorial**: Common workflows (list runs, download checkpoints, etc.)
4. **FAQ**: Common questions and troubleshooting

### Developer Documentation
1. **Architecture**: Output system, error handling, context
2. **Adding Commands**: How to add new commands/subcommands
3. **Testing**: How to test CLI commands
4. **Contributing**: Guidelines for CLI contributions

---

## Appendix A: Python CLI File Sizes

| File | Lines | Purpose |
|------|-------|---------|
| `__main__.py` | 61 | Entry point with LazyGroup |
| `client.py` | 158 | REST client creation & error decorator |
| `context.py` | 24 | CLIContext dataclass |
| `exceptions.py` | 32 | TinkerCliError exception |
| `lazy_group.py` | 90 | LazyGroup for lazy loading |
| `output.py` | 228 | OutputBase + formatting utilities |
| `commands/__init__.py` | 2 | Package marker |
| `commands/checkpoint.py` | 651 | 7 checkpoint subcommands |
| `commands/run.py` | 258 | 2 run subcommands |
| `commands/version.py` | 19 | Version command |
| **TOTAL** | **1,523** | **10 files** |

---

## Appendix B: Elixir CLI File Sizes

| File | Lines | Purpose |
|------|-------|---------|
| `cli.ex` | 1,013 | All CLI logic |
| **TOTAL** | **1,013** | **1 file** |

---

## Appendix C: Command Matrix

| Category | Python Commands | Elixir Commands | Gap |
|----------|----------------|-----------------|-----|
| **Checkpoint Management** | list, info, download, publish, unpublish, delete | None | 6 commands missing |
| **Checkpoint Creation** | None | checkpoint | 1 extra command |
| **Run Management** | list, info | None | 2 commands missing |
| **Run Execution** | None | run | 1 extra command |
| **Version** | version | version | Parity |
| **TOTAL** | 10 subcommands | 3 commands | 8 gaps |

---

## Summary

The Python tinker CLI is a comprehensive, well-architected command-line tool with rich output, extensive error handling, and complete checkpoint/run management capabilities. The Elixir tinkex CLI is a basic escript focused on execution (checkpoint creation, text sampling) rather than management.

**Key Takeaways**:
1. **~35% completeness** - Only version command has parity
2. **12 critical gaps** - Missing core commands and architecture
3. **Semantic mismatch** - Commands have same names but different purposes
4. **Output gap** - No table rendering or formatting utilities
5. **Modular vs monolithic** - Python is modular (10 files), Elixir is monolithic (1 file)

**Recommended Next Steps**:
1. Decide on command naming strategy (subcommand structure recommended)
2. Implement output abstraction layer
3. Add checkpoint/run management commands
4. Improve error handling and formatting
5. Split into modular structure

**Estimated Effort**: 6-8 weeks for full parity with Python CLI.
