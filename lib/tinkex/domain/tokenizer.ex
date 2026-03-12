defmodule Tinkex.Tokenizer do
  @moduledoc """
  Tokenization helpers for the Tinkex SDK.
  """

  alias TiktokenEx.Encoding, as: TikEncoding
  alias TiktokenEx.Kimi, as: TikKimi
  alias Tinkex.Error
  alias Tokenizers.Encoding
  alias Tokenizers.Tokenizer

  @llama3_tokenizer "thinkingmachineslabinc/meta-llama-3-tokenizer"
  @kimi_tokenizer "moonshotai/Kimi-K2-Thinking"

  @type tokenizer_id :: String.t()
  @type handle :: Tokenizer.t() | TikEncoding.t()

  @spec get_tokenizer_id(String.t(), term() | nil, keyword()) :: tokenizer_id()
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

  @spec get_or_load_tokenizer(tokenizer_id(), keyword()) :: {:ok, handle()} | {:error, Error.t()}
  def get_or_load_tokenizer(tokenizer_id, opts \\ [])

  def get_or_load_tokenizer(tokenizer_id, _opts) when not is_binary(tokenizer_id) do
    {:error, Error.new(:validation, "invalid tokenizer_id: #{inspect(tokenizer_id)}")}
  end

  def get_or_load_tokenizer(tokenizer_id, opts) do
    load_fun = Keyword.get(opts, :load_fun, &default_load_fun/2)
    load_tokenizer_handle(tokenizer_id, load_fun, opts)
  end

  defp default_load_fun(id, opts), do: Tokenizer.from_pretrained(id, opts)

  defp load_tokenizer_handle(tokenizer_id, load_fun, opts) when is_function(load_fun, 2) do
    if kimi_tokenizer?(tokenizer_id) do
      load_kimi_encoding(opts)
    else
      load_opts = Keyword.take(opts, [:revision])
      load_tokenizer(load_fun, tokenizer_id, load_opts)
    end
  end

  defp load_tokenizer_handle(_tokenizer_id, load_fun, _opts) do
    {:error, Error.new(:validation, "invalid load_fun: #{inspect(load_fun)}")}
  end

  defp kimi_tokenizer?(tokenizer_id) when tokenizer_id == @kimi_tokenizer, do: true
  defp kimi_tokenizer?(_tokenizer_id), do: false

  defp load_kimi_encoding(opts) do
    model_path = Keyword.get(opts, :tiktoken_model_path)
    config_path = Keyword.get(opts, :tokenizer_config_path)

    if is_binary(model_path) and is_binary(config_path) do
      kimi_opts =
        [tiktoken_model_path: model_path, tokenizer_config_path: config_path]
        |> maybe_put_opt(:pat_str, Keyword.get(opts, :pat_str))
        |> maybe_put_opt(:special_token_matching, Keyword.get(opts, :special_token_matching))

      TikKimi.from_hf_files(kimi_opts)
    else
      {:error,
       Error.new(
         :validation,
         "Kimi tokenizer requires :tiktoken_model_path and :tokenizer_config_path"
       )}
    end
  end

  defp maybe_put_opt(keyword, _key, nil), do: keyword
  defp maybe_put_opt(keyword, key, value), do: Keyword.put(keyword, key, value)

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
    case Keyword.get(opts, :info_fun) do
      fun when is_function(fun, 1) ->
        case safe_call_info(fun, training_client) do
          {:ok, %{model_data: %{tokenizer_id: id}}} when is_binary(id) -> {:ok, id}
          _ -> :no_id
        end

      _ ->
        :no_id
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

  defp safe_call_info(fun, training_client) when is_function(fun, 1) do
    fun.(training_client)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp format_reason(%Error{message: message}), do: message
  defp format_reason(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_reason(reason), do: inspect(reason)
end
