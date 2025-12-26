defmodule Tinkex.Types.SampleStreamChunk do
  @moduledoc """
  Represents a single chunk from a streaming sample response.

  Chunks are emitted incrementally during SSE-based streaming sampling,
  allowing real-time token-by-token processing of model output.
  """

  @derive Jason.Encoder
  defstruct [
    :token,
    :token_id,
    :index,
    :finish_reason,
    :total_tokens,
    :logprob,
    event_type: :token
  ]

  @type t :: %__MODULE__{
          token: String.t() | nil,
          token_id: integer() | nil,
          index: non_neg_integer() | nil,
          finish_reason: String.t() | nil,
          total_tokens: non_neg_integer() | nil,
          logprob: float() | nil,
          event_type: :token | :done | :error
        }

  @doc """
  Create a SampleStreamChunk from a parsed SSE event map.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      token: get_value(map, ["token"]),
      token_id: get_value(map, ["token_id"]),
      index: get_value(map, ["index"]),
      finish_reason: get_value(map, ["finish_reason"]),
      total_tokens: get_value(map, ["total_tokens"]),
      logprob: get_value(map, ["logprob"]),
      event_type: determine_event_type(map)
    }
  end

  @doc """
  Create a done chunk indicating stream completion.
  """
  @spec done(String.t() | nil, non_neg_integer() | nil) :: t()
  def done(finish_reason \\ nil, total_tokens \\ nil) do
    %__MODULE__{
      finish_reason: finish_reason,
      total_tokens: total_tokens,
      event_type: :done
    }
  end

  @doc """
  Create an error chunk.
  """
  @spec error(String.t()) :: t()
  def error(message) do
    %__MODULE__{
      token: message,
      event_type: :error
    }
  end

  @doc """
  Check if this is the final chunk in a stream.
  """
  @spec done?(t()) :: boolean()
  def done?(%__MODULE__{event_type: :done}), do: true
  def done?(%__MODULE__{finish_reason: reason}) when not is_nil(reason), do: true
  def done?(_), do: false

  # Private helpers

  defp get_value(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key) || Map.get(map, String.to_atom(key))
    end)
  end

  defp determine_event_type(map) do
    cond do
      get_value(map, ["finish_reason"]) != nil -> :done
      get_value(map, ["error"]) != nil -> :error
      true -> :token
    end
  end
end
