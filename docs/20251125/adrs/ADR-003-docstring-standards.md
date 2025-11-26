# ADR-003: Documentation String Standards

**Status:** Proposed
**Date:** 2025-11-25
**Decision Makers:** TBD
**Technical Story:** Aligning TinKex documentation with Python SDK quality standards

## Context

The Python Tinker SDK commits standardized documentation formatting across all public interfaces:
- Comprehensive class/method docstrings
- Consistent formatting with bullet points
- Code examples in all docs
- Parameter/return type documentation

TinKex should adopt equivalent documentation standards while following Elixir conventions.

## Decision Drivers

1. **Developer Experience** - Clear documentation helps users adopt the SDK
2. **API Discoverability** - Good docs enable IDE autocomplete preview
3. **Consistency** - Uniform style across all modules
4. **Elixir Conventions** - Follow community standards
5. **ExDoc Compatibility** - Render correctly in generated docs

## Python Format (After Standardization)

```python
def method(self, param: Type) -> ReturnType:
    """Short description.

    Longer description if needed.

    Args:
    - `param`: Description of param

    Returns:
    - `ReturnType` with description

    Raises:
        SomeException: When something goes wrong

    Example:
    ```python
    result = client.method("value")
    print(result)
    ```
    """
```

## Decision: Elixir Documentation Standards

### Module Documentation (@moduledoc)

```elixir
defmodule Tinkex.Module do
  @moduledoc """
  Short description of the module.

  Longer description with context and usage information. Explain what
  this module provides and when developers should use it.

  ## Overview

  Brief overview of capabilities.

  ## Usage

  High-level usage pattern:

      client = Module.create(opts)
      result = Module.do_something(client, params)

  ## Configuration

  If applicable, describe configuration options.

  ## Examples

      iex> {:ok, client} = Module.create()
      iex> Module.do_something(client, "param")
      {:ok, %Result{}}

  ## See Also

  - `Tinkex.RelatedModule` - For related functionality
  - `Tinkex.Types.SomeType` - Type definitions
  """
end
```

### Function Documentation (@doc)

```elixir
@doc """
Short description of what the function does.

Longer description if needed. Explain the purpose, behavior,
and any important details.

## Parameters

- `client` - The client instance
- `param` - Description of the parameter
- `opts` - Optional keyword list:
  - `:option1` - Description (default: `value`)
  - `:option2` - Description (default: `nil`)

## Returns

Description of return value. Use tagged tuples:
- `{:ok, result}` - When operation succeeds
- `{:error, reason}` - When operation fails

For specific success types:
- `{:ok, %SomeType{}}` - With the resulting struct

For specific error types:
- `{:error, :not_found}` - When resource doesn't exist
- `{:error, %APIError{}}` - When API returns an error

## Examples

    iex> {:ok, result} = Module.function(client, "value")
    iex> result.field
    "expected"

    iex> Module.function(client, "invalid")
    {:error, :invalid_input}

## Notes

Any additional information, caveats, or tips.
"""
@spec function(client(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
def function(client, param, opts \\ []) do
  # ...
end
```

### Type Documentation (@moduledoc for type modules)

```elixir
defmodule Tinkex.Types.SomeType do
  @moduledoc """
  Description of what this type represents.

  Mirrors Python `tinker.types.SomeType`.

  ## Fields

  - `field1` - Description of field1
  - `field2` - Description of field2 (optional, default: `nil`)

  ## Wire Format

  JSON representation sent over the wire:

  ```json
  {
    "field1": "value",
    "field2": 123
  }
  ```

  ## Examples

      iex> type = %SomeType{field1: "value", field2: 123}
      iex> Jason.encode!(type)
      ~s({"field1":"value","field2":123})

  ## See Also

  - `Tinkex.Types.RelatedType`
  """
end
```

## Formatting Rules

### 1. Section Headers

Use `## Header` for major sections:
- `## Parameters`
- `## Returns`
- `## Examples`
- `## Errors`
- `## Notes`
- `## See Also`

### 2. Parameter Lists

Use dash-prefixed lists with backticks for parameter names:
```elixir
## Parameters

- `param1` - Description
- `param2` - Description with `type reference`
```

### 3. Return Values

Describe using tagged tuple format:
```elixir
## Returns

- `{:ok, %Type{}}` - On success with result
- `{:error, reason}` - On failure
```

### 4. Code Examples

Use 4-space indented code blocks for IEx examples:
```elixir
## Examples

    iex> result = function(arg)
    iex> result.field
    "value"
```

### 5. Cross-References

Use ExDoc link format:
- Module: `Tinkex.Module`
- Function: `function/2`
- Type: `t:Tinkex.Types.Type.t/0`

### 6. Wire Format

For types, include JSON wire format:
```elixir
## Wire Format

```json
{"field": "value"}
```
```

## Implementation Checklist

### Public API Modules

- [ ] `Tinkex` - Main module
- [ ] `Tinkex.API.Service` - ServiceClient equivalent
- [ ] `Tinkex.API.Training` - TrainingClient equivalent
- [ ] `Tinkex.API.Sampling` - SamplingClient equivalent
- [ ] `Tinkex.API.Rest` - RestClient equivalent
- [ ] `Tinkex.Future` - APIFuture equivalent

### Type Modules (Priority)

- [ ] `Tinkex.Types.WeightsInfoResponse` (NEW)
- [ ] `Tinkex.Types.GetSamplerResponse` (NEW)
- [ ] `Tinkex.Types.LossFnType` (UPDATE)
- [ ] `Tinkex.Types.ImageChunk` (UPDATE)
- [ ] `Tinkex.Types.LoadWeightsRequest` (UPDATE)

### Type Modules (Complete Review)

All type modules should have:
- [ ] @moduledoc with fields list
- [ ] Wire format example
- [ ] Usage examples

## Consequences

### Positive
- Consistent documentation across codebase
- Better developer experience
- IDE autocomplete with doc preview
- Professional library appearance

### Negative
- Time investment to update all modules
- Requires ongoing maintenance
- May differ from some Python phrasings

### Neutral
- Follows Elixir conventions (different from Python)
- ExDoc generates navigation automatically

## Validation

Run `mix docs` and verify:
1. No warnings about missing docs
2. Examples render correctly
3. Cross-references resolve
4. Navigation is logical

## Links

- [ExDoc Writing Documentation](https://hexdocs.pm/ex_doc/readme.html)
- [Elixir Documentation Guidelines](https://hexdocs.pm/elixir/writing-documentation.html)
- [ELIXIR_MAPPING.md](../ELIXIR_MAPPING.md) - Python to Elixir format mapping
