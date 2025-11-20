defmodule Tinkex.Tokenizer.NifSafetyTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tokenizers.{Encoding, Tokenizer}

  @moduletag :network
  @table_name :tinkex_tokenizers_nif_safety
  @tokenizer_id "gpt2"

  setup do
    {:ok, _} = Application.ensure_all_started(:tokenizers)

    drop_table(@table_name)
    :ets.new(@table_name, [:set, :public, :named_table])

    on_exit(fn -> drop_table(@table_name) end)
    :ok
  end

  test "tokenizer handles are usable across processes via ETS" do
    {:ok, tokenizer} = Tokenizer.from_pretrained(@tokenizer_id)
    :ets.insert(@table_name, {@tokenizer_id, tokenizer})

    task =
      Task.async(fn ->
        [{@tokenizer_id, tok}] = :ets.lookup(@table_name, @tokenizer_id)
        {:ok, encoding} = Tokenizer.encode(tok, "hello from another process")
        ids = Encoding.get_ids(encoding)

        assert is_list(ids)
        assert Enum.all?(ids, &is_integer/1)

        {:ok, ids}
      end)

    assert {:ok, _ids} = Task.await(task, 15_000)
  end

  defp drop_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ok
      tid -> :ets.delete(tid)
    end
  end
end
