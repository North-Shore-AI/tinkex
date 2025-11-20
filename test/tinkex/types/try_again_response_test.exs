defmodule Tinkex.Types.TryAgainResponseTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.TryAgainResponse

  describe "from_map/1" do
    test "parses string-keyed maps" do
      input = %{
        "type" => "try_again",
        "request_id" => "req-1",
        "queue_state" => "active",
        "retry_after_ms" => 1_000
      }

      assert %TryAgainResponse{} = response = TryAgainResponse.from_map(input)
      assert response.queue_state == :active
      assert response.retry_after_ms == 1_000
    end

    test "parses atom-keyed maps" do
      input = %{
        type: "try_again",
        request_id: "req-2",
        queue_state: "paused_capacity",
        retry_after_ms: nil
      }

      assert %TryAgainResponse{} = response = TryAgainResponse.from_map(input)
      assert response.queue_state == :paused_capacity
      assert response.retry_after_ms == nil
    end

    test "parses queue_state case-insensitively" do
      input = %{
        "type" => "TRY_AGAIN",
        "request_id" => "req-3",
        "queue_state" => "Paused_Rate_Limit",
        "retry_after_ms" => 500
      }

      assert %TryAgainResponse{} = response = TryAgainResponse.from_map(input)
      assert response.queue_state == :paused_rate_limit
      assert response.type == "TRY_AGAIN"
    end

    test "raises on missing required fields" do
      input = %{"type" => "try_again", "request_id" => "req-4"}

      assert_raise ArgumentError, fn ->
        TryAgainResponse.from_map(input)
      end
    end
  end
end
