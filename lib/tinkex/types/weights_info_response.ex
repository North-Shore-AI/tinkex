defmodule Tinkex.Types.WeightsInfoResponse do
  @moduledoc """
  Minimal information for loading public checkpoints.

  Mirrors Python `tinker.types.WeightsInfoResponse`.

  ## Fields

  - `base_model` - The base model name (e.g., "Qwen/Qwen2.5-7B")
  - `is_lora` - Whether this checkpoint uses LoRA
  - `lora_rank` - The LoRA rank, if applicable (nil for non-LoRA checkpoints)

  ## Wire Format

  ```json
  {
    "base_model": "Qwen/Qwen2.5-7B",
    "is_lora": true,
    "lora_rank": 32
  }
  ```

  ## Examples

      iex> json = %{"base_model" => "Qwen/Qwen2.5-7B", "is_lora" => true, "lora_rank" => 32}
      iex> Tinkex.Types.WeightsInfoResponse.from_json(json)
      %Tinkex.Types.WeightsInfoResponse{base_model: "Qwen/Qwen2.5-7B", is_lora: true, lora_rank: 32}

  ## See Also

  - `Tinkex.API.Rest.get_weights_info_by_tinker_path/2`
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec

  @enforce_keys [:base_model, :is_lora]
  defstruct [:base_model, :is_lora, :lora_rank]

  @schema Schema.define([
            {:base_model, :string, [required: true]},
            {:is_lora, :boolean, [required: true]},
            {:lora_rank, :integer, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          base_model: String.t(),
          is_lora: boolean(),
          lora_rank: non_neg_integer() | nil
        }

  @doc """
  Create a WeightsInfoResponse from a JSON map.

  Handles both string and atom keys.

  ## Parameters

  - `json` - Map with keys `"base_model"`/`:base_model`, `"is_lora"`/`:is_lora`,
    and optionally `"lora_rank"`/`:lora_rank`

  ## Examples

      iex> WeightsInfoResponse.from_json(%{"base_model" => "Qwen", "is_lora" => true, "lora_rank" => 32})
      %WeightsInfoResponse{base_model: "Qwen", is_lora: true, lora_rank: 32}

      iex> WeightsInfoResponse.from_json(%{base_model: "Qwen", is_lora: false})
      %WeightsInfoResponse{base_model: "Qwen", is_lora: false, lora_rank: nil}
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    SchemaCodec.decode_struct(schema(), json, struct(__MODULE__), coerce: true)
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.WeightsInfoResponse do
  def encode(resp, opts) do
    resp
    |> Tinkex.SchemaCodec.omit_nil_fields([:lora_rank])
    |> Tinkex.SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end
end
