defmodule Tinkex.Types.GetServerCapabilitiesResponse do
  @moduledoc """
  Supported model metadata returned by the service capabilities endpoint.
  """

  @enforce_keys [:supported_models]
  defstruct [:supported_models]

  @type t :: %__MODULE__{
          supported_models: [String.t()]
        }

  @doc """
  Parse from JSON map with string or atom keys.
  """
  @spec from_json(map()) :: t()
  def from_json(map) when is_map(map) do
    models = map["supported_models"] || map[:supported_models] || []

    names =
      models
      |> Enum.map(fn
        %{"model_name" => name} -> name
        %{model_name: name} -> name
        name when is_binary(name) -> name
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    %__MODULE__{supported_models: names}
  end
end
