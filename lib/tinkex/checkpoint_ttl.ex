defmodule Tinkex.CheckpointTTL do
  @moduledoc false

  alias Tinkex.Error

  @spec validate(term()) :: {:ok, pos_integer() | nil} | {:error, Error.t()}
  def validate(nil), do: {:ok, nil}

  def validate(ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0 do
    {:ok, ttl_seconds}
  end

  def validate(ttl_seconds) do
    {:error,
     Error.new(:validation, "ttl_seconds must be a positive integer",
       category: :user,
       data: %{ttl_seconds: ttl_seconds}
     )}
  end
end
