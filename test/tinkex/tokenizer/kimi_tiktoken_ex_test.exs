defmodule Tinkex.Tokenizer.KimiTikTokenExTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias TiktokenEx.Encoding, as: TikEncoding
  alias Tinkex.Tokenizer

  @kimi_tokenizer "moonshotai/Kimi-K2-Thinking"

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ets.delete_all_objects(:tinkex_tokenizers)
    :ok
  end

  test "uses tiktoken_ex for Kimi encode/decode (no network)" do
    with_tmp_dir(fn dir ->
      model_path = Path.join(dir, "tiktoken.model")
      config_path = Path.join(dir, "tokenizer_config.json")

      ranks = [
        {"S", 0},
        {"a", 1},
        {"y", 2},
        {" ", 3},
        {"h", 4},
        {"i", 5}
      ]

      model_contents =
        ranks
        |> Enum.map(fn {token, rank} ->
          Base.encode64(token) <> " " <> Integer.to_string(rank)
        end)
        |> Enum.join("\n")
        |> Kernel.<>("\n")

      File.write!(model_path, model_contents)

      config = %{
        "added_tokens_decoder" => %{
          "6" => %{"content" => "<|bos|>"}
        }
      }

      File.write!(config_path, Jason.encode!(config))

      opts = [tiktoken_model_path: model_path, tokenizer_config_path: config_path]

      assert {:ok, %TikEncoding{} = _enc} = Tokenizer.get_or_load_tokenizer(@kimi_tokenizer, opts)

      assert {:ok, [0, 1, 2, 3, 4, 5]} = Tokenizer.encode("Say hi", @kimi_tokenizer, opts)
      assert {:ok, "Say hi"} = Tokenizer.decode([0, 1, 2, 3, 4, 5], @kimi_tokenizer, opts)

      assert {:ok, [6, 0, 1, 2]} = Tokenizer.encode("<|bos|>Say", @kimi_tokenizer, opts)
      assert {:ok, "<|bos|>Say"} = Tokenizer.decode([6, 0, 1, 2], @kimi_tokenizer, opts)

      assert [{@kimi_tokenizer, %TikEncoding{}}] =
               :ets.lookup(:tinkex_tokenizers, @kimi_tokenizer)

      {:ok, _} = Tokenizer.get_or_load_tokenizer(@kimi_tokenizer, opts)
    end)
  end

  defp with_tmp_dir(fun) when is_function(fun, 1) do
    dir =
      Path.join(System.tmp_dir!(), "tinkex_kimi_tiktoken_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      _ = File.rm_rf(dir)
    end
  end
end
