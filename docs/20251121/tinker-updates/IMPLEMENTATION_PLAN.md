# Tinkex Implementation Plan: Nov 16-21 Updates

## Overview

This document outlines a staged TDD implementation plan for porting all new functionality from tinker Python SDK (Nov 16-21, 2025) to tinkex Elixir.

**Approach:** Test-Driven Development with mock tests first, then live examples

---

## Implementation Stages

### Stage 1: Foundation - Types & RestClient Module
**Duration:** Core infrastructure
**Dependencies:** None

### Stage 2: Session Management APIs
**Duration:** REST endpoints
**Dependencies:** Stage 1

### Stage 3: Checkpoint Management APIs
**Duration:** REST endpoints
**Dependencies:** Stage 1

### Stage 4: Async Client Factory Pattern
**Duration:** Client refactoring
**Dependencies:** Stage 1

### Stage 5: Checkpoint Download
**Duration:** File operations
**Dependencies:** Stage 3

### Stage 6: CLI Commands (Optional)
**Duration:** User interface
**Dependencies:** Stages 1-5

---

## Stage 1: Foundation - Types & RestClient Module

### 1.1 New Types

Create new type modules in `lib/tinkex/types/`:

```elixir
# lib/tinkex/types/get_session_response.ex
defmodule Tinkex.Types.GetSessionResponse do
  @moduledoc "Response from get_session API"

  @type t :: %__MODULE__{
    training_run_ids: [String.t()],
    sampler_ids: [String.t()]
  }

  defstruct [:training_run_ids, :sampler_ids]
end

# lib/tinkex/types/list_sessions_response.ex
defmodule Tinkex.Types.ListSessionsResponse do
  @moduledoc "Response from list_sessions API"

  @type t :: %__MODULE__{
    sessions: [String.t()]
  }

  defstruct [:sessions]
end

# lib/tinkex/types/checkpoint.ex
defmodule Tinkex.Types.Checkpoint do
  @moduledoc "Checkpoint metadata"

  @type t :: %__MODULE__{
    checkpoint_id: String.t(),
    checkpoint_type: String.t(),
    tinker_path: String.t(),
    size_bytes: integer() | nil,
    public: boolean(),
    time: String.t()
  }

  defstruct [:checkpoint_id, :checkpoint_type, :tinker_path,
             :size_bytes, :public, :time]
end

# lib/tinkex/types/checkpoints_list_response.ex
defmodule Tinkex.Types.CheckpointsListResponse do
  @moduledoc "Response from list_checkpoints API"

  @type t :: %__MODULE__{
    checkpoints: [Tinkex.Types.Checkpoint.t()],
    cursor: map() | nil
  }

  defstruct [:checkpoints, :cursor]
end

# lib/tinkex/types/checkpoint_archive_url_response.ex
defmodule Tinkex.Types.CheckpointArchiveUrlResponse do
  @moduledoc "Response with download URL for checkpoint"

  @type t :: %__MODULE__{
    url: String.t()
  }

  defstruct [:url]
end
```

### 1.2 RestClient Module

Create `lib/tinkex/rest_client.ex`:

```elixir
defmodule Tinkex.RestClient do
  @moduledoc """
  REST client for synchronous Tinker API operations.

  Provides checkpoint and session management functionality.
  """

  alias Tinkex.{API, Config, Future}
  alias Tinkex.Types.{
    Checkpoint,
    CheckpointsListResponse,
    CheckpointArchiveUrlResponse,
    GetSessionResponse,
    ListSessionsResponse
  }

  @type t :: %__MODULE__{
    session_id: String.t(),
    config: Config.t()
  }

  defstruct [:session_id, :config]

  # Constructor
  def new(session_id, config) do
    %__MODULE__{session_id: session_id, config: config}
  end

  # Session APIs
  def get_session(client, session_id)
  def list_sessions(client, opts \\ [])

  # Checkpoint APIs
  def list_checkpoints(client, run_id)
  def list_user_checkpoints(client, opts \\ [])
  def get_checkpoint_archive_url(client, checkpoint_path)
  def delete_checkpoint(client, checkpoint_path)
end
```

