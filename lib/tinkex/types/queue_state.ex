defmodule Tinkex.Types.QueueState do
  @moduledoc """
  Queue state parser used by TryAgain responses.

  Mirrors the Python QueueState enum but normalizes strings to atoms. Any
  unknown or missing value becomes `:unknown` instead of defaulting to
  `:active`, which better captures the ambiguity for downstream observers.
  """

  @type t :: :active | :paused_rate_limit | :paused_capacity | :unknown

  @doc """
  Parse queue state strings into atoms.

  Values are case-insensitive and handle strings with underscores or mixed
  casing (e.g. `"PAUSED_RATE_LIMIT"`). Invalid or missing values return
  `:unknown`.
  """
  @spec parse(String.t() | nil) :: t()
  def parse(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "active" -> :active
      "paused_rate_limit" -> :paused_rate_limit
      "paused_capacity" -> :paused_capacity
      _ -> :unknown
    end
  end

  def parse(_), do: :unknown
end
