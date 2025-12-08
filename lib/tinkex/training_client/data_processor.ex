defmodule Tinkex.TrainingClient.DataProcessor do
  @moduledoc """
  Data chunking, numbering, and tensor operations for TrainingClient.

  This module handles:
  - Chunking training data based on size limits
  - Estimating chunk sizes using byte heuristics
  - Building placeholder gradients for custom loss
  - Extracting target tokens from loss function inputs
  """

  alias Tinkex.ByteEstimator
  alias Tinkex.Error
  alias Tinkex.Types.{Datum, TensorData}

  @max_chunk_len 1024
  @max_chunk_bytes_count 5_000_000

  @doc """
  Chunk data into manageable pieces based on size and byte limits.

  Ensures no chunk exceeds:
  - #{@max_chunk_len} items
  - #{@max_chunk_bytes_count} total estimated bytes
  """
  @spec chunk_data(list()) :: [list()]
  def chunk_data(data) do
    data
    |> Enum.chunk_while(
      {[], 0},
      fn datum, {chunk, byte_count} ->
        estimated = ByteEstimator.estimate_datum_bytes(datum)

        cond do
          length(chunk) >= @max_chunk_len ->
            {:cont, chunk, {[datum], estimated}}

          byte_count + estimated > @max_chunk_bytes_count ->
            {:cont, chunk, {[datum], estimated}}

          true ->
            {:cont, {chunk ++ [datum], byte_count + estimated}}
        end
      end,
      fn
        {[], 0} -> {:cont, []}
        {chunk, _count} -> {:cont, chunk, {[], 0}}
      end
    )
  end

  @doc """
  Allocate sequential request IDs for a batch of requests.

  Returns `{[id1, id2, ...], new_counter}` where the IDs are consecutive
  starting from the current counter.
  """
  @spec allocate_request_ids(non_neg_integer(), pos_integer()) ::
          {[pos_integer()], pos_integer()}
  def allocate_request_ids(count, counter) when count <= 0, do: {[], counter}

  def allocate_request_ids(count, counter) do
    ids = Enum.to_list(counter..(counter + count - 1))
    {ids, counter + count}
  end

  @doc """
  Build placeholder gradients (zeros) for custom loss computation.

  Creates zero-filled tensors matching the shape of target_tokens for each datum.
  These are used as placeholder gradients before the actual loss computation.
  """
  @spec build_placeholder_gradients(list(Datum.t())) ::
          {:ok, [Nx.Tensor.t()]} | {:error, Error.t()}
  def build_placeholder_gradients(data) do
    data
    |> Enum.reduce_while({:ok, []}, fn datum, {:ok, acc} ->
      case fetch_target_tokens_tensor(datum) do
        {:ok, target_tensor} ->
          zero =
            Nx.broadcast(
              Nx.tensor(0.0, type: {:f, 32}),
              Nx.shape(target_tensor)
            )

          {:cont, {:ok, [zero | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, grads_rev} -> {:ok, Enum.reverse(grads_rev)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Extract target_tokens tensor from a datum's loss_fn_inputs.

  Supports both TensorData and Nx.Tensor formats.
  """
  @spec fetch_target_tokens_tensor(Datum.t()) ::
          {:ok, Nx.Tensor.t()} | {:error, Error.t()}
  def fetch_target_tokens_tensor(%Datum{loss_fn_inputs: inputs}) do
    case inputs["target_tokens"] || inputs[:target_tokens] do
      %TensorData{} = td ->
        {:ok, TensorData.to_nx(td)}

      %Nx.Tensor{} = tensor ->
        {:ok, tensor}

      nil ->
        {:error, Error.new(:validation, "target_tokens missing from loss_fn_inputs")}

      other ->
        {:error,
         Error.new(
           :validation,
           "Invalid target_tokens in loss_fn_inputs: #{inspect(other)}"
         )}
    end
  end
end
