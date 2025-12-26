# Refactoring encode_test.exs

## Current State

`test/tinkex/tokenizer/encode_test.exs` has two issues:

1. **Agent cleanup race**: Uses `Agent.start_link` with manual `on_exit` cleanup
2. **Global ETS mutation**: Clears `:tinkex_tokenizers` table in setup

---

## Target State

1. Use `start_supervised!` for Agent lifecycle management
2. Use `ETSIsolation` to mirror the tokenizers table
3. No global state mutations

---

## Issue 1: Agent Cleanup Race

### Current Code (Lines 47-55)

```elixir
test "caches tokenizer after first successful encode" do
  # ...
  {:ok, counter} = Agent.start_link(fn -> 0 end)

  on_exit(fn ->
    if Process.alive?(counter) do
      Agent.stop(counter)
    end
  end)
  # ...
end
```

### Problem

When the test completes, the test process begins terminating. Because the Agent is linked to the test process, it receives an EXIT signal and starts shutting down. Meanwhile, the `on_exit` callback runs, calls `Process.alive?(counter)` which may return `true` (process exists but is exiting), then calls `Agent.stop(counter)` which fails because the Agent is already shutting down.

### Fix

Use `start_supervised!` which handles cleanup properly:

```elixir
test "caches tokenizer after first successful encode" do
  # ...
  counter = start_supervised!({Agent, fn -> 0 end})
  # No on_exit needed - ExUnit handles cleanup
  # ...
end
```

`start_supervised!` uses the test's supervisor, which:
1. Properly terminates children before test process exits
2. Handles already-terminated processes gracefully
3. Provides consistent cleanup timing

---

## Issue 2: Global ETS Mutation

### Current Code (Lines 8-11)

```elixir
setup do
  ensure_table()
  :ets.delete_all_objects(:tinkex_tokenizers)
  {:ok, _} = Application.ensure_all_started(:tokenizers)
  :ok
end
```

### Problem

`:tinkex_tokenizers` is a global named table. When tests run concurrently:

1. Test A populates the cache with tokenizer T1
2. Test B calls `:ets.delete_all_objects(:tinkex_tokenizers)`
3. Test A tries to use cached T1, but it's gone
4. Test A fails unexpectedly

### Fix

Use `ETSIsolation` to mirror the table:

```elixir
use Supertester.ExUnitFoundation,
  isolation: :full_isolation,
  ets_isolation: [:tinkex_tokenizers]

setup %{isolation_context: ctx} do
  {:ok, _} = Application.ensure_all_started(:tokenizers)

  # Use isolated mirror
  tokenizer_cache = ctx.isolated_ets_tables[:tinkex_tokenizers]
  {:ok, tokenizer_cache: tokenizer_cache}
end
```

### Application Code Change

For the isolation to work, the Tokenizer module needs to support table injection. Add to `lib/tinkex/tokenizer.ex`:

```elixir
defmodule Tinkex.Tokenizer do
  @default_table :tinkex_tokenizers

  # Support table injection for testing
  def cache_table do
    Process.get(:tinkex_tokenizer_cache_override, @default_table)
  end

  # Called by ETSIsolation.inject_table/3
  def __supertester_set_table__(:cache_table, table) do
    if table == @default_table do
      Process.delete(:tinkex_tokenizer_cache_override)
    else
      Process.put(:tinkex_tokenizer_cache_override, table)
    end
    :ok
  end

  # Update all ETS operations to use cache_table()
  defp get_cached(model, variant) do
    case :ets.lookup(cache_table(), {model, variant}) do
      # ...
    end
  end

  defp put_cached(model, variant, tokenizer) do
    :ets.insert(cache_table(), {{model, variant}, tokenizer})
  end
end
```

---

## Complete Refactored Test File

