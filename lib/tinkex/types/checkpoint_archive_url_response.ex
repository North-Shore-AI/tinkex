defmodule Tinkex.Types.CheckpointArchiveUrlResponse do
  @moduledoc """
  Response containing a download URL for a checkpoint archive.
  """

  @type t :: %__MODULE__{
          url: String.t(),
          expires: DateTime.t() | String.t() | nil
        }

  defstruct [:url, :expires]

  @doc """
  Convert a map (from JSON) to a CheckpointArchiveUrlResponse struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      url: map["url"] || map[:url],
      expires: parse_expires(map["expires"] || map[:expires])
    }
  end

  defp parse_expires(nil), do: nil
  defp parse_expires(%DateTime{} = dt), do: dt

  defp parse_expires(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> value
    end
  end

  defp parse_expires(other), do: other
end
