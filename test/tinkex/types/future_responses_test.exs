defmodule Tinkex.Types.FutureRetrieveResponseTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.{
    FutureRetrieveResponse,
    FuturePendingResponse,
    FutureCompletedResponse,
    FutureFailedResponse,
    TryAgainResponse
  }

  describe "from_json/1" do
    test "parses pending response" do
      json = %{"status" => "pending"}
      result = FutureRetrieveResponse.from_json(json)

      assert %FuturePendingResponse{status: "pending"} = result
    end

    test "parses completed response" do
      json = %{
        "status" => "completed",
        "result" => %{"data" => "test"}
      }

      result = FutureRetrieveResponse.from_json(json)

      assert %FutureCompletedResponse{status: "completed", result: %{"data" => "test"}} = result
    end

    test "parses failed response" do
      json = %{
        "status" => "failed",
        "error" => %{"message" => "Something went wrong"}
      }

      result = FutureRetrieveResponse.from_json(json)

      assert %FutureFailedResponse{status: "failed"} = result
      assert result.error["message"] == "Something went wrong"
    end

    test "parses try_again response with active queue" do
      json = %{
        "type" => "try_again",
        "request_id" => "req-123",
        "queue_state" => "active",
        "retry_after_ms" => nil
      }

      result = FutureRetrieveResponse.from_json(json)

      assert %TryAgainResponse{} = result
      assert result.type == "try_again"
      assert result.request_id == "req-123"
      assert result.queue_state == :active
      assert result.retry_after_ms == nil
    end

    test "parses try_again response with paused_capacity" do
      json = %{
        "type" => "try_again",
        "request_id" => "req-456",
        "queue_state" => "paused_capacity",
        "retry_after_ms" => 5000
      }

      result = FutureRetrieveResponse.from_json(json)

      assert result.queue_state == :paused_capacity
      assert result.retry_after_ms == 5000
    end

    test "parses try_again response with paused_rate_limit" do
      json = %{
        "type" => "try_again",
        "request_id" => "req-789",
        "queue_state" => "paused_rate_limit",
        "retry_after_ms" => 10000
      }

      result = FutureRetrieveResponse.from_json(json)

      assert result.queue_state == :paused_rate_limit
      assert result.retry_after_ms == 10000
    end
  end
end
