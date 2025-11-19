defmodule Tinkex.Types.SampleResponseTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.SampleResponse

  describe "from_json/1" do
    test "converts nested topk logprob entries into tuples" do
      json = %{
        "sequences" => [
          %{
            "tokens" => [1, 2],
            "logprobs" => [-1.0, -2.0],
            "stop_reason" => "stop"
          }
        ],
        "prompt_logprobs" => [nil, -0.2],
        "topk_prompt_logprobs" => [
          [
            [123, -0.9],
            [456, -1.5]
          ],
          nil
        ],
        "type" => "sample"
      }

      response = SampleResponse.from_json(json)

      assert response.topk_prompt_logprobs == [
               [{123, -0.9}, {456, -1.5}],
               nil
             ]
    end
  end
end
