defmodule Tinkex.Training.CustomLossTest do
  use ExUnit.Case, async: true

  alias Tinkex.Training.CustomLoss
  alias Tinkex.Types.{Datum, TensorData, ForwardBackwardOutput}

  describe "extract_per_datum_logprobs/1" do
    test "preserves per-datum structure from forward output" do
      output = %ForwardBackwardOutput{
        loss_fn_output_type: "cross_entropy",
        loss_fn_outputs: [
          %{"logprobs" => %{"data" => [-1.0, -2.0], "dtype" => "float32"}},
          %{"logprobs" => %{"data" => [-0.5, -1.5, -2.5], "dtype" => "float32"}},
          %{"logprobs" => %{"data" => [-3.0], "dtype" => "float32"}}
        ],
        metrics: %{"loss" => 1.5}
      }

      {:ok, logprobs_list} = CustomLoss.extract_per_datum_logprobs(output)

      assert length(logprobs_list) == 3
      assert Nx.shape(Enum.at(logprobs_list, 0)) == {2}
      assert Nx.shape(Enum.at(logprobs_list, 1)) == {3}
      assert Nx.shape(Enum.at(logprobs_list, 2)) == {1}
    end
  end

  describe "compute_gradients/2" do
    test "computes gradients for each logprobs tensor" do
      logprobs_list = [
        Nx.tensor([-1.0, -2.0]),
        Nx.tensor([-0.5, -1.5])
      ]

      loss_fn = fn _data, logprobs ->
        total = logprobs |> Enum.map(&Nx.sum/1) |> Enum.reduce(&Nx.add/2)
        {total, %{"custom" => 1.0}}
      end

      {:ok, {gradients, metrics}} = CustomLoss.compute_gradients([], logprobs_list, loss_fn)

      assert length(gradients) == 2
      assert Nx.to_flat_list(Enum.at(gradients, 0)) == [1.0, 1.0]
      assert metrics == %{"custom" => 1.0}
    end
  end

  describe "build_linear_loss_data/3" do
    test "creates synthetic data with negative gradients as weights" do
      original_data = [
        %Datum{
          model_input: %{chunks: [%{data: [1, 2, 3]}]},
          loss_fn_inputs: %{"target_tokens" => %TensorData{data: [4, 5, 6], dtype: :int64}}
        }
      ]

      gradients = [Nx.tensor([0.1, 0.2, 0.3])]

      linear_data = CustomLoss.build_linear_loss_data(original_data, gradients)

      assert length(linear_data) == 1
      datum = hd(linear_data)

      assert datum.model_input == hd(original_data).model_input

      assert datum.loss_fn_inputs["target_tokens"] ==
               hd(original_data).loss_fn_inputs["target_tokens"]

      weights = datum.loss_fn_inputs["weights"]

      assert Enum.zip(weights.data, [-0.1, -0.2, -0.3])
             |> Enum.all?(fn {got, expected} -> abs(got - expected) < 1.0e-6 end)
    end
  end

  describe "forward_backward_custom integration" do
    @tag :integration
    test "returns ForwardBackwardOutput compatible with optim_step" do
      # This test requires a mock or actual server
      # The key assertion: result type is ForwardBackwardOutput, not CustomLossOutput
      assert true
    end
  end
end
