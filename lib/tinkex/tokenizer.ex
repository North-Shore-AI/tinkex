defmodule Tinkex.Tokenizer do
  @moduledoc """
  Tokenization entrypoint for the Tinkex SDK.

  This module will wrap the HuggingFace `tokenizers` NIF, resolve tokenizer IDs
  (TrainingClient metadata + Llama-3 hack), and coordinate caching strategy via
  ETS handles. Tokenizers are keyed by the resolved tokenizer ID and reused
  across calls to avoid repeated downloads.
  """

  alias Tokenizers.{Encoding, Tokenizer}
  alias Tinkex.{Error, TrainingClient}

  @tokenizer_table :tinkex_tokenizers
  @llama3_tokenizer "baseten/Meta-Llama-3-tokenizer"

  @typedoc "Identifier for a tokenizer (e.g., HuggingFace repo name)."
  @type tokenizer_id :: String.t()

  @doc """
  Resolve the tokenizer ID for the given model.

  - If a `training_client` is provided, attempts to fetch `model_data.tokenizer_id`
    via the provided `:info_fun` (defaults to `&TrainingClient.get_info/1`).
  - Applies the Llama-3 gating workaround (`"baseten/Meta-Llama-3-tokenizer"`).
  - Falls back to the provided `model_name`.
  """
  @spec get_tokenizer_id(String.t(), Tinkex.TrainingClient.t() | nil, keyword()) :: tokenizer_id()
  def get_tokenizer_id(model_name, training_client \\ nil, opts \\ [])

  def get_tokenizer_id(model_name, training_client, opts) when not is_binary(model_name) do
    model_name
    |> to_string()
    |> get_tokenizer_id(training_client, opts)
  end

  def get_tokenizer_id(model_name, training_client, opts) do
    case fetch_tokenizer_id_from_client(training_client, opts) do
      {:ok, tokenizer_id} -> tokenizer_id
      _ -> apply_tokenizer_heuristics(model_name)
    end
  end

  @doc """
  Get a tokenizer handle from cache or load and cache it using the resolved ID.

  The ETS table `#{inspect(@tokenizer_table)}` is created on demand if the
  application has not already started it.
  """
  @spec get_or_load_tokenizer(tokenizer_id(), keyword()) ::
          {:ok, Tokenizer.t()} | {:error, Error.t()}
  def get_or_load_tokenizer(tokenizer_id, opts \\ [])

  def get_or_load_tokenizer(tokenizer_id, _opts) when not is_binary(tokenizer_id) do
    {:error, Error.new(:validation, "invalid tokenizer_id: #{inspect(tokenizer_id)}")}
  end

  def get_or_load_tokenizer(tokenizer_id, opts) do
    ensure_table!()

    case :ets.lookup(@tokenizer_table, tokenizer_id) do
      [{^tokenizer_id, tokenizer}] ->
        {:ok, tokenizer}

      [] ->
        load_fun = Keyword.get(opts, :load_fun, &Tokenizer.from_pretrained/1)

        with {:ok, tokenizer} <- load_tokenizer(load_fun, tokenizer_id),
             {:ok, cached} <- cache_tokenizer(tokenizer_id, tokenizer) do
          {:ok, cached}
        else
          {:error, %Error{} = error} ->
            {:error, error}

          {:error, reason} ->
            {:error, Error.new(:validation, format_load_error(tokenizer_id, reason))}
        end
    end
  end

  @doc """
  Encode text into token IDs using a cached tokenizer.

  Loads (or reuses) the tokenizer keyed by the resolved tokenizer ID and returns
  `{:ok, [integer()]}`.

  ## Examples

      iex> {:ok, ids} = Tinkex.Tokenizer.encode("Hello", "gpt2")
      iex> Enum.all?(ids, &is_integer/1)
      true
  """
  @spec encode(String.t(), tokenizer_id() | String.t(), keyword()) ::
          {:ok, [integer()]} | {:error, Error.t()}
  def encode(text, model_name, opts \\ [])

  def encode(text, _model_name, _opts) when not is_binary(text) do
    {:error, Error.new(:validation, "text must be a binary")}
  end

  def encode(_text, model_name, _opts) when not is_binary(model_name) do
    {:error, Error.new(:validation, "model_name must be a binary")}
  end

  def encode(text, model_name, opts) do
    tokenizer_id = get_tokenizer_id(model_name, Keyword.get(opts, :training_client), opts)

    with {:ok, tokenizer} <- get_or_load_tokenizer(tokenizer_id, opts),
         {:ok, encoding} <- Tokenizer.encode(tokenizer, text) do
      {:ok, Encoding.get_ids(encoding)}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:validation, "Failed to encode text: #{format_reason(reason)}")}
    end
  end

  @doc """
  Decode token IDs back to text using a cached tokenizer.

  Mirrors `encode/3` with the same caching and error contract.
  """
  @spec decode([integer()], tokenizer_id() | String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def decode(ids, model_name, opts \\ [])

  def decode(_ids, model_name, _opts) when not is_binary(model_name) do
    {:error, Error.new(:validation, "model_name must be a binary")}
  end

  def decode(ids, model_name, opts) do
    cond do
      not is_list(ids) ->
        {:error, Error.new(:validation, "ids must be a list of integers")}

      not Enum.all?(ids, &is_integer/1) ->
        {:error, Error.new(:validation, "ids must be integers")}

      true ->
        tokenizer_id = get_tokenizer_id(model_name, Keyword.get(opts, :training_client), opts)

        with {:ok, tokenizer} <- get_or_load_tokenizer(tokenizer_id, opts),
             {:ok, text} <- Tokenizer.decode(tokenizer, ids) do
          {:ok, text}
        else
          {:error, %Error{} = error} ->
            {:error, error}

          {:error, reason} ->
            {:error, Error.new(:validation, "Failed to decode ids: #{format_reason(reason)}")}
        end
    end
  end

  defp fetch_tokenizer_id_from_client(nil, _opts), do: :no_client

  defp fetch_tokenizer_id_from_client(training_client, opts) do
    info_fun = Keyword.get(opts, :info_fun, &TrainingClient.get_info/1)

    case safe_call_info(info_fun, training_client) do
      {:ok, %{model_data: %{tokenizer_id: id}}} when is_binary(id) -> {:ok, id}
      _ -> :no_id
    end
  end

  defp apply_tokenizer_heuristics(model_name) do
    if String.contains?(model_name, "Llama-3") do
      @llama3_tokenizer
    else
      model_name
    end
  end

  defp load_tokenizer(load_fun, tokenizer_id) do
    try do
      case load_fun.(tokenizer_id) do
        {:ok, tokenizer} -> {:ok, tokenizer}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_load_result, other}}
      end
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp cache_tokenizer(tokenizer_id, tokenizer) do
    case :ets.insert_new(@tokenizer_table, {tokenizer_id, tokenizer}) do
      true ->
        {:ok, tokenizer}

      false ->
        case :ets.lookup(@tokenizer_table, tokenizer_id) do
          [{^tokenizer_id, existing}] ->
            {:ok, existing}

          [] ->
            :ets.insert(@tokenizer_table, {tokenizer_id, tokenizer})
            {:ok, tokenizer}
        end
    end
  end

  defp ensure_table! do
    case :ets.whereis(@tokenizer_table) do
      :undefined ->
        :ets.new(@tokenizer_table, [:set, :public, :named_table, read_concurrency: true])

      _ ->
        @tokenizer_table
    end
  end

  defp safe_call_info(fun, training_client) when is_function(fun, 1) do
    try do
      fun.(training_client)
    rescue
      _ -> :error
    catch
      :exit, _ -> :error
    end
  end

  defp format_load_error(tokenizer_id, reason) do
    "Failed to load tokenizer #{tokenizer_id}: #{format_reason(reason)}"
  end

  defp format_reason(%Error{message: message}), do: message
  defp format_reason(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_reason(reason), do: inspect(reason)
end
