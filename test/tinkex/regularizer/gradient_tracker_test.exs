defmodule Tinkex.Regularizer.GradientTrackerTest do
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer.GradientTracker
  alias Tinkex.Types.RegularizerSpec

  describe "compute_grad_norm/2" do
    test "computes L2 norm for simple sum loss" do
      # For loss = sum(x), gradient = 1 for each element
      # L2 norm = sqrt(1^2 + 1^2 + 1^2) = sqrt(3)
      loss_fn = fn x -> Nx.sum(x) end
      inputs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.compute_grad_norm(loss_fn, inputs)

      assert_in_delta norm, :math.sqrt(3.0), 0.001
    end

    test "computes L2 norm for squared loss" do
      # For loss = sum(x^2), gradient = 2*x
      # For x = [1, 2, 3], grad = [2, 4, 6]
      # L2 norm = sqrt(4 + 16 + 36) = sqrt(56)
      loss_fn = fn x -> Nx.sum(Nx.pow(x, 2)) end
      inputs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.compute_grad_norm(loss_fn, inputs)

      assert_in_delta norm, :math.sqrt(56.0), 0.001
    end

    test "computes L2 norm for mean loss" do
      # For loss = mean(x), gradient = 1/n for each element
      # With n=3: L2 norm = sqrt(3 * (1/3)^2) = sqrt(3/9) = sqrt(1/3)
      loss_fn = fn x -> Nx.mean(x) end
      inputs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.compute_grad_norm(loss_fn, inputs)

      assert_in_delta norm, :math.sqrt(1.0 / 3.0), 0.001
    end

    test "handles scalar input" do
      loss_fn = fn x -> Nx.multiply(x, 2) end
      inputs = Nx.tensor(5.0)

      norm = GradientTracker.compute_grad_norm(loss_fn, inputs)

      assert_in_delta norm, 2.0, 0.001
    end

    test "handles 2D tensor input" do
      # For loss = sum(x), gradient = 1 for each element
      # 2x2 matrix: L2 norm = sqrt(4 * 1^2) = 2
      loss_fn = fn x -> Nx.sum(x) end
      inputs = Nx.tensor([[1.0, 2.0], [3.0, 4.0]])

      norm = GradientTracker.compute_grad_norm(loss_fn, inputs)

      assert_in_delta norm, 2.0, 0.001
    end
  end

  describe "grad_norm_for_regularizer/3" do
    test "computes gradient norm for regularizer spec" do
      spec = %RegularizerSpec{
        fn: fn _data, logprobs ->
          {Nx.sum(Nx.abs(logprobs)), %{}}
        end,
        weight: 0.1,
        name: "l1"
      }

      data = []
      logprobs = Nx.tensor([1.0, -2.0, 3.0])

      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

      # For L1 norm, gradient is sign(x): [1, -1, 1]
      # L2 norm = sqrt(3)
      assert_in_delta norm, :math.sqrt(3.0), 0.001
    end

    test "handles regularizer returning non-scalar loss" do
      spec = %RegularizerSpec{
        fn: fn _data, logprobs ->
          # Returns a vector, should be summed
          {Nx.abs(logprobs), %{}}
        end,
        weight: 0.1,
        name: "vector_loss"
      }

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

      # Sum of abs values, gradient = sign(x) = [1, 1, 1]
      # L2 norm = sqrt(3)
      assert_in_delta norm, :math.sqrt(3.0), 0.001
    end

    test "returns 0.0 for non-differentiable operations gracefully" do
      # This tests the rescue clause - operations that fail during grad computation
      spec = %RegularizerSpec{
        fn: fn _data, _logprobs ->
          # Return a constant tensor (not dependent on input)
          {Nx.tensor(1.0), %{}}
        end,
        weight: 0.1,
        name: "constant"
      }

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      # This should either return a valid norm (0.0 for constant) or gracefully handle
      norm = GradientTracker.grad_norm_for_regularizer(spec, data, logprobs)

      # Constant loss has zero gradient
      assert_in_delta norm, 0.0, 0.001
    end
  end

  describe "total_grad_norm/4" do
    test "computes combined gradient norm for base loss and regularizers" do
      base_loss_fn = fn _data, logprobs ->
        {Nx.sum(logprobs), %{}}
      end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(Nx.pow(logprobs, 2)), %{}} end,
          weight: 0.5,
          name: "l2"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)

      # Base loss grad: [1, 1, 1]
      # L2 reg grad: 0.5 * [2, 4, 6] = [1, 2, 3]
      # Combined: [2, 3, 4]
      # L2 norm = sqrt(4 + 9 + 16) = sqrt(29)
      assert_in_delta norm, :math.sqrt(29.0), 0.001
    end

    test "computes gradient norm with empty regularizers" do
      base_loss_fn = fn _data, logprobs ->
        {Nx.sum(logprobs), %{}}
      end

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.total_grad_norm(base_loss_fn, [], data, logprobs)

      # Just base loss: gradient = [1, 1, 1], L2 norm = sqrt(3)
      assert_in_delta norm, :math.sqrt(3.0), 0.001
    end

    test "computes gradient norm with multiple regularizers" do
      base_loss_fn = fn _data, logprobs ->
        {Nx.mean(logprobs), %{}}
      end

      regularizers = [
        %RegularizerSpec{
          fn: fn _data, lp -> {Nx.sum(lp), %{}} end,
          weight: 1.0,
          name: "sum"
        },
        %RegularizerSpec{
          fn: fn _data, lp -> {Nx.sum(lp), %{}} end,
          weight: 1.0,
          name: "sum2"
        }
      ]

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      norm = GradientTracker.total_grad_norm(base_loss_fn, regularizers, data, logprobs)

      # mean grad: [1/3, 1/3, 1/3]
      # sum grad (x2): 2 * [1, 1, 1] = [2, 2, 2]
      # combined: [2+1/3, 2+1/3, 2+1/3] = [7/3, 7/3, 7/3]
      # L2 norm = sqrt(3 * (7/3)^2) = (7/3) * sqrt(3)
      expected = 7.0 / 3.0 * :math.sqrt(3.0)
      assert_in_delta norm, expected, 0.01
    end
  end
end
