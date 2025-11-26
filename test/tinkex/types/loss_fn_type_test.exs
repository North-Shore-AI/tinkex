defmodule Tinkex.Types.LossFnTypeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.LossFnType

  describe "parse/1" do
    test "parses all valid loss function types" do
      assert LossFnType.parse("cross_entropy") == :cross_entropy
      assert LossFnType.parse("importance_sampling") == :importance_sampling
      assert LossFnType.parse("ppo") == :ppo
      assert LossFnType.parse("cispo") == :cispo
      assert LossFnType.parse("dro") == :dro
    end

    test "returns nil for unknown values" do
      assert LossFnType.parse("unknown") == nil
      assert LossFnType.parse("mse") == nil
    end

    test "returns nil for nil input" do
      assert LossFnType.parse(nil) == nil
    end
  end

  describe "to_string/1" do
    test "converts atoms to wire format strings" do
      assert LossFnType.to_string(:cross_entropy) == "cross_entropy"
      assert LossFnType.to_string(:importance_sampling) == "importance_sampling"
      assert LossFnType.to_string(:ppo) == "ppo"
      assert LossFnType.to_string(:cispo) == "cispo"
      assert LossFnType.to_string(:dro) == "dro"
    end
  end

  describe "roundtrip" do
    test "all loss types roundtrip correctly" do
      for loss_type <- [:cross_entropy, :importance_sampling, :ppo, :cispo, :dro] do
        string = LossFnType.to_string(loss_type)
        assert LossFnType.parse(string) == loss_type
      end
    end
  end
end
