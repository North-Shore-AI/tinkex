defmodule Tinkex.API.Futures do
  @moduledoc """
  Future/promise retrieval endpoints.

  Uses :futures pool (concurrent polling).
  Pool size: 50 connections.
  """

  @doc """
  Retrieve future result by request_id.

  ## Examples

      Tinkex.API.Futures.retrieve(
        %{request_id: "abc-123"},
        config: config
      )
  """
  @spec retrieve(map(), keyword()) ::
          {:ok, map()} | {:error, Tinkex.Error.t()}
  def retrieve(request, opts) do
    Tinkex.API.post(
      "/api/v1/future/retrieve",
      request,
      Keyword.put(opts, :pool_type, :futures)
    )
  end
end
