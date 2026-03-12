defmodule Tinkex.Generated.Types.SampleRequest do
  @moduledoc """
  SampleRequest type.
  """

  defstruct [
    :base_model,
    :model_path,
    :num_samples,
    :prompt,
    :prompt_logprobs,
    :sampling_params,
    :sampling_session_id,
    :seq_id,
    :topk_prompt_logprobs,
    :type
  ]

  @type t :: %__MODULE__{
          base_model: term() | nil,
          model_path: term() | nil,
          num_samples: term() | nil,
          prompt: term(),
          prompt_logprobs: term() | nil,
          sampling_params: term(),
          sampling_session_id: term() | nil,
          seq_id: term() | nil,
          topk_prompt_logprobs: term() | nil,
          type: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:base_model, :any, [optional: true]},
      {:model_path, :any, [optional: true]},
      {:num_samples, :any, [optional: true]},
      {:prompt, :any, [required: true]},
      {:prompt_logprobs, :any, [optional: true]},
      {:sampling_params, :any, [required: true]},
      {:sampling_session_id, :any, [optional: true]},
      {:seq_id, :any, [optional: true]},
      {:topk_prompt_logprobs, :any, [optional: true]},
      {:type, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.SampleRequest struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         base_model: validated["base_model"],
         model_path: validated["model_path"],
         num_samples: validated["num_samples"],
         prompt: validated["prompt"],
         prompt_logprobs: validated["prompt_logprobs"],
         sampling_params: validated["sampling_params"],
         sampling_session_id: validated["sampling_session_id"],
         seq_id: validated["seq_id"],
         topk_prompt_logprobs: validated["topk_prompt_logprobs"],
         type: validated["type"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.SampleRequest struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "base_model" => struct.base_model,
      "model_path" => struct.model_path,
      "num_samples" => struct.num_samples,
      "prompt" => struct.prompt,
      "prompt_logprobs" => struct.prompt_logprobs,
      "sampling_params" => struct.sampling_params,
      "sampling_session_id" => struct.sampling_session_id,
      "seq_id" => struct.seq_id,
      "topk_prompt_logprobs" => struct.topk_prompt_logprobs,
      "type" => struct.type
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.SampleRequest from a map."
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data) do
    struct(__MODULE__, atomize_keys(data))
  end

  @doc "Convert to a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.SampleRequest."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ [])
  def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
  def new(attrs) when is_map(attrs), do: from_map(attrs)

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
