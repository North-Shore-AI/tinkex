defmodule Tinkex.Telemetry.ExceptionChainTest do
  use ExUnit.Case, async: true

  alias Tinkex.Telemetry.Reporter

  defmodule UserError do
    defexception [:message, :status]
  end

  defmodule SystemError do
    defexception [:message, :status]
  end

  defmodule WrapperError do
    defexception [:message, :reason]
  end

  defmodule CauseError do
    defexception [:message, :cause]
  end

  defmodule ContextError do
    defexception [:message, :__cause__, :__context__]
  end

  defmodule PlugStatusError do
    defexception [:message, :plug_status]
  end

  defmodule StatusCodeError do
    defexception [:message, :status_code]
  end

  describe "find_user_error_in_chain/2" do
    test "detects user error with 4xx status (excluding 408/429)" do
      user_error = %UserError{message: "bad request", status: 400}
      assert {:ok, ^user_error} = Reporter.find_user_error_in_chain(user_error)
    end

    test "detects user error with 403 status" do
      user_error = %UserError{message: "forbidden", status: 403}
      assert {:ok, ^user_error} = Reporter.find_user_error_in_chain(user_error)
    end

    test "does not treat 408 as user error" do
      timeout = %UserError{message: "timeout", status: 408}
      assert :not_found = Reporter.find_user_error_in_chain(timeout)
    end

    test "does not treat 429 as user error" do
      rate_limited = %UserError{message: "rate limited", status: 429}
      assert :not_found = Reporter.find_user_error_in_chain(rate_limited)
    end

    test "finds user error via :reason (WrapperError)" do
      user_error = %UserError{message: "inner", status: 400}
      wrapper = %WrapperError{message: "wrapped", reason: user_error}
      assert {:ok, ^user_error} = Reporter.find_user_error_in_chain(wrapper)
    end

    test "finds user error via :cause" do
      user_error = %UserError{message: "inner", status: 422}
      outer = %CauseError{message: "outer", cause: user_error}
      assert {:ok, ^user_error} = Reporter.find_user_error_in_chain(outer)
    end

    test "finds user error via :__cause__" do
      user_error = %UserError{message: "inner", status: 400}
      outer = %ContextError{message: "outer", __cause__: user_error, __context__: nil}
      assert {:ok, ^user_error} = Reporter.find_user_error_in_chain(outer)
    end

    test "finds user error via :__context__" do
      user_error = %UserError{message: "inner", status: 400}
      outer = %ContextError{message: "outer", __cause__: nil, __context__: user_error}
      assert {:ok, ^user_error} = Reporter.find_user_error_in_chain(outer)
    end

    test "finds user error via plug_status 403" do
      error = %PlugStatusError{message: "forbidden", plug_status: 403}
      assert {:ok, ^error} = Reporter.find_user_error_in_chain(error)
    end

    test "does not treat plug_status 408 as user error" do
      error = %PlugStatusError{message: "timeout", plug_status: 408}
      assert :not_found = Reporter.find_user_error_in_chain(error)
    end

    test "does not treat plug_status 429 as user error" do
      error = %PlugStatusError{message: "rate limited", plug_status: 429}
      assert :not_found = Reporter.find_user_error_in_chain(error)
    end

    test "finds user error via status_code field" do
      error = %StatusCodeError{message: "bad request", status_code: 400}
      assert {:ok, ^error} = Reporter.find_user_error_in_chain(error)
    end

    test "handles cycles without infinite loop" do
      # Create a cyclic reference using a process dictionary
      error1 = %CauseError{message: "error1", cause: nil}
      error2 = %CauseError{message: "error2", cause: error1}
      # Replace error1's cause with error2 (simulate cycle)
      error1_with_cycle = %{error1 | cause: error2}
      # This should not infinite loop
      result = Reporter.find_user_error_in_chain(error1_with_cycle)
      assert result == :not_found
    end

    test "returns :not_found for deep non-user chain" do
      inner = %SystemError{message: "inner", status: 500}
      middle = %WrapperError{message: "middle", reason: inner}
      outer = %WrapperError{message: "outer", reason: middle}
      assert :not_found = Reporter.find_user_error_in_chain(outer)
    end

    test "finds user error in deep chain" do
      user_error = %UserError{message: "deep", status: 400}
      inner = %WrapperError{message: "inner", reason: user_error}
      middle = %WrapperError{message: "middle", reason: inner}
      outer = %WrapperError{message: "outer", reason: middle}
      assert {:ok, ^user_error} = Reporter.find_user_error_in_chain(outer)
    end

    test "category :user is a user error" do
      error = %{__struct__: SomeError, __exception__: true, message: "test", category: :user}
      assert {:ok, ^error} = Reporter.find_user_error_in_chain(error)
    end

    test "500 status is not a user error" do
      error = %SystemError{message: "server error", status: 500}
      assert :not_found = Reporter.find_user_error_in_chain(error)
    end
  end
end
