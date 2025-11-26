defmodule Tinkex.Types.RegularizerOutputTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.RegularizerOutput

  describe "from_computation/5" do
    test "creates output with all fields when grad_norm provided" do
      output =
        RegularizerOutput.from_computation(
          "l1_sparsity",
          22.4,
          0.01,
          %{"l1_total" => 44.8},
          7.48
        )

      assert output.name == "l1_sparsity"
      assert output.value == 22.4
      assert output.weight == 0.01
      assert_in_delta output.contribution, 0.224, 0.0001
      assert output.grad_norm == 7.48
      assert_in_delta output.grad_norm_weighted, 0.0748, 0.0001
      assert output.custom == %{"l1_total" => 44.8}
    end

    test "creates output without grad_norm fields when not provided" do
      output =
        RegularizerOutput.from_computation(
          "entropy",
          1.5,
          0.001,
          %{"entropy_mean" => 1.5}
        )

      assert output.name == "entropy"
      assert output.value == 1.5
      assert output.weight == 0.001
      assert output.contribution == 0.0015
      assert output.grad_norm == nil
      assert output.grad_norm_weighted == nil
      assert output.custom == %{"entropy_mean" => 1.5}
    end

    test "handles nil custom_metrics" do
      output =
        RegularizerOutput.from_computation(
          "test",
          10.0,
          0.1,
          nil
        )

      assert output.custom == %{}
    end

    test "handles zero weight" do
      output =
        RegularizerOutput.from_computation(
          "disabled",
          100.0,
          0.0,
          %{}
        )

      assert output.contribution == 0.0
    end

    test "handles zero grad_norm" do
      output =
        RegularizerOutput.from_computation(
          "test",
          10.0,
          0.1,
          %{},
          0.0
        )

      assert output.grad_norm == 0.0
      assert output.grad_norm_weighted == 0.0
    end
  end

  describe "struct fields" do
    test "has expected fields with enforce_keys" do
      output = %RegularizerOutput{
        name: "test",
        value: 1.0,
        weight: 0.1,
        contribution: 0.1
      }

      assert output.name == "test"
      assert output.value == 1.0
      assert output.weight == 0.1
      assert output.contribution == 0.1
      assert output.grad_norm == nil
      assert output.grad_norm_weighted == nil
      assert output.custom == %{}
    end
  end

  describe "Jason.Encoder" do
    test "encodes output without grad_norm" do
      output = %RegularizerOutput{
        name: "l1",
        value: 10.0,
        weight: 0.1,
        contribution: 1.0,
        custom: %{"total" => 20.0}
      }

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["name"] == "l1"
      assert decoded["value"] == 10.0
      assert decoded["weight"] == 0.1
      assert decoded["contribution"] == 1.0
      assert decoded["custom"] == %{"total" => 20.0}
      refute Map.has_key?(decoded, "grad_norm")
      refute Map.has_key?(decoded, "grad_norm_weighted")
    end

    test "encodes output with grad_norm" do
      output = %RegularizerOutput{
        name: "l1",
        value: 10.0,
        weight: 0.1,
        contribution: 1.0,
        grad_norm: 5.0,
        grad_norm_weighted: 0.5,
        custom: %{}
      }

      json = Jason.encode!(output)
      decoded = Jason.decode!(json)

      assert decoded["grad_norm"] == 5.0
      assert decoded["grad_norm_weighted"] == 0.5
    end
  end
end
