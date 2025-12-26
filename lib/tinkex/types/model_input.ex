defmodule Tinkex.Types.ModelInput do
  @moduledoc """
  Model input containing chunks of encoded text and/or images.

  Mirrors Python tinker.types.ModelInput.
  """

  alias Tinkex.{Error, Tokenizer}
  alias Tinkex.Types.{EncodedTextChunk, ImageAssetPointerChunk, ImageChunk}

  @derive {Jason.Encoder, only: [:chunks]}
  defstruct chunks: []

  @type chunk ::
          EncodedTextChunk.t()
          | ImageChunk.t()
          | ImageAssetPointerChunk.t()
  @type t :: %__MODULE__{
          chunks: [chunk()]
        }

  @doc """
  Create an empty ModelInput with no chunks.

  ## Examples

      iex> ModelInput.empty()
      %ModelInput{chunks: []}
  """
  @spec empty() :: t()
  def empty, do: %__MODULE__{chunks: []}

  @doc """
  Append a chunk to the ModelInput.

  Returns a new ModelInput with the given chunk appended to the end.

  ## Examples

      iex> input = ModelInput.empty()
      iex> chunk = %EncodedTextChunk{tokens: [1, 2, 3], type: "encoded_text"}
      iex> ModelInput.append(input, chunk)
      %ModelInput{chunks: [%EncodedTextChunk{tokens: [1, 2, 3], type: "encoded_text"}]}
  """
  @spec append(t(), chunk()) :: t()
  def append(%__MODULE__{chunks: chunks}, chunk) do
    %__MODULE__{chunks: chunks ++ [chunk]}
  end

  @doc """
  Append a single token to the ModelInput.

  Token-aware append: if the last chunk is an EncodedTextChunk, extends its
  tokens; otherwise adds a new EncodedTextChunk with that single token.

  ## Examples

      iex> input = ModelInput.from_ints([1, 2])
      iex> ModelInput.append_int(input, 3) |> ModelInput.to_ints()
      [1, 2, 3]

      iex> input = ModelInput.empty()
      iex> ModelInput.append_int(input, 42) |> ModelInput.to_ints()
      [42]
  """
  @spec append_int(t(), integer()) :: t()
  def append_int(%__MODULE__{chunks: []}, token) when is_integer(token) do
    %__MODULE__{chunks: [%EncodedTextChunk{tokens: [token], type: "encoded_text"}]}
  end

  def append_int(%__MODULE__{chunks: chunks}, token) when is_integer(token) do
    case List.last(chunks) do
      %EncodedTextChunk{tokens: tokens} = last ->
        updated = %{last | tokens: tokens ++ [token]}
        %__MODULE__{chunks: List.replace_at(chunks, -1, updated)}

      _other ->
        append(%__MODULE__{chunks: chunks}, %EncodedTextChunk{
          tokens: [token],
          type: "encoded_text"
        })
    end
  end

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

  For image chunks, `expected_tokens` must be set; otherwise `length/1` will
  raise to mirror Python SDK guardrails.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{chunks: chunks}) do
    Enum.sum(Enum.map(chunks, &chunk_length/1))
  end

  defp chunk_length(%EncodedTextChunk{} = chunk), do: EncodedTextChunk.length(chunk)
  defp chunk_length(%ImageChunk{} = chunk), do: ImageChunk.length(chunk)

  defp chunk_length(%ImageAssetPointerChunk{} = chunk),
    do: ImageAssetPointerChunk.length(chunk)

  defp validate_opts(opts) do
    if is_list(opts) and Keyword.keyword?(opts) do
      :ok
    else
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
