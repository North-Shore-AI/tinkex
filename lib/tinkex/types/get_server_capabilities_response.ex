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

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.SupportedModel

  @enforce_keys [:supported_models]
  defstruct [:supported_models]

  @schema Schema.define([
            {:supported_models,
             {:array, {:union, [:null, :string, {:object, SupportedModel.schema()}]}},
             [optional: true, default: []]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

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
    SchemaCodec.decode_struct(schema(), map, struct(__MODULE__),
      coerce: true,
      converters: %{supported_models: &parse_supported_models/1}
    )
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

  defp parse_supported_models(models) when is_list(models) do
    models
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&SupportedModel.from_json/1)
  end
end