### 1.3 REST API Module

Create `lib/tinkex/api/rest.ex`:

```elixir
defmodule Tinkex.API.Rest do
  @moduledoc "Low-level REST API endpoints"

  alias Tinkex.API

  # Session endpoints
  def get_session(config, session_id)
  def list_sessions(config, limit, offset)

  # Checkpoint endpoints
  def list_checkpoints(config, run_id)
  def list_user_checkpoints(config, limit, offset)
  def get_checkpoint_archive_url(config, checkpoint_path)
  def delete_checkpoint(config, checkpoint_path)
end
```

### 1.4 Update ServiceClient

Modify `create_rest_client/1` to return proper RestClient struct:

```elixir
def create_rest_client(pid) do
  GenServer.call(pid, :create_rest_client)
end

# In handle_call
def handle_call(:create_rest_client, _from, state) do
  client = Tinkex.RestClient.new(state.session_id, state.config)
  {:reply, {:ok, client}, state}
end
```

---

## Stage 2: Session Management APIs

### 2.1 API Implementation

In `lib/tinkex/api/rest.ex`:

```elixir
def get_session(config, session_id) do
  API.get(config, "/api/v1/sessions/#{session_id}", pool: :training)
end

def list_sessions(config, limit \\ 20, offset \\ 0) do
  params = %{limit: limit, offset: offset}
  API.get(config, "/api/v1/sessions", params: params, pool: :training)
end
```

### 2.2 RestClient Implementation

```elixir
def get_session(%__MODULE__{config: config}, session_id) do
  case API.Rest.get_session(config, session_id) do
    {:ok, data} -> {:ok, struct(GetSessionResponse, data)}
    error -> error
  end
end

def list_sessions(%__MODULE__{config: config}, opts \\ []) do
  limit = Keyword.get(opts, :limit, 20)
  offset = Keyword.get(opts, :offset, 0)

  case API.Rest.list_sessions(config, limit, offset) do
    {:ok, data} -> {:ok, struct(ListSessionsResponse, data)}
    error -> error
  end
end
```

---

## Stage 3: Checkpoint Management APIs

### 3.1 API Implementation

In `lib/tinkex/api/rest.ex`:

```elixir
def list_checkpoints(config, run_id) do
  API.get(config, "/api/v1/training_runs/#{run_id}/checkpoints", pool: :training)
end

def list_user_checkpoints(config, limit \\ 50, offset \\ 0) do
  params = %{limit: limit, offset: offset}
  API.get(config, "/api/v1/checkpoints", params: params, pool: :training)
end

def get_checkpoint_archive_url(config, checkpoint_path) do
  # Parse tinker://run-id/weights/0001 format
  encoded_path = URI.encode(checkpoint_path)
  API.get(config, "/api/v1/checkpoints/archive_url",
    params: %{tinker_path: encoded_path},
    pool: :training)
end

def delete_checkpoint(config, checkpoint_path) do
  encoded_path = URI.encode(checkpoint_path)
  API.delete(config, "/api/v1/checkpoints",
    params: %{tinker_path: encoded_path},
    pool: :training)
end
```

### 3.2 RestClient Implementation

