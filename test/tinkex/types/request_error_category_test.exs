defmodule Tinkex.Types.RequestErrorCategoryTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.RequestErrorCategory

  describe "parse/1" do
    test "parses lowercase wire values" do
      assert RequestErrorCategory.parse("unknown") == :unknown
      assert RequestErrorCategory.parse("server") == :server
      assert RequestErrorCategory.parse("user") == :user
    end

    test "is case-insensitive" do
      assert RequestErrorCategory.parse("UNKNOWN") == :unknown
      assert RequestErrorCategory.parse("Server") == :server
      assert RequestErrorCategory.parse("USER") == :user
    end

    test "defaults to :unknown for unrecognized values" do
      assert RequestErrorCategory.parse("invalid") == :unknown
      assert RequestErrorCategory.parse("") == :unknown
    end

    test "defaults to :unknown for nil input" do
      assert RequestErrorCategory.parse(nil) == :unknown
    end
  end

  describe "to_string/1" do
    test "converts atoms to wire format strings" do
      assert RequestErrorCategory.to_string(:unknown) == "unknown"
      assert RequestErrorCategory.to_string(:server) == "server"
      assert RequestErrorCategory.to_string(:user) == "user"
    end
  end

  describe "retryable?/1" do
    test "user errors are not retryable" do
      refute RequestErrorCategory.retryable?(:user)
    end

    test "server errors are retryable" do
      assert RequestErrorCategory.retryable?(:server)
    end

    test "unknown errors are retryable" do
      assert RequestErrorCategory.retryable?(:unknown)
    end
  end
end
