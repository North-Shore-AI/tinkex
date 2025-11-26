defmodule Tinkex.Regularizer.GradientTracker do
  @moduledoc """
  Computes gradient norms for regularizers using Nx automatic differentiation.

  This module provides L2 gradient norm computation for monitoring which
  regularizers dominate the training signal.

  ## Implementation Notes

  Nx provides automatic differentiation through `Nx.Defn.grad/2`. We wrap
  regularizer functions to extract just the loss tensor for differentiation.

  Unlike PyTorch's `torch.autograd.grad(..., retain_graph=True)`, Nx
  computes gradients symbolically and doesn't require graph retention.

  ## Usage

  Gradient tracking is an optional feature enabled via the
  `:track_grad_norms` option in the regularizer pipeline:

      Pipeline.compute(data, logprobs, base_loss_fn,
        regularizers: regularizers,
        track_grad_norms: true
      )

  When enabled, each `RegularizerOutput` includes:
  - `grad_norm`: L2 norm of the regularizer's gradient
  - `grad_norm_weighted`: `weight * grad_norm`
  """

  require Logger

  alias Tinkex.Types.RegularizerSpec

  @doc """
  Compute L2 norm of gradients from a loss function with respect to inputs.

  ## Parameters
  - `loss_fn` - Function that takes logprobs and returns scalar loss tensor
  - `logprobs` - Nx tensor to differentiate with respect to

  ## Returns
  Float representing the L2 norm: `sqrt(sum(grad^2))`

  ## Examples

      loss_fn = fn x -> Nx.sum(x) end
      norm = GradientTracker.compute_grad_norm(loss_fn, Nx.tensor([1.0, 2.0, 3.0]))
      # => 1.732... (sqrt(3))
  """
  @spec compute_grad_norm(
          loss_fn :: (Nx.Tensor.t() -> Nx.Tensor.t()),
          logprobs :: Nx.Tensor.t()
        ) :: float()
  def compute_grad_norm(loss_fn, logprobs) do
    grad_tensor = Nx.Defn.grad(logprobs, loss_fn)

    grad_tensor
    |> Nx.flatten()
    |> Nx.pow(2)
    |> Nx.sum()
    |> Nx.sqrt()
    |> Nx.to_number()
  end

  @doc """
  Compute gradient norm for a regularizer spec.

  Wraps the regularizer function to extract just the loss for differentiation.

  ## Parameters
  - `spec` - RegularizerSpec with the regularizer function
  - `data` - Training data (passed to regularizer but not differentiated)
  - `logprobs` - Nx tensor to differentiate with respect to

  ## Returns
  Float representing the L2 gradient norm. Returns 0.0 if gradient
  computation fails (e.g., for non-differentiable operations).

  ## Examples

      spec = %RegularizerSpec{fn: &my_regularizer/2, weight: 0.1, name: "l1"}
      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)
  """
  @spec grad_norm_for_regularizer(
          RegularizerSpec.t(),
          list(Tinkex.Types.Datum.t()),
          Nx.Tensor.t()
        ) :: float()
  def grad_norm_for_regularizer(spec, data, logprobs) do
    # Wrap regularizer to return only the loss tensor
    loss_fn = fn lp ->
      {loss, _metrics} = spec.fn.(data, lp)

      # Ensure it's a scalar
      case Nx.shape(loss) do
        {} -> loss
        _ -> Nx.sum(loss)
      end
    end

    compute_grad_norm(loss_fn, logprobs)
  rescue
    e ->
      # Some operations may not be differentiable
      # Return 0.0 with a warning
      Logger.warning("Gradient computation failed for #{spec.name}: #{inspect(e)}")
      0.0
  end

  @doc """
  Compute gradient norm for the total composed loss.

  Composes the base loss and all regularizers (with weights) and computes
  the L2 norm of the combined gradient.

  ## Parameters
  - `base_loss_fn` - Base loss function `(data, logprobs) -> {loss, metrics}`
  - `regularizers` - List of RegularizerSpec structs
  - `data` - Training data
  - `logprobs` - Nx tensor to differentiate with respect to

  ## Returns
  Float representing the L2 norm of the total gradient.

  ## Formula

  The total loss is:
      total = base_loss + Σ(weight_i × regularizer_i)

  The gradient is computed with respect to `logprobs`.

  ## Examples

      norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)
  """
  @spec total_grad_norm(
          base_loss_fn :: function(),
          regularizers :: list(RegularizerSpec.t()),
          data :: list(Tinkex.Types.Datum.t()),
          logprobs :: Nx.Tensor.t()
        ) :: float()
  def total_grad_norm(base_loss_fn, regularizers, data, logprobs) do
    # Compose total loss function
    total_loss_fn = fn lp ->
      {base_loss, _} = base_loss_fn.(data, lp)

      reg_losses =
        Enum.map(regularizers, fn spec ->
          {loss, _} = spec.fn.(data, lp)
          Nx.multiply(spec.weight, loss)
        end)

      case reg_losses do
        [] ->
          base_loss

        _ ->
          [base_loss | reg_losses]
          |> Enum.reduce(&Nx.add/2)
      end
    end

    compute_grad_norm(total_loss_fn, logprobs)
  rescue
    e ->
      Logger.warning("Total gradient computation failed: #{inspect(e)}")
      0.0
  end
end
