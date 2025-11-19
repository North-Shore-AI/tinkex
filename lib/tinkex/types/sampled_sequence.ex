defmodule Tinkex.Types.SampledSequence do
  @moduledoc """
  A single sampled sequence from text generation.

  Mirrors Python tinker.types.SampledSequence.
  """

  alias Tinkex.Types.StopReason

  defstruct [:tokens, :logprobs, :stop_reason]

  @type t :: %__MODULE__{
          tokens: [integer()],
          logprobs: [float()] | nil,
          stop_reason: StopReason.t() | nil
        }

  @doc """
  Parse a sampled sequence from JSON response.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      tokens: json["tokens"],
      logprobs: json["logprobs"],
      stop_reason: StopReason.parse(json["stop_reason"])
    }
  end
end
