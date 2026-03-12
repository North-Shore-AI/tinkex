defmodule Tinkex.TokenizerRef do
  @moduledoc false

  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(reference) when is_binary(reference) do
    case String.split(reference, ":", parts: 2) do
      [normalized | _rest] -> normalized
      [] -> reference
    end
  end
end
