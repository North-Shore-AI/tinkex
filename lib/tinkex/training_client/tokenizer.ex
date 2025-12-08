defmodule Tinkex.TrainingClient.Tokenizer do
  @moduledoc """
  Tokenizer integration and operations for TrainingClient.

  Provides functions to get tokenizers, encode text, and decode token IDs
  using the training client's model information.
  """

  alias Tinkex.Error
  alias Tinkex.Types.GetInfoResponse

  @doc """
  Get a tokenizer for the training client's model.

  Fetches model info to determine the tokenizer ID, applies heuristics
  (e.g., Llama-3 gating workaround), and loads/caches the tokenizer.

  ## Options

    * `:load_fun` - Custom tokenizer loader function (default: HuggingFace)
    * `:info_fun` - Custom info fetcher for testing

  ## Examples

      {:ok, tokenizer} = Tokenizer.get_tokenizer(client)
      {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, "Hello world")

  ## Errors

  Returns `{:error, %Tinkex.Error{}}` if:
    * Model info cannot be fetched
    * Tokenizer cannot be loaded
  """
  @spec get_tokenizer(pid(), keyword()) ::
          {:ok, Tokenizers.Tokenizer.t()} | {:error, Error.t()}
  def get_tokenizer(client, opts \\ []) do
    info_fun = Keyword.get(opts, :info_fun, &get_info_default/1)

    with {:ok, info} <- info_fun.(client) do
      model_name = get_model_name_from_info(info)
      tokenizer_id = Tinkex.Tokenizer.get_tokenizer_id(model_name, client, opts)
      Tinkex.Tokenizer.get_or_load_tokenizer(tokenizer_id, opts)
    end
  end

  @doc """
  Encode text using the training client's tokenizer.

  Convenience wrapper around `Tinkex.Tokenizer.encode/3` that automatically
  resolves the tokenizer from the training client's model info.

  ## Examples

      {:ok, ids} = Tokenizer.encode(client, "Hello world")

  ## Options

    * `:load_fun` - Custom tokenizer loader function
    * `:info_fun` - Custom info fetcher for testing
  """
  @spec encode(pid(), String.t(), keyword()) ::
          {:ok, [integer()]} | {:error, Error.t()}
  def encode(client, text, opts \\ []) when is_binary(text) do
    info_fun = Keyword.get(opts, :info_fun, &get_info_default/1)

    with {:ok, info} <- info_fun.(client) do
      model_name = get_model_name_from_info(info)
      Tinkex.Tokenizer.encode(text, model_name, Keyword.put(opts, :training_client, client))
    end
  end

  @doc """
  Decode token IDs using the training client's tokenizer.

  Convenience wrapper around `Tinkex.Tokenizer.decode/3` that automatically
  resolves the tokenizer from the training client's model info.

  ## Examples

      {:ok, text} = Tokenizer.decode(client, [1, 2, 3])

  ## Options

    * `:load_fun` - Custom tokenizer loader function
    * `:info_fun` - Custom info fetcher for testing
  """
  @spec decode(pid(), [integer()], keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def decode(client, ids, opts \\ []) when is_list(ids) do
    info_fun = Keyword.get(opts, :info_fun, &get_info_default/1)

    with {:ok, info} <- info_fun.(client) do
      model_name = get_model_name_from_info(info)
      Tinkex.Tokenizer.decode(ids, model_name, Keyword.put(opts, :training_client, client))
    end
  end

  # Extract model name from GetInfoResponse for tokenizer resolution
  defp get_model_name_from_info(%GetInfoResponse{model_data: %{base_model: base}})
       when is_binary(base),
       do: base

  defp get_model_name_from_info(%GetInfoResponse{model_data: %{model_name: name}})
       when is_binary(name),
       do: name

  defp get_model_name_from_info(%{model_data: %{base_model: base}})
       when is_binary(base),
       do: base

  defp get_model_name_from_info(%{model_data: %{model_name: name}})
       when is_binary(name),
       do: name

  defp get_model_name_from_info(_), do: "unknown"

  # Default info function that calls GenServer
  defp get_info_default(client) do
    GenServer.call(client, :get_info)
  end
end
