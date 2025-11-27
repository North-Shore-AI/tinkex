defmodule Tinkex.Types.SampleRequest do
  @moduledoc """
  Request for sampling/text generation.

  Mirrors Python tinker.types.SampleRequest.

  Supports two modes:
  - Mode 1: Via sampling session (sampling_session_id)
  - Mode 2: Direct model specification (base_model or model_path)

  CRITICAL: prompt_logprobs is Optional[bool] = None, NOT bool = False.
  This is a tri-state field where nil means "not set" and must be omitted from JSON.
  """

  alias Tinkex.Types.{ModelInput, SamplingParams}

  @enforce_keys [:prompt, :sampling_params]
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

defimpl Jason.Encoder, for: Tinkex.Types.SampleRequest do
  def encode(request, opts) do
    # Start with required fields
    map = %{
      prompt: request.prompt,
      sampling_params: request.sampling_params,
      num_samples: request.num_samples,
      topk_prompt_logprobs: request.topk_prompt_logprobs,
      type: request.type
    }

    # Add optional fields only if non-nil
    map =
      if request.sampling_session_id,
        do: Map.put(map, :sampling_session_id, request.sampling_session_id),
        else: map

    map = if request.seq_id, do: Map.put(map, :seq_id, request.seq_id), else: map
    map = if request.base_model, do: Map.put(map, :base_model, request.base_model), else: map
    map = if request.model_path, do: Map.put(map, :model_path, request.model_path), else: map

    # prompt_logprobs is tri-state: true, false, or nil (omitted)
    map =
      if is_boolean(request.prompt_logprobs),
        do: Map.put(map, :prompt_logprobs, request.prompt_logprobs),
        else: map

    Jason.Encode.map(map, opts)
  end
end
