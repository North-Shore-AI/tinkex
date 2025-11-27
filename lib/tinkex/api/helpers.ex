defmodule Tinkex.API.Helpers do
  @moduledoc """
  Request helpers for raw and streaming response access.

  Provides Python SDK parity for `with_raw_response` and `with_streaming_response`
  patterns.

  ## Python SDK Reference

  Python SDK exposes these methods on resources:

      # Raw response access
      response = client.sampling.with_raw_response.sample(...)
      response.status_code  # HTTP status
      response.headers      # HTTP headers
      response.text()       # Raw body

      # Streaming response access
      with client.streaming.with_streaming_response.stream(...) as response:
          for chunk in response.iter_lines():
              ...

  ## Elixir Usage

      # Raw response - returns Tinkex.API.Response struct
      opts = Tinkex.API.Helpers.with_raw_response([config: config])
      {:ok, %Response{} = response} = Tinkex.API.Sampling.sample(params, opts)
      response.status   # HTTP status
      response.headers  # HTTP headers map
      response.body     # Raw body
      response.data     # Parsed JSON data

      # Using pipe-style
      config
      |> Tinkex.API.Helpers.with_raw_response()
      |> then(&Tinkex.API.Sampling.sample(params, &1))

      # Streaming response - returns Tinkex.API.StreamResponse struct
      opts = Tinkex.API.Helpers.with_streaming_response([config: config])
      {:ok, %StreamResponse{} = response} = Tinkex.API.stream_get("/events", opts)
      for event <- response.stream do
        IO.inspect(event)
      end
  """

  @doc """
  Modify options to request a wrapped raw response.

  Returns options with `response: :wrapped` set, causing API calls
  to return a `Tinkex.API.Response` struct instead of just the parsed data.

  Accepts either a keyword list of options or a `Tinkex.Config` struct directly.

  ## Examples

      iex> opts = Tinkex.API.Helpers.with_raw_response(config: my_config)
      iex> opts[:response]
      :wrapped

      # With existing opts
      iex> opts = [config: my_config, timeout: 5000]
      iex> new_opts = Tinkex.API.Helpers.with_raw_response(opts)
      iex> new_opts[:response]
      :wrapped
      iex> new_opts[:timeout]
      5000

      # With Config struct directly
      iex> opts = Tinkex.API.Helpers.with_raw_response(my_config)
      iex> opts[:config] == my_config
      true
      iex> opts[:response]
      :wrapped
  """
  @spec with_raw_response(keyword() | Tinkex.Config.t()) :: keyword()
  def with_raw_response(opts) when is_list(opts) do
    Keyword.put(opts, :response, :wrapped)
  end

  def with_raw_response(%Tinkex.Config{} = config) do
    [config: config, response: :wrapped]
  end

  @doc """
  Modify options to request a streaming response.

  Returns options with `response: :stream` set, causing streaming API calls
  to return a `Tinkex.API.StreamResponse` struct with a lazy enumerable.

  Accepts either a keyword list of options or a `Tinkex.Config` struct directly.

  ## Examples

      iex> opts = Tinkex.API.Helpers.with_streaming_response(config: my_config)
      iex> opts[:response]
      :stream

      # With existing opts
      iex> opts = [config: my_config, timeout: 30_000]
      iex> new_opts = Tinkex.API.Helpers.with_streaming_response(opts)
      iex> new_opts[:response]
      :stream

      # With Config struct directly
      iex> opts = Tinkex.API.Helpers.with_streaming_response(my_config)
      iex> opts[:config] == my_config
      true
      iex> opts[:response]
      :stream
  """
  @spec with_streaming_response(keyword() | Tinkex.Config.t()) :: keyword()
  def with_streaming_response(opts) when is_list(opts) do
    Keyword.put(opts, :response, :stream)
  end

  def with_streaming_response(%Tinkex.Config{} = config) do
    [config: config, response: :stream]
  end
end
