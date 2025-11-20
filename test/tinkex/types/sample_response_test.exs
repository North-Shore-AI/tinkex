defmodule Tinkex.Types.SampleResponseTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

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

    test "accepts map entries and empty inner lists" do
      json = %{
        "sequences" => [
          %{"tokens" => [], "logprobs" => nil, "stop_reason" => nil}
        ],
        "topk_prompt_logprobs" => [
          [%{"token_id" => 42, "logprob" => -0.5}],
          []
        ]
      }

      response = SampleResponse.from_json(json)

      assert response.topk_prompt_logprobs == [
               [{42, -0.5}],
               []
             ]
    end

    test "raises for malformed entries" do
      json = %{
        "sequences" => [
          %{"tokens" => [], "logprobs" => nil, "stop_reason" => nil}
        ],
        "topk_prompt_logprobs" => [
          [["bad"]]
        ]
      }

      assert_raise ArgumentError, fn ->
        SampleResponse.from_json(json)
      end
    end
  end
end
