defmodule Tinkex.Types.CustomLossOutputTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{CustomLossOutput, RegularizerOutput}

  describe "build/4" do
    test "builds output with base loss and no regularizers" do
      output =
        CustomLossOutput.build(
          2.5,
          %{"perplexity" => 12.18},
          []
        )

      assert output.loss_total == 2.5
      assert output.base_loss.value == 2.5
      assert output.base_loss.custom == %{"perplexity" => 12.18}
      assert output.regularizers == %{}
      assert output.regularizer_total == 0.0
      assert output.total_grad_norm == nil
    end

    test "builds output with base loss and regularizers" do
      reg_outputs = [
        %RegularizerOutput{
          name: "sparsity",
          value: 22.4,
          weight: 0.01,
          contribution: 0.224,
          custom: %{}
        },
        %RegularizerOutput{
          name: "entropy",
          value: 1.5,
          weight: 0.1,
          contribution: 0.15,
          custom: %{}
        }
      ]

      output =
        CustomLossOutput.build(
          2.5,
          %{},
          reg_outputs
        )

      assert_in_delta output.loss_total, 2.874, 0.001
      assert_in_delta output.regularizer_total, 0.374, 0.001
      assert Map.has_key?(output.regularizers, "sparsity")
      assert Map.has_key?(output.regularizers, "entropy")
      assert output.regularizers["sparsity"].contribution == 0.224
    end

    test "builds output with gradient norms" do
      reg_outputs = [
        %RegularizerOutput{
          name: "l1",
          value: 10.0,
          weight: 0.1,
          contribution: 1.0,
          grad_norm: 5.0,
          grad_norm_weighted: 0.5,
          custom: %{}
        }
      ]

      output =
        CustomLossOutput.build(
          1.0,
          %{},
          reg_outputs,
          base_grad_norm: 3.14,
          total_grad_norm: 5.67
        )

      assert output.base_loss.grad_norm == 3.14
      assert output.total_grad_norm == 5.67
    end

    test "handles nil base_loss_metrics" do
      output =
        CustomLossOutput.build(
          1.0,
          nil,
          []
        )

      assert output.base_loss.custom == %{}
    end
  end

  describe "loss/1" do
    test "returns loss_total value" do
      output = %CustomLossOutput{
        loss_total: 5.5,
        regularizer_total: 1.0,
        regularizers: %{}
      }

      assert CustomLossOutput.loss(output) == 5.5
    end
  end

  describe "struct fields" do
    test "has expected defaults" do
      output = %CustomLossOutput{loss_total: 1.0}

      assert output.loss_total == 1.0
      assert output.base_loss == nil
      assert output.regularizers == %{}
      assert output.regularizer_total == nil
      assert output.total_grad_norm == nil
    end
  end

  describe "Jason.Encoder" do
    test "encodes output without optional fields" do
      output =
        CustomLossOutput.build(
          2.5,
          %{"perplexity" => 12.18},
          []
        )

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["loss_total"] == 2.5
      assert decoded["regularizer_total"] == 0.0
      assert decoded["base_loss"]["value"] == 2.5
      assert decoded["regularizers"] == %{}
      refute Map.has_key?(decoded, "total_grad_norm")
    end

    test "encodes output with regularizers and grad_norms" do
      reg_outputs = [
        %RegularizerOutput{
          name: "l1",
          value: 10.0,
          weight: 0.1,
          contribution: 1.0,
          grad_norm: 5.0,
          grad_norm_weighted: 0.5,
          custom: %{"sum" => 100.0}
        }
      ]

      output =
        CustomLossOutput.build(
          1.0,
          %{"nll" => 1.0},
          reg_outputs,
          base_grad_norm: 3.14,
          total_grad_norm: 5.67
        )

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["loss_total"] == 2.0
      assert decoded["regularizer_total"] == 1.0
      assert decoded["total_grad_norm"] == 5.67
      assert decoded["base_loss"]["grad_norm"] == 3.14

      l1 = decoded["regularizers"]["l1"]
      assert l1["value"] == 10.0
      assert l1["weight"] == 0.1
      assert l1["contribution"] == 1.0
      assert l1["grad_norm"] == 5.0
    end
  end
end
