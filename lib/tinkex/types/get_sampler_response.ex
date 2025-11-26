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

  @enforce_keys [:sampler_id, :base_model]
  defstruct [:sampler_id, :base_model, :model_path]

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
  def from_json(%{"sampler_id" => sampler_id, "base_model" => base_model} = json) do
    %__MODULE__{
      sampler_id: sampler_id,
      base_model: base_model,
      model_path: json["model_path"]
    }
  end

  def from_json(%{sampler_id: sampler_id, base_model: base_model} = json) do
    %__MODULE__{
      sampler_id: sampler_id,
      base_model: base_model,
      model_path: json[:model_path]
    }
  end
end

defimpl Jason.Encoder, for: Tinkex.Types.GetSamplerResponse do
  def encode(resp, opts) do
    map = %{
      sampler_id: resp.sampler_id,
      base_model: resp.base_model
    }

    map =
      if resp.model_path do
        Map.put(map, :model_path, resp.model_path)
      else
        map
      end

    Jason.Encode.map(map, opts)
  end
end
