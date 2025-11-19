defmodule Tinkex.Types.SampleResponse do
  @moduledoc """
  Response from sampling/text generation request.

  Mirrors Python tinker.types.SampleResponse.
  """

  alias Tinkex.Types.SampledSequence

  defstruct [:sequences, :prompt_logprobs, :topk_prompt_logprobs, type: "sample"]

  @type topk_entry :: {integer(), float()}
  @type t :: %__MODULE__{
          sequences: [SampledSequence.t()],
          prompt_logprobs: [float() | nil] | nil,
          topk_prompt_logprobs: [[topk_entry()] | nil] | nil,
          type: String.t()
        }

  @doc """
  Parse a sample response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    sequences =
      json["sequences"]
      |> Enum.map(&SampledSequence.from_json/1)

    %__MODULE__{
      sequences: sequences,
      prompt_logprobs: json["prompt_logprobs"],
      topk_prompt_logprobs: json["topk_prompt_logprobs"],
      type: json["type"] || "sample"
    }
  end
end
