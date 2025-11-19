defmodule Tinkex.Types.CreateSamplingSessionResponse do
  @moduledoc """
  Response from create sampling session request.

  Mirrors Python tinker.types.CreateSamplingSessionResponse.
  """

  @enforce_keys [:sampling_session_id]
  defstruct [:sampling_session_id]

  @type t :: %__MODULE__{
          sampling_session_id: String.t()
        }

  @doc """
  Parse a create sampling session response from JSON.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    %__MODULE__{
      sampling_session_id: json["sampling_session_id"]
    }
  end
end