```elixir
def list_checkpoints(%__MODULE__{config: config}, run_id) do
  case API.Rest.list_checkpoints(config, run_id) do
    {:ok, data} ->
      checkpoints = Enum.map(data["checkpoints"], &struct(Checkpoint, &1))
      {:ok, %CheckpointsListResponse{checkpoints: checkpoints, cursor: data["cursor"]}}
    error -> error
  end
end

def list_user_checkpoints(%__MODULE__{config: config}, opts \\ []) do
  limit = Keyword.get(opts, :limit, 50)
  offset = Keyword.get(opts, :offset, 0)

  case API.Rest.list_user_checkpoints(config, limit, offset) do
    {:ok, data} ->
      checkpoints = Enum.map(data["checkpoints"], &struct(Checkpoint, &1))
      {:ok, %CheckpointsListResponse{checkpoints: checkpoints, cursor: data["cursor"]}}
    error -> error
  end
end

def get_checkpoint_archive_url(%__MODULE__{config: config}, checkpoint_path) do
  case API.Rest.get_checkpoint_archive_url(config, checkpoint_path) do
    {:ok, data} -> {:ok, struct(CheckpointArchiveUrlResponse, data)}
    error -> error
  end
end

def delete_checkpoint(%__MODULE__{config: config}, checkpoint_path) do
  API.Rest.delete_checkpoint(config, checkpoint_path)
end
```

---

## Stage 4: Async Client Factory Pattern

### 4.1 SamplingClient Factory

Add to `lib/tinkex/sampling_client.ex`:

```elixir
@doc """
Create a sampling client asynchronously.

Returns a Task that resolves to {:ok, pid} | {:error, reason}
"""
def create_async(service_pid, opts \\ []) do
  Task.async(fn ->
    # This allows the sampling session creation to happen async
    Tinkex.ServiceClient.create_sampling_client(service_pid, opts)
  end)
end
```

### 4.2 ServiceClient Async Methods

Add to `lib/tinkex/service_client.ex`:

```elixir
@doc """
Create a sampling client asynchronously.

Returns a Task that resolves to {:ok, pid} | {:error, reason}
"""
def create_sampling_client_async(pid, opts \\ []) do
  Task.async(fn ->
    create_sampling_client(pid, opts)
  end)
end
```

### 4.3 TrainingClient Async Methods

Add to `lib/tinkex/training_client.ex`:

```elixir
@doc """
Create a sampling client from this training client asynchronously.
"""
def create_sampling_client_async(pid, model_path, opts \\ []) do
  Task.async(fn ->
    create_sampling_client(pid, model_path, opts)
  end)
end
```

---

## Stage 5: Checkpoint Download

### 5.1 Download Module

Create `lib/tinkex/checkpoint_download.ex`:

```elixir
defmodule Tinkex.CheckpointDownload do
  @moduledoc """
  Download and extract checkpoint archives.
  """

  alias Tinkex.RestClient

  @doc """
  Download and extract a checkpoint.

  Options:
    - :output_dir - Parent directory (default: current directory)
    - :force - Overwrite existing (default: false)
    - :progress - Progress callback fun/2 (bytes_downloaded, total_bytes)
  """
  def download(rest_client, checkpoint_path, opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, File.cwd!())
    force = Keyword.get(opts, :force, false)
    progress_fn = Keyword.get(opts, :progress)

    # Generate checkpoint ID from path
    checkpoint_id = checkpoint_path
      |> String.replace("tinker://", "")
      |> String.replace("/", "_")

    target_path = Path.join(output_dir, checkpoint_id)

    # Check existing
    with :ok <- check_target(target_path, force),
         {:ok, url_response} <- RestClient.get_checkpoint_archive_url(rest_client, checkpoint_path),
         {:ok, archive_path} <- download_archive(url_response.url, progress_fn),
         :ok <- extract_archive(archive_path, target_path) do
      File.rm(archive_path)
      {:ok, %{destination: target_path, checkpoint_path: checkpoint_path}}
    end
  end

  defp check_target(path, force) do
    if File.exists?(path) and not force do
      {:error, {:exists, path}}
    else
      if File.exists?(path), do: File.rm_rf!(path)
      :ok
    end
  end

  defp download_archive(url, progress_fn) do
    # Use :httpc or Finch for download
    # Implement progress tracking
  end

  defp extract_archive(archive_path, target_path) do
    # Use :erl_tar for extraction
    File.mkdir_p!(target_path)
    :erl_tar.extract(archive_path, [:compressed, {:cwd, target_path}])
  end
end
```

