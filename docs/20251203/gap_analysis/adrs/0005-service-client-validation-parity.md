# ADR 0005: Match ServiceClient validation to Python

Status: Proposed  
Date: 2025-12-03

## Context
- Python ServiceClient enforces that `create_sampling_client` must receive either `model_path` or `base_model` and requires at least one of the LoRA train flags when creating training clients (`tinker/src/tinker/lib/public_interfaces/service_client.py:102-114`, `343-379`).
- Elixir `Tinkex.ServiceClient` currently skips both validations (`lib/tinkex/service_client.ex:358-379`, `496-531`), allowing invalid configs that Python would fail fast.
- This parity gap can lead to runtime errors deeper in the stack and inconsistent developer experience across SDKs.

## Decision
- Add validation in Elixir to require `model_path` or `base_model` for sampling creation and to assert at least one of `train_mlp/train_attn/train_unembed` is true for training creation.
- Return clear `{:error, %Tinkex.Error{type: :validation}}` tuples rather than letting invalid requests proceed.

## Consequences
- Aligns preflight validation with Python, improving predictability and error messaging.
- Slightly stricter behavior; some previously accepted calls will now fail fast with explicit errors.

## Alternatives considered
- Keep permissive behavior and document differences: rejected to maintain parity and reduce downstream failures.
