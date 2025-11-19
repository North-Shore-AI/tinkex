defmodule Tinkex.Types.OptimStepResponseTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.OptimStepResponse

  describe "from_json/1" do
    test "parses success: true" do
      result = OptimStepResponse.from_json(%{"success" => true})
      assert result.success == true
    end

    test "parses success: false" do
      result = OptimStepResponse.from_json(%{"success" => false})
      assert result.success == false
    end

    test "defaults to true when success key missing" do
      result = OptimStepResponse.from_json(%{})
      assert result.success == true
    end
  end
end
