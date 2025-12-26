defmodule Tinkex.Tokenizer.HTTPClientTest do
  use Supertester.ExUnitFoundation,
    isolation: :full_isolation,
    ets_isolation: [:tinkex_tokenizers]

  alias Supertester.ETSIsolation
  alias Tinkex.Tokenizer

  setup %{isolation_context: ctx} do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    tokenizer_cache = Map.fetch!(ctx.isolated_ets_tables, :tinkex_tokenizers)
    {:ok, _} = ETSIsolation.inject_table(Tokenizer, :cache_table, tokenizer_cache, create: false)

    {:ok, tokenizer_cache: tokenizer_cache}
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
