defmodule Tinkex.Types.Datum do
  @moduledoc """
  Training example containing model input and loss function inputs.

  Mirrors Python tinker.types.Datum.
  """

  alias Tinkex.Types.{ModelInput, TensorData}

  @enforce_keys [:model_input]
  @derive {Jason.Encoder, only: [:model_input, :loss_fn_inputs]}
  defstruct [:model_input, loss_fn_inputs: %{}]

  @key_dtype_map %{
    "target_tokens" => :int64,
    "weights" => :float32,
    "advantages" => :float32,
    "logprobs" => :float32,
    "clip_low_threshold" => :float32,
    "clip_high_threshold" => :float32
  }

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
      {key_str, maybe_convert_tensor(key_str, value)}
    end)
  end

  defp maybe_convert_tensor(_key, %Nx.Tensor{} = tensor) do
    TensorData.from_nx(tensor)
  end

  defp maybe_convert_tensor(_key, %TensorData{} = td), do: td

  defp maybe_convert_tensor(key, list) when is_list(list) do
    dtype =
      Map.fetch(@key_dtype_map, key)
      |> case do
        {:ok, found} ->
          found

        :error ->
          raise ArgumentError,
                "Unsupported list value for loss_fn_inputs key #{inspect(key)}. " <>
                  "Use TensorData/Nx.Tensor or one of: #{inspect(Map.keys(@key_dtype_map))}."
      end

    %TensorData{data: List.flatten(list), dtype: dtype, shape: nil}
  end

  defp maybe_convert_tensor(key, value) do
    raise ArgumentError,
          "Unsupported tensor value in loss_fn_inputs (key #{inspect(key)}): #{inspect(value)}. " <>
            "Expected Nx.Tensor, TensorData, or list."
  end
end
