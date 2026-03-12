defmodule Tinkex.ModelInput do
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

  @doc "Create an empty ModelInput with no chunks."
  @spec empty() :: t()
  def empty, do: %__MODULE__{chunks: []}

  @doc "Append a chunk to the ModelInput."
  @spec append(t(), chunk()) :: t()
  def append(%__MODULE__{chunks: chunks}, chunk) do
    %__MODULE__{chunks: chunks ++ [chunk]}
  end

  @doc "Append a single token to the ModelInput."
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

  @doc "Create ModelInput from a list of token IDs."
  @spec from_ints([integer()]) :: t()
  def from_ints(tokens) when is_list(tokens) do
    %__MODULE__{
      chunks: [%EncodedTextChunk{tokens: tokens, type: "encoded_text"}]
    }
  end

  @doc "Create ModelInput from raw text using `Tinkex.Tokenizer.encode/3`."
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

  @doc "Create ModelInput from raw text, raising on failure."
  @spec from_text!(String.t(), keyword()) :: t()
  def from_text!(text, opts \\ []) do
    case from_text(text, opts) do
      {:ok, model_input} ->
        model_input

      {:error, %Error{} = error} ->
        raise ArgumentError, Error.format(error)
    end
  end

  @doc "Extract all token IDs from the ModelInput."
  @spec to_ints(t()) :: [integer()]
  def to_ints(%__MODULE__{chunks: chunks}) do
    Enum.flat_map(chunks, fn
      %EncodedTextChunk{tokens: tokens} -> tokens
      _ -> raise ArgumentError, "Cannot convert non-text chunk to ints"
    end)
  end

  @doc "Get the total length (token count) of the ModelInput."
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
