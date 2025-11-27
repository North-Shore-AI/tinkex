defmodule Tinkex.Multipart.FormSerializer do
  @moduledoc """
  Flatten maps into multipart form fields using bracket notation.
  """

  @spec serialize_form_fields(map() | nil) :: map()
  def serialize_form_fields(nil), do: %{}

  def serialize_form_fields(%{} = data) do
    data
    |> do_serialize([])
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case Map.get(acc, key) do
        nil -> Map.put(acc, key, value)
        existing when is_list(existing) -> Map.put(acc, key, existing ++ [value])
        existing -> Map.put(acc, key, [existing, value])
      end
    end)
  end

  def serialize_form_fields(_other), do: %{}

  defp do_serialize(%{} = data, path) do
    Enum.flat_map(data, fn {key, value} ->
      do_serialize(value, path ++ [normalize_key(key)])
    end)
  end

  defp do_serialize(list, path) when is_list(list) do
    Enum.flat_map(list, fn value ->
      do_serialize(value, path ++ ["[]"])
    end)
  end

  defp do_serialize(value, path) do
    [{build_key(path), normalize_value(value)}]
  end

  defp build_key([first | rest]) do
    Enum.reduce(rest, first, fn segment, acc ->
      if segment == "[]" do
        acc <> segment
      else
        acc <> "[#{segment}]"
      end
    end)
  end

  defp build_key([]), do: ""

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(other), do: to_string(other)

  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_nil(value), do: ""
  defp normalize_value(value), do: to_string(value)
end
