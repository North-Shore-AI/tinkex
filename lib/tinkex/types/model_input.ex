defmodule Tinkex.Types.ModelInput do
  @moduledoc """
  Model input containing chunks of encoded text and/or images.

  Mirrors Python tinker.types.ModelInput.
  """

  alias Tinkex.Types.EncodedTextChunk
  alias Tinkex.{Error, Tokenizer}

  @derive {Jason.Encoder, only: [:chunks]}
  defstruct chunks: []

  @type chunk ::
          EncodedTextChunk.t()
          | Tinkex.Types.ImageChunk.t()
          | Tinkex.Types.ImageAssetPointerChunk.t()
  @type t :: %__MODULE__{
          chunks: [chunk()]
        }

  @doc """
  Create ModelInput from a list of token IDs.
  """
  @spec from_ints([integer()]) :: t()
  def from_ints(tokens) when is_list(tokens) do
    %__MODULE__{
      chunks: [%EncodedTextChunk{tokens: tokens, type: "encoded_text"}]
    }
  end

  @doc """
  Create ModelInput from raw text.

  Tokenizes the provided `text` via `Tinkex.Tokenizer.encode/3` and returns a
  tuple using the same `{:ok, ...} | {:error, ...}` contract. Chat templates
  are **not** applied; callers must supply fully formatted prompts.

  ## Options

    * `:model_name` (required) - Model name used to resolve the tokenizer.
    * `:training_client` - Forwarded to tokenizer resolution.
    * Any other options supported by `Tinkex.Tokenizer.encode/3`.
  """
  @spec from_text(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def from_text(text, opts \\ []) do
    with :ok <- validate_opts(opts),
         {:ok, model_name} <- fetch_model_name(opts),
         {:ok, tokens} <- Tokenizer.encode(text, model_name, opts) do
      {:ok,
       %__MODULE__{
         chunks: [%EncodedTextChunk{tokens: tokens, type: "encoded_text"}]
       }}
    end
  end

  @doc """
  Create ModelInput from raw text, raising on failure.

  See `from_text/2` for options and behavior.
  """
  @spec from_text!(String.t(), keyword()) :: t()
  def from_text!(text, opts \\ []) do
    case from_text(text, opts) do
      {:ok, model_input} ->
        model_input

      {:error, %Error{} = error} ->
        raise ArgumentError, Error.format(error)
    end
  end

  @doc """
  Extract all token IDs from the ModelInput.

  Only works with EncodedTextChunk chunks. Raises for image chunks.
  """
  @spec to_ints(t()) :: [integer()]
  def to_ints(%__MODULE__{chunks: chunks}) do
    Enum.flat_map(chunks, fn
      %EncodedTextChunk{tokens: tokens} -> tokens
      _ -> raise ArgumentError, "Cannot convert non-text chunk to ints"
    end)
  end

  @doc """
  Get the total length (token count) of the ModelInput.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{chunks: chunks}) do
    Enum.sum(Enum.map(chunks, &chunk_length/1))
  end

  defp chunk_length(%EncodedTextChunk{} = chunk), do: EncodedTextChunk.length(chunk)
  defp chunk_length(%Tinkex.Types.ImageChunk{} = chunk), do: Tinkex.Types.ImageChunk.length(chunk)

  defp chunk_length(%Tinkex.Types.ImageAssetPointerChunk{} = chunk),
    do: Tinkex.Types.ImageAssetPointerChunk.length(chunk)

  defp validate_opts(opts) do
    cond do
      is_list(opts) and Keyword.keyword?(opts) ->
        :ok

      true ->
        {:error, Error.new(:validation, "options must be a keyword list, got: #{inspect(opts)}")}
    end
  end

  defp fetch_model_name(opts) do
    case Keyword.fetch(opts, :model_name) do
      {:ok, model_name} when is_binary(model_name) ->
        {:ok, model_name}

      {:ok, other} ->
        {:error, Error.new(:validation, "model_name must be a binary, got: #{inspect(other)}")}

      :error ->
        {:error, Error.new(:validation, "model_name is required to encode text")}
    end
  end
end
