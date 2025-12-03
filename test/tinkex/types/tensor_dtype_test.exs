defmodule Tinkex.Types.TensorDtypeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation
  import ExUnit.CaptureLog

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
    test "maps float32 directly" do
      assert TensorDtype.from_nx_type({:f, 32}) == :float32
    end

    test "maps float64 to float32 with warning" do
      log =
        capture_log(fn ->
          assert TensorDtype.from_nx_type({:f, 64}) == :float32
        end)

      assert log =~ "Downcasting float64 to float32"
      assert log =~ "precision loss"
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

    test "warns when converting u64 (potential overflow)" do
      log =
        capture_log(fn ->
          assert TensorDtype.from_nx_type({:u, 64}) == :int64
        end)

      assert log =~ "u64 to int64"
      assert log =~ "overflow"
    end
  end

  describe "from_nx_type_quiet/1" do
    test "maps without warnings" do
      log =
        capture_log(fn ->
          assert TensorDtype.from_nx_type_quiet({:f, 64}) == :float32
          assert TensorDtype.from_nx_type_quiet({:u, 64}) == :int64
        end)

      refute log =~ "Downcasting"
      refute log =~ "overflow"
    end

    test "maps all types correctly" do
      assert TensorDtype.from_nx_type_quiet({:f, 32}) == :float32
      assert TensorDtype.from_nx_type_quiet({:f, 64}) == :float32
      assert TensorDtype.from_nx_type_quiet({:s, 64}) == :int64
      assert TensorDtype.from_nx_type_quiet({:s, 32}) == :int64
      assert TensorDtype.from_nx_type_quiet({:u, 8}) == :int64
    end
  end

  describe "check_precision_loss/1" do
    test "returns :ok for safe conversions" do
      assert TensorDtype.check_precision_loss({:f, 32}) == :ok
      assert TensorDtype.check_precision_loss({:s, 64}) == :ok
      assert TensorDtype.check_precision_loss({:s, 32}) == :ok
      assert TensorDtype.check_precision_loss({:u, 32}) == :ok
    end

    test "returns {:downcast, reason} for float64" do
      assert {:downcast, reason} = TensorDtype.check_precision_loss({:f, 64})
      assert reason =~ "float64 to float32"
      assert reason =~ "precision loss"
    end

    test "returns {:downcast, reason} for u64" do
      assert {:downcast, reason} = TensorDtype.check_precision_loss({:u, 64})
      assert reason =~ "u64 to int64"
      assert reason =~ "overflow"
    end
  end

  describe "to_nx_type/1" do
    test "converts dtype to Nx type" do
      assert TensorDtype.to_nx_type(:float32) == {:f, 32}
      assert TensorDtype.to_nx_type(:int64) == {:s, 64}
    end
  end
end
