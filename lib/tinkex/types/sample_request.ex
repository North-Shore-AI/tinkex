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

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
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

  @schema Schema.define([
            {:sampling_session_id, :string, [optional: true]},
            {:seq_id, :integer, [optional: true]},
            {:base_model, :string, [optional: true]},
            {:model_path, :string, [optional: true]},
            {:prompt, {:object, ModelInput.schema()}, [required: true]},
            {:sampling_params, {:object, SamplingParams.schema()}, [required: true]},
            {:num_samples, :integer, [optional: true, default: 1]},
            {:prompt_logprobs, {:nullable, :boolean}, [optional: true]},
            {:topk_prompt_logprobs, :integer, [optional: true, default: 0]},
            {:type, :string, [optional: true, default: "sample"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

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
  alias Tinkex.SchemaCodec

  def encode(request, opts) do
    request
    |> SchemaCodec.omit_nil_fields([
      :sampling_session_id,
      :seq_id,
      :base_model,
      :model_path,
      :prompt_logprobs
    ])
    |> SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end
end
