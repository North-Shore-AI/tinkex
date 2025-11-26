defmodule Tinkex.Types.RegularizerSpecTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.RegularizerSpec

  describe "new/1" do
    test "creates spec with valid map attributes" do
      spec =
        RegularizerSpec.new(%{
          fn: fn _data, _logprobs -> {Nx.tensor(1.0), %{}} end,
          weight: 0.01,
          name: "l1_sparsity"
        })

      assert spec.weight == 0.01
      assert spec.name == "l1_sparsity"
      assert spec.async == false
      assert is_function(spec.fn, 2)
    end

    test "creates spec with valid keyword list attributes" do
      spec =
        RegularizerSpec.new(
          fn: fn _data, _logprobs -> {Nx.tensor(1.0), %{}} end,
          weight: 0.5,
          name: "entropy"
        )

      assert spec.weight == 0.5
      assert spec.name == "entropy"
      assert spec.async == false
    end

    test "creates async spec when async is true" do
      spec =
        RegularizerSpec.new(%{
          fn: fn _data, _logprobs ->
            Task.async(fn -> {Nx.tensor(1.0), %{}} end)
          end,
          weight: 0.1,
          name: "async_regularizer",
          async: true
        })

      assert spec.async == true
    end

    test "accepts integer weight (coerced as number)" do
      spec =
        RegularizerSpec.new(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: 1,
          name: "test"
        })

      assert spec.weight == 1
    end

    test "accepts zero weight" do
      spec =
        RegularizerSpec.new(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: 0.0,
          name: "disabled_reg"
        })

      assert spec.weight == 0.0
    end
  end

  describe "validate!/1" do
    test "raises for non-function fn" do
      assert_raise ArgumentError, ~r/must be a function of arity 2/, fn ->
        RegularizerSpec.validate!(%{fn: "not a function", weight: 0.1, name: "test"})
      end
    end

    test "raises for function with wrong arity" do
      assert_raise ArgumentError, ~r/must be a function of arity 2/, fn ->
        RegularizerSpec.validate!(%{fn: fn x -> x end, weight: 0.1, name: "test"})
      end
    end

    test "raises for negative weight" do
      assert_raise ArgumentError, ~r/must be a non-negative number/, fn ->
        RegularizerSpec.validate!(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: -0.1,
          name: "test"
        })
      end
    end

    test "raises for non-numeric weight" do
      assert_raise ArgumentError, ~r/must be a non-negative number/, fn ->
        RegularizerSpec.validate!(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: "0.1",
          name: "test"
        })
      end
    end

    test "raises for empty name" do
      assert_raise ArgumentError, ~r/must be a non-empty string/, fn ->
        RegularizerSpec.validate!(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: 0.1,
          name: ""
        })
      end
    end

    test "raises for nil name" do
      assert_raise ArgumentError, ~r/must be a non-empty string/, fn ->
        RegularizerSpec.validate!(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: 0.1,
          name: nil
        })
      end
    end

    test "raises for non-string name" do
      assert_raise ArgumentError, ~r/must be a non-empty string/, fn ->
        RegularizerSpec.validate!(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: 0.1,
          name: :atom_name
        })
      end
    end

    test "raises for non-boolean async" do
      assert_raise ArgumentError, ~r/must be a boolean/, fn ->
        RegularizerSpec.validate!(%{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: 0.1,
          name: "test",
          async: "true"
        })
      end
    end

    test "returns :ok for valid attributes" do
      assert :ok ==
               RegularizerSpec.validate!(%{
                 fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
                 weight: 0.1,
                 name: "valid"
               })
    end
  end

  describe "struct creation" do
    test "can create struct directly with enforce_keys" do
      fn_ref = fn _d, _l -> {Nx.tensor(1.0), %{}} end

      spec = %RegularizerSpec{
        fn: fn_ref,
        weight: 0.01,
        name: "direct"
      }

      assert spec.fn == fn_ref
      assert spec.weight == 0.01
      assert spec.name == "direct"
      assert spec.async == false
    end

    test "raises when missing required keys via new/1" do
      # Missing weight and name results in validation failure
      assert_raise ArgumentError, fn ->
        RegularizerSpec.new(%{fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end})
      end
    end
  end
end
