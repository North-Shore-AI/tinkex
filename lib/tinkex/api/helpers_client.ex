defmodule Tinkex.API.Helpers do
  @moduledoc """
  Request helpers for raw and streaming response access.

  Provides Python SDK parity for `with_raw_response` and `with_streaming_response`
  patterns.
  """

  @doc """
  Modify options to request a wrapped raw response.

  Returns options with `response: :wrapped` set, causing API calls
  to return a `Tinkex.API.Response` struct instead of just the parsed data.

  Accepts either a keyword list of options or a `Tinkex.Config`/`Pristine.Core.Context`.
  """
  @spec with_raw_response(keyword() | Tinkex.Config.t() | Pristine.Core.Context.t()) :: keyword()
  def with_raw_response(opts) when is_list(opts) do
    Keyword.put(opts, :response, :wrapped)
  end

  def with_raw_response(%Tinkex.Config{} = config) do
    [config: config, response: :wrapped]
  end

  def with_raw_response(%Pristine.Core.Context{} = context) do
    [context: context, response: :wrapped]
  end

  @doc """
  Modify options to request a streaming response.

  Returns options with `response: :stream` set, causing streaming API calls
  to return a `Tinkex.API.StreamResponse` struct with a lazy enumerable.

  Accepts either a keyword list of options or a `Tinkex.Config`/`Pristine.Core.Context`.
  """
  @spec with_streaming_response(keyword() | Tinkex.Config.t() | Pristine.Core.Context.t()) ::
          keyword()
  def with_streaming_response(opts) when is_list(opts) do
    Keyword.put(opts, :response, :stream)
  end

  def with_streaming_response(%Tinkex.Config{} = config) do
    [config: config, response: :stream]
  end

  def with_streaming_response(%Pristine.Core.Context{} = context) do
    [context: context, response: :stream]
  end
end
