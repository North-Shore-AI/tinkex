defmodule Tinkex.Types.SampleRequest do
  @moduledoc """
  Request for sampling/text generation.

  Mirrors Python tinker.types.SampleRequest.

  Supports two modes:
  - Mode 1: Via sampling session (sampling_session_id)
  - Mode 2: Direct model specification (base_model or model_path)

  CRITICAL: prompt_logprobs is Optional[bool] = None, NOT bool = False.
  This is a tri-state field where nil means "not set".
  """

  alias Tinkex.Types.{ModelInput, SamplingParams}

  @derive {Jason.Encoder,
           only: [
             :sampling_session_id,
             :seq_id,
             :base_model,
             :model_path,
             :prompt,
             :sampling_params,
             :num_samples,
             :prompt_logprobs,
             :topk_prompt_logprobs,
             :type
           ]}
  defstruct [
    :sampling_session_id,
    :seq_id,
    :base_model,
    :model_path,
    :prompt,
    :sampling_params,
    num_samples: 1,
    prompt_logprobs: nil,
    topk_prompt_logprobs: 0,
    type: "sample"
  ]

  @type t :: %__MODULE__{
          sampling_session_id: String.t() | nil,
          seq_id: integer() | nil,
          base_model: String.t() | nil,
          model_path: String.t() | nil,
          prompt: ModelInput.t(),
          sampling_params: SamplingParams.t(),
          num_samples: pos_integer(),
          prompt_logprobs: boolean() | nil,
          topk_prompt_logprobs: non_neg_integer(),
          type: String.t()
        }
end
