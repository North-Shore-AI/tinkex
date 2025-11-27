defmodule Tinkex.Types.SampleRequestTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.{SampleRequest, ModelInput, SamplingParams}

  describe "JSON encoding" do
    test "omits prompt_logprobs when nil" do
      req = %SampleRequest{
        num_samples: 1,
        prompt: ModelInput.from_ints([1, 2, 3]),
        sampling_params: %SamplingParams{max_tokens: 100},
        prompt_logprobs: nil,
        type: "sample"
      }

      json = Jason.encode!(req)
      decoded = Jason.decode!(json)

      # nil should be omitted from JSON, not encoded as null
      # (server rejects null values for prompt_logprobs)
      refute Map.has_key?(decoded, "prompt_logprobs")
    end

    test "encodes prompt_logprobs false correctly" do
      req = %SampleRequest{
        num_samples: 1,
        prompt: ModelInput.from_ints([1, 2, 3]),
        sampling_params: %SamplingParams{max_tokens: 100},
        prompt_logprobs: false,
        type: "sample"
      }

      json = Jason.encode!(req)
      decoded = Jason.decode!(json)

      assert decoded["prompt_logprobs"] == false
    end

    test "encodes prompt_logprobs true correctly" do
      req = %SampleRequest{
        num_samples: 1,
        prompt: ModelInput.from_ints([1, 2, 3]),
        sampling_params: %SamplingParams{max_tokens: 100},
        prompt_logprobs: true,
        type: "sample"
      }

      json = Jason.encode!(req)
      decoded = Jason.decode!(json)

      assert decoded["prompt_logprobs"] == true
    end

    test "encodes all required fields" do
      req = %SampleRequest{
        num_samples: 2,
        prompt: ModelInput.from_ints([1, 2]),
        sampling_params: %SamplingParams{},
        type: "sample"
      }

      json = Jason.encode!(req)
      decoded = Jason.decode!(json)

      assert decoded["num_samples"] == 2
      assert decoded["type"] == "sample"
      assert is_map(decoded["prompt"])
      assert is_map(decoded["sampling_params"])
    end
  end
end
