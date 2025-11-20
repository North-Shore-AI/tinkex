defmodule Tinkex.Types.QueueStateTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.QueueState

  describe "parse/1" do
    test "parses known states case-insensitively" do
      assert QueueState.parse("active") == :active
      assert QueueState.parse("PAUSED_RATE_LIMIT") == :paused_rate_limit
      assert QueueState.parse("Paused_Capacity") == :paused_capacity
    end

    test "treats unknown strings as :unknown (breaking change)" do
      assert QueueState.parse("mystery_state") == :unknown
    end

    test "handles nil values" do
      assert QueueState.parse(nil) == :unknown
    end
  end
end
