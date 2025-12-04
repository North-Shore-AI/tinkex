defmodule Tinkex.Types.TensorData do
  @moduledoc """
  Numerical tensor data for training.

  Mirrors Python tinker.types.TensorData.

  IMPORTANT: Only `int64` and `float32` dtypes are supported by the backend.
  This module performs aggressive casting to match Python SDK behavior.
  """

  alias Tinkex.Types.TensorDtype

  defstruct [:data, :dtype, :shape]

  @type t :: %__MODULE__{
          data: [number()],
          dtype: TensorDtype.t(),
          shape: [non_neg_integer()] | nil
        }

  @doc """
  Create TensorData from an Nx tensor.

  Performs aggressive type casting to match Python SDK:
  - float64 → float32 (downcast)
  - int32 → int64 (upcast)
  - unsigned → int64 (upcast)
  """
  @spec from_nx(Nx.Tensor.t()) :: t()
  def from_nx(%Nx.Tensor{} = tensor) do
    {casted_tensor, dtype} = normalize_tensor(tensor)
    shape_tuple = Nx.shape(casted_tensor)

    %__MODULE__{
      data: Nx.to_flat_list(casted_tensor),
      dtype: dtype,
      shape: maybe_list_shape(shape_tuple)
    }
  end

  @doc """
  Convert TensorData back to an Nx tensor.
  """
  @spec to_nx(t()) :: Nx.Tensor.t()
  def to_nx(%__MODULE__{data: data, dtype: dtype, shape: nil}) do
    Nx.tensor(data, type: TensorDtype.to_nx_type(dtype))
  end

  def to_nx(%__MODULE__{data: data, dtype: dtype, shape: shape}) when is_list(shape) do
    data
    |> Nx.tensor(type: TensorDtype.to_nx_type(dtype))
    |> Nx.reshape(List.to_tuple(shape))
  end

  @doc """
  Return the flat data list from TensorData.

  Provides API parity with Python's `TensorData.tolist()`.

  ## Examples

      iex> tensor = TensorData.from_nx(Nx.tensor([1.0, 2.0, 3.0]))
      iex> TensorData.tolist(tensor)
      [1.0, 2.0, 3.0]
  """
  @spec tolist(t()) :: [number()]
  def tolist(%__MODULE__{data: data}), do: data

  defp normalize_tensor(%Nx.Tensor{} = tensor) do
    case Nx.type(tensor) do
      {:f, 32} ->
        {tensor, :float32}

      {:f, 64} ->
        {Nx.as_type(tensor, {:f, 32}), :float32}

      {:s, 64} ->
        {tensor, :int64}

      {:s, 32} ->
        {Nx.as_type(tensor, {:s, 64}), :int64}

      {:u, _} ->
        {Nx.as_type(tensor, {:s, 64}), :int64}

      {:bf, 16} ->
        raise ArgumentError, "Unsupported tensor dtype: bf16. Use float32 or float64."

      other ->
        raise ArgumentError, "Unsupported tensor dtype: #{inspect(other)}"
    end
  end

  defp maybe_list_shape({}), do: nil
  defp maybe_list_shape(shape_tuple), do: Tuple.to_list(shape_tuple)
end

defimpl Jason.Encoder, for: Tinkex.Types.TensorData do
  def encode(tensor_data, opts) do
    dtype_str = Tinkex.Types.TensorDtype.to_string(tensor_data.dtype)

    %{
      data: tensor_data.data,
      dtype: dtype_str,
      shape: tensor_data.shape
    }
    |> Jason.Encode.map(opts)
  end
end
