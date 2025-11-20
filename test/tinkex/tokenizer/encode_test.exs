defmodule Tinkex.Tokenizer.EncodeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Tokenizer
  alias Tokenizers.Tokenizer, as: HFTokenizer

  setup do
    ensure_table()
    :ets.delete_all_objects(:tinkex_tokenizers)
    {:ok, _} = Application.ensure_all_started(:tokenizers)
    :ok
  end

  test "get_tokenizer_id uses training client info when provided" do
    parent = self()

    info_fun = fn client ->
      send(parent, {:info_called, client})
      {:ok, %{model_data: %{tokenizer_id: "custom/tokenizer"}}}
    end

    assert "custom/tokenizer" =
             Tokenizer.get_tokenizer_id("fallback-model", :client_pid, info_fun: info_fun)

    assert_receive {:info_called, :client_pid}
  end

  test "get_tokenizer_id applies Llama-3 hack" do
    assert "baseten/Meta-Llama-3-tokenizer" ==
             Tokenizer.get_tokenizer_id("Llama-3-8B-Instruct")
  end

  @tag :network
  test "encode caches tokenizer by resolved id" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    on_exit(fn ->
      if Process.alive?(counter) do
        Agent.stop(counter)
      end
    end)

    load_fun = fn id ->
      Agent.update(counter, &(&1 + 1))
      HFTokenizer.from_pretrained(id)
    end

    model_name = "gpt2"

    assert {:ok, ids1} = Tokenizer.encode("cache test", model_name, load_fun: load_fun)
    assert is_list(ids1)
    assert Enum.all?(ids1, &is_integer/1)

    assert {:ok, ids2} = Tokenizer.encode("cache test", model_name, load_fun: load_fun)
    assert ids1 == ids2

    assert Agent.get(counter, & &1) == 1
    assert [{^model_name, _}] = :ets.lookup(:tinkex_tokenizers, model_name)
  end

  defp ensure_table do
    case :ets.whereis(:tinkex_tokenizers) do
      :undefined ->
        :ets.new(:tinkex_tokenizers, [:set, :public, :named_table, read_concurrency: true])

      _ ->
        :ok
    end
  end
end
