defmodule Tinkex.Types.SampleResponse do
  @moduledoc """
  Response from sampling/text generation request.

  Mirrors Python tinker.types.SampleResponse.
  """

  alias Tinkex.Types.SampledSequence

  defstruct [:sequences, :prompt_logprobs, :topk_prompt_logprobs, type: "sample"]

  @type topk_entry :: {integer(), float()}
  @type topk_prompt_logprobs :: [nil | [topk_entry()]] | nil
  @type t :: %__MODULE__{
          sequences: [SampledSequence.t()],
          prompt_logprobs: [float() | nil] | nil,
          topk_prompt_logprobs: topk_prompt_logprobs(),
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
      topk_prompt_logprobs: parse_topk_prompt_logprobs(json["topk_prompt_logprobs"]),
      type: json["type"] || "sample"
    }
  end

  defp parse_topk_prompt_logprobs(nil), do: nil

  defp parse_topk_prompt_logprobs(entries) when is_list(entries) do
    Enum.map(entries, fn
      nil ->
        nil

      inner when is_list(inner) ->
        Enum.map(inner, &parse_topk_entry/1)
    end)
  end

  defp parse_topk_entry([token_id, logprob]), do: {token_id, logprob}
  defp parse_topk_entry({token_id, logprob}), do: {token_id, logprob}
  defp parse_topk_entry(%{"token_id" => token_id, "logprob" => logprob}), do: {token_id, logprob}

  defp parse_topk_entry(other) do
    raise ArgumentError, "Invalid topk prompt logprob entry: #{inspect(other)}"
  end
end
