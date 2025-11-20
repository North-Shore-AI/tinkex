defmodule Tinkex.Tokenizer do
  @moduledoc """
  Tokenization entrypoint for the Tinkex SDK.

  This module will wrap the HuggingFace `tokenizers` NIF, resolve tokenizer IDs
  (TrainingClient metadata + Llama-3 hack), and coordinate caching strategy
  (ETS handles if safe, or a process-owned fallback) once implemented.

  TODO:
  - Phase 5B: implement tokenizer ID resolution + caching behavior.
  - Phase 5C: add ModelInput helpers and encode/decode wiring.
  """

  @typedoc "Identifier for a tokenizer (e.g., HuggingFace repo name)."
  @type tokenizer_id :: String.t()

  @doc """
  Resolve the tokenizer ID for the given model.

  Will call into TrainingClient metadata when available, apply known hacks
  (e.g., Llama-3 → \"baseten/Meta-Llama-3-tokenizer\"), and fall back to the
  model name. Implementation lands in Phase 5B.
  """
  @spec get_tokenizer_id(String.t(), Tinkex.TrainingClient.t() | nil, keyword()) :: tokenizer_id()
  def get_tokenizer_id(model_name, _training_client \\ nil, _opts \\ []) do
    # Placeholder passthrough until Phase 5B wires full resolution logic.
    model_name
  end

  @doc """
  Encode text into token IDs using a cached tokenizer.

  Final behavior will load from ETS or a process owner (depending on NIF safety
  results) and return `{:ok, [integer()]}`. Stubbed until Phase 5B/5C.
  """
  @spec encode(String.t(), tokenizer_id() | String.t(), keyword()) ::
          {:ok, [integer()]} | {:error, term()}
  def encode(_text, _model_name, _opts \\ []) do
    {:error, :not_implemented}
  end

  @doc """
  Decode token IDs back to text using a cached tokenizer.

  Stub placeholder; implemented alongside encode/3 once decode semantics are
  finalized in Phase 5C.
  """
  @spec decode([integer()], tokenizer_id() | String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def decode(_ids, _model_name, _opts \\ []) do
    {:error, :not_implemented}
  end
end
