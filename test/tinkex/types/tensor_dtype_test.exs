defmodule Tinkex.Types.TensorDtypeTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.TensorDtype

  describe "parse/1" do
    test "parses valid dtypes" do
      assert TensorDtype.parse("int64") == :int64
      assert TensorDtype.parse("float32") == :float32
    end

    test "returns nil for unsupported dtypes" do
      assert TensorDtype.parse("float64") == nil
      assert TensorDtype.parse("int32") == nil
    end

    test "returns nil for nil input" do
      assert TensorDtype.parse(nil) == nil
    end
  end

  describe "to_string/1" do
    test "converts atoms to wire format strings" do
      assert TensorDtype.to_string(:int64) == "int64"
      assert TensorDtype.to_string(:float32) == "float32"
    end
  end

  describe "from_nx_type/1" do
    test "maps float types" do
      assert TensorDtype.from_nx_type({:f, 32}) == :float32
      assert TensorDtype.from_nx_type({:f, 64}) == :float32
    end

    test "maps integer types" do
      assert TensorDtype.from_nx_type({:s, 64}) == :int64
      assert TensorDtype.from_nx_type({:s, 32}) == :int64
    end

    test "maps unsigned to int64" do
      assert TensorDtype.from_nx_type({:u, 8}) == :int64
      assert TensorDtype.from_nx_type({:u, 16}) == :int64
      assert TensorDtype.from_nx_type({:u, 32}) == :int64
    end
  end

  describe "to_nx_type/1" do
    test "converts dtype to Nx type" do
      assert TensorDtype.to_nx_type(:float32) == {:f, 32}
      assert TensorDtype.to_nx_type(:int64) == {:s, 64}
    end
  end
end
