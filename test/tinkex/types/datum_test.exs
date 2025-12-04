defmodule Tinkex.Types.DatumTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{Datum, TensorData}

  describe "loss_fn_inputs list handling" do
    test "applies Python key-based dtype map for known keys" do
      datum =
        Datum.new(%{
          model_input: %{chunks: []},
          loss_fn_inputs: %{
            "weights" => [1, 2, 3],
            "target_tokens" => [9, 8]
          }
        })

      assert %TensorData{dtype: :float32, data: [1, 2, 3]} = datum.loss_fn_inputs["weights"]
      assert %TensorData{dtype: :int64, data: [9, 8]} = datum.loss_fn_inputs["target_tokens"]
    end

    test "raises on list under unknown key (parity with Python KeyError)" do
      assert_raise ArgumentError, fn ->
        Datum.new(%{
          model_input: %{chunks: []},
          loss_fn_inputs: %{
            "custom_penalty" => [0.1, 0.2]
          }
        })
      end
    end

    test "allows tensors for custom keys" do
      tensor = Nx.tensor([1, 2, 3], type: :s64)

      datum =
        Datum.new(%{
          model_input: %{chunks: []},
          loss_fn_inputs: %{
            "custom_penalty" => tensor
          }
        })

      assert %TensorData{dtype: :int64, data: [1, 2, 3]} = datum.loss_fn_inputs["custom_penalty"]
    end
  end
end
