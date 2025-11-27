defmodule Tinkex.Types.Cursor do
  @moduledoc """
  Pagination cursor for paged responses.
  """

  @enforce_keys [:offset, :limit, :total_count]
  defstruct [:offset, :limit, :total_count]

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          limit: non_neg_integer(),
          total_count: non_neg_integer()
        }

  @doc """
  Parse a Cursor from a map.
  """
  @spec from_map(map() | nil) :: t() | nil
  def from_map(nil), do: nil
  def from_map(map) when not is_map(map), do: nil

  def from_map(map) when is_map(map) do
    %__MODULE__{
      offset: fetch_int(map, "offset"),
      limit: fetch_int(map, "limit"),
      total_count: fetch_int(map, "total_count")
    }
  end

  defp fetch_int(map, key) do
    case map[key] || map[String.to_atom(key)] do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, _} -> int
          :error -> 0
        end

      _ ->
        0
    end
  end
end
