defmodule Tinkex.Types.SupportedModel do
  @moduledoc """
  Metadata for a single supported model from the server capabilities response.

  ## Fields

  - `model_id` - Short identifier (e.g., "llama-3-8b")
  - `model_name` - Full model path (e.g., "meta-llama/Meta-Llama-3-8B")
  - `arch` - Architecture type (e.g., "llama", "qwen2")

  ## Example

      iex> json = %{
      ...>   "model_id" => "llama-3-8b",
      ...>   "model_name" => "meta-llama/Meta-Llama-3-8B",
      ...>   "arch" => "llama"
      ...> }
      iex> model = Tinkex.Types.SupportedModel.from_json(json)
      iex> model.model_id
      "llama-3-8b"
      iex> model.arch
      "llama"
  """

  defstruct [:model_id, :model_name, :arch]

  @type t :: %__MODULE__{
          model_id: String.t() | nil,
          model_name: String.t() | nil,
          arch: String.t() | nil
        }

  @doc """
  Parse a supported model from JSON map with string or atom keys.

  Falls back gracefully if given a plain string (treats as model_name).
  Unknown fields are ignored without error.
  """
  @spec from_json(map() | String.t()) :: t()
  def from_json(json) when is_map(json) do
    %__MODULE__{
      model_id: json["model_id"] || json[:model_id],
      model_name: json["model_name"] || json[:model_name],
      arch: json["arch"] || json[:arch]
    }
  end

  def from_json(name) when is_binary(name) do
    # Backward compatibility: plain string becomes model_name
    %__MODULE__{model_name: name}
  end
end
