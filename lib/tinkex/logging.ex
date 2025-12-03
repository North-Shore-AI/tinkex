defmodule Tinkex.Logging do
  @moduledoc false

  require Logger

  @spec maybe_set_level(Logger.level() | nil) :: :ok
  def maybe_set_level(nil), do: :ok

  def maybe_set_level(level) when level in [:debug, :info, :warn, :error] do
    normalized = normalize_level(level)

    case Logger.level() do
      ^normalized -> :ok
      _ -> Logger.configure(level: normalized)
    end
  end

  defp normalize_level(:warn), do: :warning
  defp normalize_level(level), do: level
end
