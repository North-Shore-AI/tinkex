defmodule Tinkex.Types.Datum do
  @moduledoc """
  Training example containing model input and loss function inputs.

  Mirrors Python tinker.types.Datum.
  """

  alias Tinkex.Types.{ModelInput, TensorData}

  @derive {Jason.Encoder, only: [:model_input, :loss_fn_inputs]}
  defstruct [:model_input, :loss_fn_inputs]

  @type t :: %__MODULE__{
          model_input: ModelInput.t(),
          loss_fn_inputs: %{String.t() => TensorData.t()}
        }

  @doc """
  Create a new Datum with automatic tensor conversion.

  Converts:
  - Nx.Tensor → TensorData
  - Plain lists → TensorData (with dtype inference)
  - TensorData → passthrough
  """
  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      model_input: attrs[:model_input],
      loss_fn_inputs: convert_loss_fn_inputs(attrs[:loss_fn_inputs] || %{})
    }
  end

  defp convert_loss_fn_inputs(inputs) when is_map(inputs) do
    Map.new(inputs, fn {key, value} ->
      key_str = if is_atom(key), do: Atom.to_string(key), else: key
      {key_str, maybe_convert_tensor(value)}
    end)
  end

  defp maybe_convert_tensor(%Nx.Tensor{} = tensor) do
    TensorData.from_nx(tensor)
  end

  defp maybe_convert_tensor(%TensorData{} = td), do: td

  defp maybe_convert_tensor(list) when is_list(list) do
    dtype = infer_dtype(list)

    %TensorData{
      data: List.flatten(list),
      dtype: dtype,
      shape: infer_shape(list)
    }
  end

  defp maybe_convert_tensor(value), do: value

  defp infer_dtype([first | _]) when is_integer(first), do: :int64
  defp infer_dtype([first | _]) when is_float(first), do: :float32
  defp infer_dtype([[first | _] | _]), do: infer_dtype([first])
  defp infer_dtype([]), do: :float32

  defp infer_shape(list) when is_list(list) do
    case list do
      [] -> [0]
      [first | _] when is_list(first) -> [length(list) | infer_shape(first)]
      _ -> [length(list)]
    end
  end
end
