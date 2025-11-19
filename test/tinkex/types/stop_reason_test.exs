defmodule Tinkex.Types.StopReasonTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.StopReason

  describe "parse/1" do
    test "parses lowercase wire values" do
      assert StopReason.parse("length") == :length
      assert StopReason.parse("stop") == :stop
    end

    test "returns nil for unknown values" do
      assert StopReason.parse("unknown_value") == nil
      assert StopReason.parse("max_tokens") == nil
    end

    test "returns nil for nil input" do
      assert StopReason.parse(nil) == nil
    end
  end

  describe "to_string/1" do
    test "converts atoms to wire format strings" do
      assert StopReason.to_string(:length) == "length"
      assert StopReason.to_string(:stop) == "stop"
    end
  end
end
