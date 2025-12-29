defmodule Tinkex.Types.GetSamplerResponse do
  @moduledoc """
  Response from the get_sampler API call.

  Mirrors Python `tinker.types.GetSamplerResponse`.

  ## Fields

  - `sampler_id` - The sampler ID (sampling_session_id)
  - `base_model` - The base model name
  - `model_path` - Optional tinker:// path to custom weights

  ## Wire Format

  ```json
  {
    "sampler_id": "session-id:sample:0",
    "base_model": "Qwen/Qwen2.5-7B",
    "model_path": "tinker://run-id/weights/checkpoint-001"
  }
  ```

  ## Examples

      iex> json = %{"sampler_id" => "sess:sample:0", "base_model" => "Qwen/Qwen2.5-7B"}
      iex> Tinkex.Types.GetSamplerResponse.from_json(json)
      %Tinkex.Types.GetSamplerResponse{sampler_id: "sess:sample:0", base_model: "Qwen/Qwen2.5-7B", model_path: nil}

  ## See Also

  - `Tinkex.API.Rest.get_sampler/2`
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:sampler_id, :base_model]
  defstruct [:sampler_id, :base_model, :model_path]

  @schema Schema.define([
            {:sampler_id, :string, [required: true]},
            {:base_model, :string, [required: true]},
            {:model_path, :string, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          sampler_id: String.t(),
          base_model: String.t(),
          model_path: String.t() | nil
        }

  @doc """
  Create a GetSamplerResponse from a JSON map.

  Handles both string and atom keys.

  ## Parameters

  - `json` - Map with keys `"sampler_id"`/`:sampler_id`, `"base_model"`/`:base_model`,
    and optionally `"model_path"`/`:model_path`

  ## Examples

      iex> GetSamplerResponse.from_json(%{"sampler_id" => "s1", "base_model" => "Qwen", "model_path" => "tinker://..."})
      %GetSamplerResponse{sampler_id: "s1", base_model: "Qwen", model_path: "tinker://..."}

      iex> GetSamplerResponse.from_json(%{sampler_id: "s1", base_model: "Qwen"})
      %GetSamplerResponse{sampler_id: "s1", base_model: "Qwen", model_path: nil}
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.GetSamplerResponse do
  def encode(resp, opts) do
    resp
    |> Tinkex.SchemaCodec.omit_nil_fields([:model_path])
    |> Tinkex.SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end
end
