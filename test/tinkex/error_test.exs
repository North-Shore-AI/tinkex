defmodule Tinkex.ErrorTest do
  use ExUnit.Case, async: true

  alias Tinkex.Error

  describe "user_error?/1" do
    test "category :user is user error" do
      error = %Error{message: "test", type: :request_failed, category: :user}
      assert Error.user_error?(error)
    end

    test "4xx status (not 408/429) is user error" do
      error = %Error{message: "test", type: :api_status, status: 400}
      assert Error.user_error?(error)

      error = %Error{message: "test", type: :api_status, status: 404}
      assert Error.user_error?(error)
    end

    test "408 is not user error (retryable)" do
      error = %Error{message: "test", type: :api_status, status: 408}
      refute Error.user_error?(error)
    end

    test "429 is not user error (retryable)" do
      error = %Error{message: "test", type: :api_status, status: 429}
      refute Error.user_error?(error)
    end

    test "5xx is not user error" do
      error = %Error{message: "test", type: :api_status, status: 500}
      refute Error.user_error?(error)
    end

    test "category :server is not user error" do
      error = %Error{message: "test", type: :request_failed, category: :server}
      refute Error.user_error?(error)
    end
  end

  describe "retryable?/1" do
    test "user errors are not retryable" do
      error = %Error{message: "test", type: :request_failed, category: :user}
      refute Error.retryable?(error)
    end

    test "server errors are retryable" do
      error = %Error{message: "test", type: :request_failed, category: :server}
      assert Error.retryable?(error)
    end

    test "5xx errors are retryable" do
      error = %Error{message: "test", type: :api_status, status: 500}
      assert Error.retryable?(error)
    end
  end

  describe "format/1" do
    test "formats error with status" do
      error = %Error{message: "Not found", type: :api_status, status: 404}
      assert Error.format(error) == "[api_status (404)] Not found"
    end

    test "formats error without status" do
      error = %Error{message: "Connection failed", type: :api_connection}
      assert Error.format(error) == "[api_connection] Connection failed"
    end
  end
end
