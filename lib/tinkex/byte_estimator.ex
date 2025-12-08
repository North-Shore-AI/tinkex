defmodule Tinkex.ByteEstimator do
  @moduledoc """
  Byte size estimation for model inputs and datums.

  Provides consistent heuristics across training chunking and sampling dispatch:
  - Image chunks: raw byte size of the data string
  - Image asset pointers: byte size of the location string
  - Encoded text and other length-aware chunks: token count * 10 bytes
  - Loss function inputs (TensorData / tensors / plain maps): element count * 10 bytes
  """

  alias Tinkex.Types.{
    Datum,
    EncodedTextChunk,
    ImageAssetPointerChunk,
    ImageChunk,
    ModelInput,
    TensorData
  }

  @bytes_per_token 10
  @bytes_per_tensor_element 10

  @doc """
  Estimate byte size of a single `ModelInput` chunk.
  """
  @spec estimate_chunk_bytes(struct()) :: non_neg_integer()
  def estimate_chunk_bytes(%ImageChunk{data: data}) when is_binary(data) do
    byte_size(data)
  end

  def estimate_chunk_bytes(%ImageAssetPointerChunk{location: location})
      when is_binary(location) do
    byte_size(location)
  end

  def estimate_chunk_bytes(%EncodedTextChunk{} = chunk) do
    EncodedTextChunk.length(chunk) * @bytes_per_token
  end

  def estimate_chunk_bytes(%{__struct__: mod} = chunk) do
    if function_exported?(mod, :length, 1) do
      length = mod.length(chunk)

      if is_number(length) and length >= 0 do
        trunc(length) * @bytes_per_token
      else
        0
      end
    else
      0
    end
  end

  def estimate_chunk_bytes(_), do: 0

  @doc """
  Estimate byte size of a `ModelInput`.
  """
  @spec estimate_model_input_bytes(ModelInput.t() | any()) :: non_neg_integer()
  def estimate_model_input_bytes(%ModelInput{chunks: chunks}) when is_list(chunks) do
    Enum.reduce(chunks, 0, fn chunk, acc ->
      acc + estimate_chunk_bytes(chunk)
    end)
  end

  def estimate_model_input_bytes(_), do: 0

  @doc """
  Estimate byte size of loss function inputs map.
  """
  @spec estimate_loss_fn_inputs_bytes(map() | any()) :: non_neg_integer()
  def estimate_loss_fn_inputs_bytes(loss_fn_inputs) when is_map(loss_fn_inputs) do
    loss_fn_inputs
    |> Map.values()
    |> Enum.reduce(0, fn value, acc ->
      acc + estimate_loss_value_bytes(value)
    end)
  end

  def estimate_loss_fn_inputs_bytes(_), do: 0

  defp estimate_loss_value_bytes(%TensorData{data: data}) when is_list(data) do
    length(data) * @bytes_per_tensor_element
  end

  defp estimate_loss_value_bytes(%Nx.Tensor{} = tensor) do
    Nx.size(tensor) * @bytes_per_tensor_element
  end

  defp estimate_loss_value_bytes(%{data: data}) when is_list(data) do
    length(data) * @bytes_per_tensor_element
  end

  defp estimate_loss_value_bytes(%{"data" => data}) when is_list(data) do
    length(data) * @bytes_per_tensor_element
  end

  defp estimate_loss_value_bytes(_), do: 0

  @doc """
  Estimate byte size of a `Datum`.
  """
  @spec estimate_datum_bytes(Datum.t() | map()) :: non_neg_integer()
  def estimate_datum_bytes(%Datum{model_input: model_input, loss_fn_inputs: loss_fn_inputs}) do
    estimate_model_input_bytes(model_input) + estimate_loss_fn_inputs_bytes(loss_fn_inputs)
  end

  def estimate_datum_bytes(%{model_input: model_input, loss_fn_inputs: loss_fn_inputs}) do
    estimate_model_input_bytes(model_input) + estimate_loss_fn_inputs_bytes(loss_fn_inputs)
  end

  def estimate_datum_bytes(_), do: 0

  @doc """
  Estimate byte size for a list of datums.
  """
  @spec estimate_data_bytes([Datum.t()]) :: non_neg_integer()
  def estimate_data_bytes(data) when is_list(data) do
    Enum.reduce(data, 0, fn datum, acc ->
      acc + estimate_datum_bytes(datum)
    end)
  end
end
