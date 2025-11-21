# Elixir Port Priorities for Tinker Nov 16-21 Updates

## High Priority

### 1. RestClient Session & Checkpoint APIs
```elixir
# Functions to implement in RestClient
def get_session(session_id)
def get_session_async(session_id)
def list_sessions(limit \\ 20, offset \\ 0)
def list_sessions_async(limit, offset)
def list_user_checkpoints(limit \\ 50, offset \\ 0)
def list_user_checkpoints_async(limit, offset)
```

### 2. New Types
```elixir
defmodule Tinker.Types.GetSessionResponse do
  defstruct [:training_run_ids, :sampler_ids]
end

defmodule Tinker.Types.ListSessionsResponse do
  defstruct [:sessions]
end
```

### 3. Async Client Creation Pattern
```elixir
# ServiceClient
def create_sampling_client_async(model_path, opts \\ [])

# TrainingClient
def create_sampling_client_async(model_path, opts \\ [])

# SamplingClient factory
def create(holder, opts) # Returns Task or Future
```

## Medium Priority

### 4. CLI Commands (if implementing CLI)
- `tinker run list` / `tinker run info`
- `tinker checkpoint list` / `tinker checkpoint info`
- `tinker checkpoint download` / `tinker checkpoint delete`
- `tinker version`

### 5. Checkpoint Download Logic
- Download with progress tracking
- Tar extraction
- Automatic cleanup

## Lower Priority

### 6. Internal Improvements
- Better cleanup in client holder
- Session heartbeat task ordering
- Path validation (tinker:// prefix)
- tml_tokenizers integration (optional)

---

## Quick Reference: Python → Elixir

| Python | Elixir Equivalent |
|--------|-------------------|
| `@capture_exceptions` | `with {:ok, result}` pattern |
| `async def` | `Task.async/1` |
| `APIFuture[T]` | `%Task{}` or custom Future |
| `click.group()` | `OptionParser` or `optimus` |
| `rich.Table` | `TableRex` |
| `urllib.request` | `HTTPoison` or `Req` |
| `tarfile` | `:erl_tar` |
