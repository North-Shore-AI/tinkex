defmodule Tinkex.Types.OptimStepResponseTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.OptimStepResponse

  describe "from_json/1" do
    test "parses metrics from response" do
      result = OptimStepResponse.from_json(%{"metrics" => %{"loss" => 0.5, "grad_norm" => 1.2}})

      assert result.metrics == %{"loss" => 0.5, "grad_norm" => 1.2}
    end

    test "handles nil metrics" do
      result = OptimStepResponse.from_json(%{"metrics" => nil})
      assert result.metrics == nil
    end

    test "handles missing metrics key" do
      result = OptimStepResponse.from_json(%{})
      assert result.metrics == nil
    end
  end

  describe "success?/1" do
    test "always returns true" do
      result = OptimStepResponse.from_json(%{"metrics" => %{"loss" => 0.5}})
      assert OptimStepResponse.success?(result) == true
    end
  end
end
