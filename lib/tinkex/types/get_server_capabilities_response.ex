defmodule Tinkex.Types.GetServerCapabilitiesResponse do
  @moduledoc """
  Supported model metadata returned by the service capabilities endpoint.

  Contains a list of `SupportedModel` structs with full metadata including
  model IDs, names, and architecture types.

  ## Migration Note

  Prior versions stored only model names as strings. The new structure
  provides richer metadata while maintaining backward compatibility for
  parsing responses.
  """

  alias Tinkex.Types.SupportedModel

  @enforce_keys [:supported_models]
  defstruct [:supported_models]

  @type t :: %__MODULE__{
          supported_models: [SupportedModel.t()]
        }

  @doc """
  Parse from JSON map with string or atom keys.

  Handles various input formats for backward compatibility:
  - Array of model objects with metadata fields
  - Array of plain strings (legacy format)
  - Mixed arrays
  """
  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    models = map["supported_models"] || map[:supported_models] || []

    parsed_models =
      models
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&SupportedModel.from_json/1)

    %__MODULE__{supported_models: parsed_models}
  end

  @doc """
  Extract just the model names from the response for convenience.

  This is useful for callers who only need the names (legacy behavior).

  ## Example

      iex> response = %GetServerCapabilitiesResponse{
      ...>   supported_models: [
      ...>     %SupportedModel{model_name: "llama"},
      ...>     %SupportedModel{model_name: "qwen"}
      ...>   ]
      ...> }
      iex> GetServerCapabilitiesResponse.model_names(response)
      ["llama", "qwen"]
  """
  @spec model_names(t()) :: [String.t() | nil]
  def model_names(%__MODULE__{supported_models: models}) do
    Enum.map(models, & &1.model_name)
  end
end
