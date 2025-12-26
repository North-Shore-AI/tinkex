defmodule Tinkex.Tokenizer do
  @moduledoc """
  Tokenization entrypoint for the Tinkex SDK.

  This module will wrap the HuggingFace `tokenizers` NIF, resolve tokenizer IDs
  (TrainingClient metadata + Llama-3 hack), and coordinate caching strategy via
  ETS handles. Tokenizers are keyed by the resolved tokenizer ID and reused
  across calls to avoid repeated downloads. Chat templating is out of scope for
  v1.0; callers must provide fully formatted prompts/strings before encoding.
  """

  alias Tinkex.Error
  alias Tinkex.HuggingFace
  alias Tinkex.TrainingClient

  alias TiktokenEx.Encoding, as: TikEncoding
  alias TiktokenEx.Kimi, as: TikKimi

  alias Tokenizers.Encoding
  alias Tokenizers.Tokenizer

  @tokenizer_table :tinkex_tokenizers
  @cache_override_key :tinkex_tokenizer_cache_override
  @llama3_tokenizer "thinkingmachineslabinc/meta-llama-3-tokenizer"
  @kimi_tokenizer "moonshotai/Kimi-K2-Thinking"
  @kimi_revision "612681931a8c906ddb349f8ad0f582cb552189cd"

  @typedoc "Identifier for a tokenizer (e.g., HuggingFace repo name)."
  @type tokenizer_id :: String.t()

  @typedoc "Loaded tokenizer handle."
  @type handle :: Tokenizer.t() | TikEncoding.t()

  @doc """
  Return the ETS table used for tokenizer caching.

  Tests can override this via `__supertester_set_table__/2`.
  """
  @spec cache_table() :: atom() | :ets.tid()
  def cache_table do
    Process.get(@cache_override_key, @tokenizer_table)
  end

  @doc false
  @spec __supertester_set_table__(:cache_table, atom() | :ets.tid()) :: :ok
  def __supertester_set_table__(:cache_table, table) do
    if table == @tokenizer_table do
      Process.delete(@cache_override_key)
    else
      Process.put(@cache_override_key, table)
    end

    :ok
  end

  @doc """
  Resolve the tokenizer ID for the given model.

  - If a `training_client` is provided, attempts to fetch `model_data.tokenizer_id`
    via the provided `:info_fun` (defaults to `&TrainingClient.get_info/1`).
  - Applies the Llama-3 gating workaround (`"thinkingmachineslabinc/meta-llama-3-tokenizer"`).
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
          {:ok, handle()} | {:error, Error.t()}
  def get_or_load_tokenizer(tokenizer_id, opts \\ [])

  def get_or_load_tokenizer(tokenizer_id, _opts) when not is_binary(tokenizer_id) do
    {:error, Error.new(:validation, "invalid tokenizer_id: #{inspect(tokenizer_id)}")}
  end

  def get_or_load_tokenizer(tokenizer_id, opts) do
    table = ensure_table!()

    case :ets.lookup(table, tokenizer_id) do
      [{^tokenizer_id, tokenizer}] ->
        {:ok, tokenizer}

      [] ->
        load_fun = Keyword.get(opts, :load_fun)

        with {:ok, tokenizer} <- load_tokenizer_handle(tokenizer_id, load_fun, opts),
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

  defp default_load_fun(id, opts), do: Tokenizer.from_pretrained(id, opts)

  defp load_tokenizer_handle(tokenizer_id, nil, opts) do
    if kimi_tokenizer?(tokenizer_id) do
      load_kimi_encoding(tokenizer_id, opts)
    else
      load_fun = &default_load_fun/2
      load_opts = tokenizer_load_opts(tokenizer_id)
      load_tokenizer(load_fun, tokenizer_id, load_opts)
    end
  end

  defp load_tokenizer_handle(tokenizer_id, load_fun, _opts) when is_function(load_fun, 2) do
    load_opts = tokenizer_load_opts(tokenizer_id)
    load_tokenizer(load_fun, tokenizer_id, load_opts)
  end

  defp load_tokenizer_handle(_tokenizer_id, load_fun, _opts) do
    {:error, Error.new(:validation, "invalid load_fun: #{inspect(load_fun)}")}
  end

  defp tokenizer_load_opts(@kimi_tokenizer),
    do: [revision: @kimi_revision, http_client: {Tinkex.Tokenizer.HTTPClient, []}]

  defp tokenizer_load_opts(_), do: [http_client: {Tinkex.Tokenizer.HTTPClient, []}]

  defp kimi_tokenizer?(tokenizer_id) when tokenizer_id == @kimi_tokenizer, do: true
  defp kimi_tokenizer?(_tokenizer_id), do: false

  defp load_kimi_encoding(tokenizer_id, opts) do
    revision = Keyword.get(opts, :revision, @kimi_revision)

    with {:ok, model_path} <- resolve_kimi_file(tokenizer_id, revision, "tiktoken.model", opts),
         {:ok, config_path} <-
           resolve_kimi_file(tokenizer_id, revision, "tokenizer_config.json", opts),
         {:ok, encoding} <- build_kimi_encoding(model_path, config_path, opts) do
      {:ok, encoding}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.new(:validation, "Failed to load Kimi tokenizer: #{format_reason(reason)}")}
    end
  end

  defp resolve_kimi_file(repo_id, revision, "tiktoken.model", opts) do
    case Keyword.get(opts, :tiktoken_model_path) do
      path when is_binary(path) -> {:ok, path}
      _ -> HuggingFace.resolve_file(repo_id, revision, "tiktoken.model", opts)
    end
  end

  defp resolve_kimi_file(repo_id, revision, "tokenizer_config.json", opts) do
    case Keyword.get(opts, :tokenizer_config_path) do
      path when is_binary(path) ->
        {:ok, path}

      _ ->
        HuggingFace.resolve_file(repo_id, revision, "tokenizer_config.json", opts)
    end
  end

  defp build_kimi_encoding(model_path, config_path, opts) do
    kimi_opts =
      [
        tiktoken_model_path: model_path,
        tokenizer_config_path: config_path
      ]
      |> maybe_put_opt(:pat_str, Keyword.get(opts, :pat_str))
      |> maybe_put_opt(:special_token_matching, Keyword.get(opts, :special_token_matching))

    TikKimi.from_hf_files(kimi_opts)
  end

  defp maybe_put_opt(keyword, _key, nil), do: keyword
  defp maybe_put_opt(keyword, key, value), do: Keyword.put(keyword, key, value)

  @doc """
  Encode text into token IDs using a cached tokenizer.

  Loads (or reuses) the tokenizer keyed by the resolved tokenizer ID and returns
  `{:ok, [integer()]}`. Does not apply chat templates; pass the already
  formatted string you want to tokenize.

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
         {:ok, ids} <- encode_with_tokenizer(tokenizer, text, opts) do
      {:ok, ids}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Error.new(:validation, "Failed to encode text: #{format_reason(reason)}")}
    end
  end

  @doc """
  Convenience alias for `encode/3`.

  Accepts the same options and returns the same tuple contract. Useful for
  user-facing API symmetry with `Tinkex.Types.ModelInput.from_text/2`.
  """
  @spec encode_text(String.t(), tokenizer_id() | String.t(), keyword()) ::
          {:ok, [integer()]} | {:error, Error.t()}
  def encode_text(text, model_name, opts \\ []) do
    encode(text, model_name, opts)
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
             {:ok, text} <- decode_with_tokenizer(tokenizer, ids) do
          {:ok, text}
        else
          {:error, %Error{} = error} ->
            {:error, error}

          {:error, reason} ->
            {:error, Error.new(:validation, "Failed to decode ids: #{format_reason(reason)}")}
        end
    end
  end

  defp encode_with_tokenizer(%TikEncoding{} = encoding, text, opts) do
    allow_special_tokens = Keyword.get(opts, :allow_special_tokens, true)
    TikEncoding.encode(encoding, text, allow_special_tokens: allow_special_tokens)
  end

  defp encode_with_tokenizer(tokenizer, text, _opts) do
    with {:ok, encoding} <- Tokenizer.encode(tokenizer, text) do
      {:ok, Encoding.get_ids(encoding)}
    end
  end

  defp decode_with_tokenizer(%TikEncoding{} = encoding, ids) do
    TikEncoding.decode(encoding, ids)
  end

  defp decode_with_tokenizer(tokenizer, ids) do
    Tokenizer.decode(tokenizer, ids)
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
    cond do
      String.starts_with?(model_name, "meta-llama/Llama-3") ->
        @llama3_tokenizer

      count_slashes(model_name) == 2 ->
        [org, model | _variant] = String.split(model_name, "/", parts: 3)
        "#{org}/#{model}"

      true ->
        model_name
    end
  end

  defp count_slashes(s), do: s |> String.graphemes() |> Enum.count(&(&1 == "/"))

  defp load_tokenizer(load_fun, tokenizer_id, load_opts) do
    case load_fun.(tokenizer_id, load_opts) do
      {:ok, tokenizer} -> {:ok, tokenizer}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_load_result, other}}
    end
  rescue
    e -> {:error, e}
  catch
    :exit, reason -> {:error, reason}
  end

  defp cache_tokenizer(tokenizer_id, tokenizer) do
    table = cache_table()

    case :ets.insert_new(table, {tokenizer_id, tokenizer}) do
      true ->
        {:ok, tokenizer}

      false ->
        case :ets.lookup(table, tokenizer_id) do
          [{^tokenizer_id, existing}] ->
            {:ok, existing}

          [] ->
            :ets.insert(table, {tokenizer_id, tokenizer})
            {:ok, tokenizer}
        end
    end
  end

  defp ensure_table! do
    table = cache_table()
    ensure_table_for(table)
  end

  defp ensure_table_for(table) when is_reference(table) do
    validate_table_reference!(table)
    table
  end

  defp ensure_table_for(table) when is_atom(table) do
    ensure_named_table!(table)
  end

  defp validate_table_reference!(table) do
    case :ets.info(table) do
      :undefined ->
        raise ArgumentError, "tokenizer cache table is not available: #{inspect(table)}"

      _ ->
        :ok
    end
  end

  defp ensure_named_table!(table) do
    case :ets.whereis(table) do
      :undefined -> start_app_and_get_table!(table)
      _ -> table
    end
  end

  defp start_app_and_get_table!(table) do
    ensure_tinkex_started!()

    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:set, :public, :named_table, read_concurrency: true])

      _ ->
        table
    end
  end

  defp ensure_tinkex_started! do
    # Ensure the application is started so the shared ETS tables are created
    case Application.ensure_all_started(:tinkex) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "could not start :tinkex application: #{inspect(reason)}"
    end
  end

  defp safe_call_info(fun, training_client) when is_function(fun, 1) do
    fun.(training_client)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp format_load_error(tokenizer_id, reason) do
    "Failed to load tokenizer #{tokenizer_id}: #{format_reason(reason)}"
  end

  defp format_reason(%Error{message: message}), do: message
  defp format_reason(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_reason(reason), do: inspect(reason)
end
