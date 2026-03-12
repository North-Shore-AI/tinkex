defmodule Tinkex.Tokenizer.EncodeTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation
  alias Tinkex.Generated.Types.{GetInfoResponse, ModelData}
  alias Tinkex.Tokenizer

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

  test "get_tokenizer_id handles typed GetInfoResponse" do
    info_fun = fn _client ->
      {:ok,
       %GetInfoResponse{
         model_id: "model-1",
         model_data: %ModelData{tokenizer_id: "struct/tokenizer"}
       }}
    end

    assert "struct/tokenizer" =
             Tokenizer.get_tokenizer_id("fallback-model", :client_pid, info_fun: info_fun)
  end

  test "get_tokenizer_id applies Llama-3 hack" do
    assert "thinkingmachineslabinc/meta-llama-3-tokenizer" ==
             Tokenizer.get_tokenizer_id("meta-llama/Llama-3-8B-Instruct")
  end
end