---

## Stage 6: CLI Commands (Optional)

### 6.1 CLI Module Structure

Enhance `lib/tinkex/cli.ex`:

```elixir
defmodule Tinkex.CLI do
  @moduledoc "Command-line interface for Tinkex"

  def main(args) do
    {opts, args, _} = OptionParser.parse(args,
      switches: [format: :string, help: :boolean],
      aliases: [f: :format, h: :help]
    )

    format = Keyword.get(opts, :format, "table")

    case args do
      ["version"] -> version()
      ["run", "list" | rest] -> run_list(rest, format)
      ["run", "info", run_id] -> run_info(run_id, format)
      ["checkpoint", "list" | rest] -> checkpoint_list(rest, format)
      ["checkpoint", "info", path] -> checkpoint_info(path, format)
      ["checkpoint", "download", path | rest] -> checkpoint_download(path, rest, format)
      ["checkpoint", "delete", path | rest] -> checkpoint_delete(path, rest)
      _ -> help()
    end
  end

  # Implementation of each command...
end
```

### 6.2 Add escript to mix.exs

```elixir
def project do
  [
    # ...
    escript: [main_module: Tinkex.CLI]
  ]
end
```

---

## File Summary

### New Files to Create

| Stage | File | Purpose |
|-------|------|---------|
| 1 | `lib/tinkex/types/get_session_response.ex` | Session response type |
| 1 | `lib/tinkex/types/list_sessions_response.ex` | Sessions list type |
| 1 | `lib/tinkex/types/checkpoint.ex` | Checkpoint type |
| 1 | `lib/tinkex/types/checkpoints_list_response.ex` | Checkpoints list type |
| 1 | `lib/tinkex/types/checkpoint_archive_url_response.ex` | Download URL type |
| 1 | `lib/tinkex/rest_client.ex` | RestClient module |
| 1 | `lib/tinkex/api/rest.ex` | REST API endpoints |
| 5 | `lib/tinkex/checkpoint_download.ex` | Download functionality |

### Files to Modify

| Stage | File | Changes |
|-------|------|---------|
| 1 | `lib/tinkex/service_client.ex` | Update create_rest_client |
| 4 | `lib/tinkex/sampling_client.ex` | Add create_async |
| 4 | `lib/tinkex/service_client.ex` | Add async methods |
| 4 | `lib/tinkex/training_client.ex` | Add async methods |
| 6 | `lib/tinkex/cli.ex` | Add commands |
| 6 | `mix.exs` | Add escript config |

---

## Implementation Order

1. **Week 1: Foundation**
   - [ ] Create all new type modules
   - [ ] Create RestClient module (stub)
   - [ ] Create API.Rest module (stub)
   - [ ] Write mock tests for types

2. **Week 2: Session APIs**
   - [ ] Implement get_session
   - [ ] Implement list_sessions
   - [ ] Write mock tests
   - [ ] Write live example

3. **Week 3: Checkpoint APIs**
   - [ ] Implement list_checkpoints
   - [ ] Implement list_user_checkpoints
   - [ ] Implement get_checkpoint_archive_url
   - [ ] Implement delete_checkpoint
   - [ ] Write mock tests
   - [ ] Write live examples

4. **Week 4: Async & Download**
   - [ ] Add async factory methods
   - [ ] Implement checkpoint download
   - [ ] Write mock tests
   - [ ] Write live examples

5. **Week 5: CLI (Optional)**
   - [ ] Implement CLI commands
   - [ ] Add escript configuration
   - [ ] Write integration tests

---

## Success Criteria

### Per Stage
- [ ] All mock tests pass
- [ ] No dialyzer warnings
- [ ] Documentation complete
- [ ] Live example works

### Overall
- [ ] All 35+ new tests pass
- [ ] Full parity with Python SDK new features
- [ ] Examples demonstrate all functionality
- [ ] CLI commands work (if implemented)
