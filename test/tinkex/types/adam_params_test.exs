defmodule Tinkex.Types.AdamParamsTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.AdamParams

  describe "new/1" do
    test "creates with default values matching Python SDK" do
      {:ok, params} = AdamParams.new()

      assert params.learning_rate == 0.0001
      assert params.beta1 == 0.9
      # NOT 0.999!
      assert params.beta2 == 0.95
      # NOT 1e-8!
      assert params.eps == 1.0e-12
    end

    test "accepts custom values" do
      {:ok, params} =
        AdamParams.new(
          learning_rate: 0.001,
          beta1: 0.8,
          beta2: 0.9,
          eps: 1.0e-8
        )

      assert params.learning_rate == 0.001
      assert params.beta1 == 0.8
      assert params.beta2 == 0.9
      assert params.eps == 1.0e-8
    end

    test "rejects non-positive learning rate" do
      assert {:error, msg} = AdamParams.new(learning_rate: 0)
      assert msg =~ "learning_rate"

      assert {:error, _} = AdamParams.new(learning_rate: -0.001)
    end

    test "rejects beta outside [0, 1)" do
      assert {:error, msg} = AdamParams.new(beta1: -0.1)
      assert msg =~ "beta1"

      assert {:error, msg} = AdamParams.new(beta1: 1.0)
      assert msg =~ "beta1"

      assert {:error, msg} = AdamParams.new(beta2: 1.5)
      assert msg =~ "beta2"
    end

    test "rejects non-positive epsilon" do
      assert {:error, msg} = AdamParams.new(eps: 0)
      assert msg =~ "eps"

      assert {:error, _} = AdamParams.new(eps: -1.0e-8)
    end
  end

  describe "JSON encoding" do
    test "encodes with correct field names" do
      {:ok, params} = AdamParams.new()
      json = Jason.encode!(params)
      decoded = Jason.decode!(json)

      assert decoded["learning_rate"] == 0.0001
      assert decoded["beta1"] == 0.9
      assert decoded["beta2"] == 0.95
      assert decoded["eps"] == 1.0e-12

      # Ensure we use 'eps', NOT 'epsilon'
      assert Map.has_key?(decoded, "eps")
      refute Map.has_key?(decoded, "epsilon")
    end
  end
end