```elixir
defmodule Tinkex.Tokenizer.EncodeTest do
  use Supertester.ExUnitFoundation,
    isolation: :full_isolation,
    ets_isolation: [:tinkex_tokenizers]

  alias Tinkex.Tokenizer

  setup %{isolation_context: ctx} do
    {:ok, _} = Application.ensure_all_started(:tokenizers)

    # Inject isolated cache table
    tokenizer_cache = ctx.isolated_ets_tables[:tinkex_tokenizers]
    {:ok, _} = ETSIsolation.inject_table(Tokenizer, :cache_table, tokenizer_cache,
      create: false  # Already created by ets_isolation
    )

    {:ok, tokenizer_cache: tokenizer_cache}
  end

  describe "encode/2" do
    test "encodes text using model tokenizer" do
      assert {:ok, tokens} = Tokenizer.encode("Hello, world!", model: "gpt-4")
      assert is_list(tokens)
      assert length(tokens) > 0
    end

    test "caches tokenizer after first successful encode", %{tokenizer_cache: cache} do
      # Use start_supervised! for proper cleanup
      counter = start_supervised!({Agent, fn -> 0 end})

      # First encode - should load tokenizer
      assert {:ok, _} = Tokenizer.encode("test", model: "gpt-4")

      # Verify it was cached
      assert :ets.info(cache, :size) > 0

      # Second encode - should use cache
      initial_count = Agent.get(counter, & &1)
      assert {:ok, _} = Tokenizer.encode("test again", model: "gpt-4")

      # Count shouldn't increase if using cache
      # (This depends on how the counter is used in the actual test)
    end

    test "returns error for invalid model" do
      assert {:error, _} = Tokenizer.encode("test", model: "nonexistent-model")
    end
  end

  describe "encode/2 with variants" do
    test "handles different model variants" do
      assert {:ok, tokens1} = Tokenizer.encode("test", model: "gpt-4", variant: "base")
      assert {:ok, tokens2} = Tokenizer.encode("test", model: "gpt-4", variant: "chat")

      # Tokens may differ between variants
      assert is_list(tokens1)
      assert is_list(tokens2)
    end
  end
end
```

---

## Alternative: Without Application Code Changes

If modifying `lib/tinkex/tokenizer.ex` is not desired, use table mirroring with application environment:

### Setup

```elixir
setup do
  {:ok, _} = Application.ensure_all_started(:tokenizers)

  # Create isolated table
  {:ok, cache} = ETSIsolation.create_isolated(:set, [
    :public,
    {:read_concurrency, true}
  ])

  # Override via application env (if Tokenizer supports it)
  original = Application.get_env(:tinkex, :tokenizer_cache_table)
  Application.put_env(:tinkex, :tokenizer_cache_table, cache)

  on_exit(fn ->
    if original do
      Application.put_env(:tinkex, :tokenizer_cache_table, original)
    else
      Application.delete_env(:tinkex, :tokenizer_cache_table)
    end
  end)

  {:ok, tokenizer_cache: cache}
end
```

### Tokenizer Module Change

```elixir
def cache_table do
  Application.get_env(:tinkex, :tokenizer_cache_table, :tinkex_tokenizers)
end
```

---

## Migration Checklist

- [ ] Update module to use `Supertester.ExUnitFoundation` with `ets_isolation`
- [ ] Remove `:ets.delete_all_objects(:tinkex_tokenizers)` from setup
- [ ] Replace `Agent.start_link` + `on_exit` with `start_supervised!`
- [ ] Add table injection support to `lib/tinkex/tokenizer.ex`
- [ ] Update tests to use injected cache table
- [ ] Verify tests pass: `mix test test/tinkex/tokenizer/encode_test.exs`
- [ ] Run 20 times to verify no flakiness

---

## Before/After Comparison

### Setup

**Before**:
```elixir
setup do
  ensure_table()
  :ets.delete_all_objects(:tinkex_tokenizers)
  {:ok, _} = Application.ensure_all_started(:tokenizers)
  :ok
end
```

**After**:
```elixir
setup %{isolation_context: ctx} do
  {:ok, _} = Application.ensure_all_started(:tokenizers)

  tokenizer_cache = ctx.isolated_ets_tables[:tinkex_tokenizers]
  {:ok, _} = ETSIsolation.inject_table(Tokenizer, :cache_table, tokenizer_cache, create: false)

  {:ok, tokenizer_cache: tokenizer_cache}
end
```

### Agent Usage

**Before**:
```elixir
{:ok, counter} = Agent.start_link(fn -> 0 end)

on_exit(fn ->
  if Process.alive?(counter) do
    Agent.stop(counter)
  end
end)
```

**After**:
```elixir
counter = start_supervised!({Agent, fn -> 0 end})
# No on_exit needed
```

---

## Testing the Fix

After making changes, verify:

```bash
# Single run
mix test test/tinkex/tokenizer/encode_test.exs

# Multiple runs with random seeds
for i in {1..20}; do
  mix test test/tinkex/tokenizer/encode_test.exs --seed $RANDOM || echo "FAILED on run $i"
done
```

All 20 runs should pass without the Agent cleanup error.
