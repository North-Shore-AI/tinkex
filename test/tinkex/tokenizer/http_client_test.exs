defmodule Tinkex.Tokenizer.HTTPClientTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Tokenizer

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ets.delete_all_objects(:tinkex_tokenizers)
    :ok
  end

  test "passes an escript-safe HTTP client to tokenizers loaders" do
    tokenizer_id = "gpt2"
    parent = self()

    load_fun = fn id, opts ->
      send(parent, {:load_opts, id, opts})
      {:error, :boom}
    end

    assert {:error, %Tinkex.Error{}} =
             Tokenizer.get_or_load_tokenizer(tokenizer_id, load_fun: load_fun)

    assert_received {:load_opts, ^tokenizer_id, opts}
    assert {Tinkex.Tokenizer.HTTPClient, []} == Keyword.fetch!(opts, :http_client)
  end
end
