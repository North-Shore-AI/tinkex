defmodule Tinkex.Types.ModelInputFromTextTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.{EncodedTextChunk, ModelInput}
  alias Tinkex.{Error, Tokenizer}

  setup do
    ensure_table()
    {:ok, _} = Application.ensure_all_started(:tokenizers)
    :ok
  end

  test "errors when model_name is missing" do
    assert {:error, %Error{message: message, type: :validation}} =
             ModelInput.from_text("hello", [])

    assert message =~ "model_name"

    assert_raise ArgumentError, fn ->
      ModelInput.from_text!("hello", [])
    end
  end

  @tag :network
  test "encodes text into an encoded_text chunk" do
    text = "Hello tokenizer"
    model_name = "gpt2"

    assert {:ok, expected_ids} = Tokenizer.encode(text, model_name)

    assert {:ok,
            %ModelInput{chunks: [%EncodedTextChunk{tokens: tokens, type: "encoded_text"}]} =
              model_input} = ModelInput.from_text(text, model_name: model_name)

    assert tokens == expected_ids
    assert ModelInput.length(model_input) == length(tokens)
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
