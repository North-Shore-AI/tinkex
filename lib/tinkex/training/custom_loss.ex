defmodule Tinkex.Training.CustomLoss do
  @moduledoc false

  alias Tinkex.Domain.Training.CustomLoss
  alias Tinkex.Types.{Datum, ForwardBackwardOutput}

  @spec extract_per_datum_logprobs(ForwardBackwardOutput.t() | [ForwardBackwardOutput.t()]) ::
          {:ok, [Nx.Tensor.t()]} | {:error, term()}
  defdelegate extract_per_datum_logprobs(outputs), to: CustomLoss

  @spec compute_gradients(
          list(),
          [Nx.Tensor.t()],
          (list(), [Nx.Tensor.t()] -> {Nx.Tensor.t(), map()})
        ) ::
          {:ok, {[Nx.Tensor.t()], map()}} | {:error, term()}
  defdelegate compute_gradients(data, logprobs_list, loss_fn), to: CustomLoss

  @spec build_linear_loss_data([Datum.t()], [Nx.Tensor.t()]) :: [Datum.t()]
  defdelegate build_linear_loss_data(original_data, gradients), to: CustomLoss
end
