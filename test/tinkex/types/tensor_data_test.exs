defmodule Tinkex.Types.TensorDataTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.TensorData

  describe "from_nx/1" do
    test "converts float64 to float32" do
      tensor = Nx.tensor([1.0, 2.0, 3.0], type: {:f, 64})
      td = TensorData.from_nx(tensor)

      assert td.dtype == :float32
      assert td.data == [1.0, 2.0, 3.0]
      assert td.shape == [3]
    end

    test "converts int32 to int64" do
      tensor = Nx.tensor([1, 2, 3], type: {:s, 32})
      td = TensorData.from_nx(tensor)

      assert td.dtype == :int64
    end

    test "preserves shape for multi-dimensional tensors" do
      tensor = Nx.tensor([[1, 2], [3, 4]], type: {:s, 64})
      td = TensorData.from_nx(tensor)

      assert td.shape == [2, 2]
      assert td.data == [1, 2, 3, 4]
    end

    test "sets shape to nil for scalars" do
      tensor = Nx.tensor(42.5, type: {:f, 64})
      td = TensorData.from_nx(tensor)

      assert td.shape == nil
      assert td.data == [42.5]
    end

    test "raises for unsupported dtypes" do
      tensor = Nx.tensor([1, 2], type: {:bf, 16})

      assert_raise ArgumentError, ~r/Unsupported tensor dtype/, fn ->
        TensorData.from_nx(tensor)
      end
    end
  end

  describe "to_nx/1" do
    test "roundtrips correctly" do
      original = Nx.tensor([1.5, 2.5, 3.5], type: {:f, 32})
      td = TensorData.from_nx(original)
      result = TensorData.to_nx(td)

      assert Nx.to_flat_list(result) == Nx.to_flat_list(original)
    end

    test "handles nil shape as 1D" do
      td = %TensorData{
        data: [1.0, 2.0, 3.0],
        dtype: :float32,
        shape: nil
      }

      result = TensorData.to_nx(td)
      assert Nx.shape(result) == {3}
    end
  end

  describe "tolist/1" do
    test "returns flat data list" do
      td = %TensorData{
        data: [1.0, 2.0, 3.0],
        dtype: :float32,
        shape: [3]
      }

      assert TensorData.tolist(td) == [1.0, 2.0, 3.0]
    end

    test "returns flat data for multi-dimensional tensor" do
      tensor = Nx.tensor([[1, 2], [3, 4]], type: {:s, 64})
      td = TensorData.from_nx(tensor)

      assert TensorData.tolist(td) == [1, 2, 3, 4]
    end

    test "returns single-element list for scalar" do
      tensor = Nx.tensor(42.5, type: {:f, 64})
      td = TensorData.from_nx(tensor)

      assert TensorData.tolist(td) == [42.5]
    end
  end

  describe "JSON encoding" do
    test "encodes to correct wire format" do
      td = %TensorData{
        data: [1.0, 2.0, 3.0],
        dtype: :float32,
        shape: [3]
      }

      json = Jason.encode!(td)
      decoded = Jason.decode!(json)

      assert decoded["dtype"] == "float32"
      assert decoded["data"] == [1.0, 2.0, 3.0]
      assert decoded["shape"] == [3]
    end
  end
end
