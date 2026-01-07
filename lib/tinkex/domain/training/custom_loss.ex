defmodule Tinkex.Domain.Training.CustomLoss do
  @moduledoc """
  Custom loss training helpers.

  Mirrors Python `forward_backward_custom` behavior by computing gradients
  with respect to per-datum logprobs and constructing the synthetic dataset
  used to send gradients back to the server.
  """

  alias Tinkex.Types.{Datum, ForwardBackwardOutput, TensorData, TensorDtype}

  @doc """
  Extract logprob tensors while preserving the per-datum structure.

  Accepts either a single `ForwardBackwardOutput` or a list of them (when
  forward responses were chunked) and returns a list of Nx tensors, one per
  datum, in the original order.
  """
  @spec extract_per_datum_logprobs(ForwardBackwardOutput.t() | [ForwardBackwardOutput.t()]) ::
          {:ok, [Nx.Tensor.t()]} | {:error, term()}
  def extract_per_datum_logprobs(outputs) when is_list(outputs) do
    Enum.reduce_while(outputs, {:ok, []}, fn output, {:ok, acc} ->
      case extract_per_datum_logprobs(output) do
        {:ok, tensors} -> {:cont, {:ok, acc ++ tensors}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def extract_per_datum_logprobs(%ForwardBackwardOutput{loss_fn_outputs: outputs}) do
    outputs
    |> Enum.reduce_while({:ok, []}, fn loss_fn_output, {:ok, acc} ->
      case logprobs_from_loss_fn_output(loss_fn_output) do
        {:ok, tensor} -> {:cont, {:ok, [tensor | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tensors_rev} -> {:ok, Enum.reverse(tensors_rev)}
      {:error, _} = error -> error
    end
  end

  def extract_per_datum_logprobs(_other),
    do: {:error, {:invalid_forward_output, "expected ForwardBackwardOutput"}}

  @doc """
  Compute gradients of the custom loss with respect to each logprobs tensor.

  Uses `Nx.Defn.grad/2` to differentiate the user-provided loss function.
  Returns gradients in the same order as the input logprobs.
  """
  @spec compute_gradients(
          list(),
          [Nx.Tensor.t()],
          (list(), [Nx.Tensor.t()] -> {Nx.Tensor.t(), map()})
        ) ::
          {:ok, {[Nx.Tensor.t()], map()}} | {:error, term()}
  def compute_gradients(_data, [], _loss_fn), do: {:ok, {[], %{}}}

  def compute_gradients(data, logprobs_list, loss_fn) when is_list(logprobs_list) do
    template = List.to_tuple(logprobs_list)

    {_loss_value, metrics} = loss_fn.(data, logprobs_list)

    gradients =
      Nx.Defn.grad(template, fn lp_tuple ->
        lp_list = Tuple.to_list(lp_tuple)
        {loss, _metrics} = loss_fn.(data, lp_list)
        to_scalar(loss)
      end)
      |> Tuple.to_list()

    {:ok, {gradients, metrics}}
  rescue
    e -> {:error, e}
  end

  @doc """
  Build synthetic data for linearized loss using negative gradients as weights.

  Each returned datum includes:
  - original `model_input`
  - `target_tokens` copied from the source datum
  - `weights` set to `-gradient`
  """
  @spec build_linear_loss_data([Datum.t()], [Nx.Tensor.t()]) :: [Datum.t()]
  def build_linear_loss_data(original_data, gradients) do
    Enum.zip(original_data, gradients)
    |> Enum.map(fn {datum, grad} ->
      target_tokens =
        datum.loss_fn_inputs["target_tokens"] ||
          datum.loss_fn_inputs[:target_tokens] ||
          raise ArgumentError, "target_tokens missing from loss_fn_inputs"

      weights =
        grad
        |> Nx.negate()
        |> TensorData.from_nx()

      %Datum{
        model_input: datum.model_input,
        loss_fn_inputs: %{
          "target_tokens" => target_tokens,
          "weights" => weights
        }
      }
    end)
  end

  defp logprobs_from_loss_fn_output(%{"logprobs" => %TensorData{} = td}) do
    {:ok, TensorData.to_nx(td)}
  end

  defp logprobs_from_loss_fn_output(%{"logprobs" => %{"data" => data} = logprobs})
       when is_list(data) do
    dtype = TensorDtype.parse(logprobs["dtype"]) || :float32
    tensor = Nx.tensor(data, type: TensorDtype.to_nx_type(dtype))
    {:ok, maybe_reshape(tensor, logprobs["shape"])}
  end

  defp logprobs_from_loss_fn_output(%{"logprobs" => data}) when is_list(data) do
    {:ok, Nx.tensor(data)}
  end

  defp logprobs_from_loss_fn_output(_),
    do: {:error, {:invalid_logprobs, "missing or invalid logprobs"}}

  defp maybe_reshape(tensor, shape) when is_list(shape),
    do: Nx.reshape(tensor, List.to_tuple(shape))

  defp maybe_reshape(tensor, _), do: tensor

  defp to_scalar(%Nx.Tensor{} = tensor) do
    case Nx.shape(tensor) do
      {} -> tensor
      _ -> Nx.sum(tensor)
    end
  end

  defp to_scalar(other), do: Nx.tensor(other)
end
