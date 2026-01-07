defmodule Tinkex.API do
  @moduledoc """
  High-level HTTP API client for Tinkex.

  Delegates request execution to Pristine's runtime pipeline using the
  Tinkex manifest and context configuration.
  """

  @behaviour Tinkex.HTTPClient
  require Logger

  alias Pristine.Core.StreamResponse, as: PristineStreamResponse
  alias Pristine.Manifest, as: PristineManifest
  alias Pristine.Runtime
  alias Pristine.Streaming.Event

  alias Tinkex.API.StreamResponse
  alias Tinkex.{Config, Context, Error, Manifest}
  alias Tinkex.Files.Transform, as: FileTransform

  @manifest Manifest.load!()

  @impl true
  @spec post(String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(path, body, opts) do
    request(:post, path, body, opts)
  end

  @impl true
  @spec get(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(path, opts) do
    request(:get, path, nil, opts)
  end

  @impl true
  @spec delete(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(path, opts) do
    request(:delete, path, nil, opts)
  end

  @spec execute(atom() | String.t(), map() | nil, keyword()) :: {:ok, map()} | {:error, Error.t()}
  def execute(endpoint_id, payload, opts) do
    context = context_from_opts(opts)
    payload = payload || %{}

    Runtime.execute(@manifest, endpoint_id, payload, context, opts)
  end

  @spec execute_stream(atom() | String.t(), map() | nil, keyword()) ::
          {:ok, PristineStreamResponse.t()} | {:error, Error.t()}
  def execute_stream(endpoint_id, payload, opts) do
    context = context_from_opts(opts)
    payload = payload || %{}

    Runtime.execute_stream(@manifest, endpoint_id, payload, context, opts)
  end

  @spec stream_get(String.t(), keyword()) :: {:ok, StreamResponse.t()} | {:error, Error.t()}
  def stream_get(path, opts) do
    parser = Keyword.get(opts, :event_parser, :json)

    with {:ok, response, events} <- stream_request(:get, path, nil, opts) do
      parsed_events =
        events
        |> Stream.map(&decode_event(&1, parser))
        |> Stream.reject(&(&1 in [nil, ""]))

      {:ok,
       %StreamResponse{
         stream: parsed_events,
         status: response.status,
         headers: headers_to_map(response.headers),
         method: :get,
         url: response.url
       }}
    end
  end

  @spec stream_request(atom(), String.t(), term() | nil, keyword()) ::
          {:ok, map(), Enumerable.t()} | {:error, Error.t()}
  def stream_request(method, path, body, opts) do
    context = context_from_opts(opts)

    with {:ok, payload, runtime_opts} <- prepare_payload(body, opts),
         {payload, runtime_opts} <- normalize_payload(method, payload, runtime_opts),
         {:ok, %PristineStreamResponse{} = response} <-
           Runtime.execute_stream(
             @manifest,
             Keyword.get(runtime_opts, :endpoint_id, raw_stream_endpoint_id(method)),
             payload,
             context,
             runtime_opts
             |> Keyword.put(:path, path)
             |> put_stream_accept_header()
           ) do
      if response.status in 200..299 do
        response_map = %{
          status: response.status,
          headers: response.headers,
          url: response.metadata[:url]
        }

        {:ok, response_map, response.stream}
      else
        {:error,
         Error.from_response(
           response.status,
           %{"message" => "HTTP #{response.status}"},
           nil,
           []
         )}
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, validation_error(reason)}
    end
  end

  @doc """
  Resolve the HTTP client module for a request based on options/config.
  """
  @spec client_module(keyword()) :: module()
  def client_module(opts) do
    cond do
      is_atom(opts[:http_client]) and not is_nil(opts[:http_client]) ->
        opts[:http_client]

      match?(
        %Pristine.Core.Context{config: %Config{http_client: client}} when is_atom(client),
        opts[:context]
      ) ->
        opts[:context].config.http_client

      match?(%Config{http_client: client} when is_atom(client), Keyword.get(opts, :config)) ->
        Keyword.fetch!(opts, :config).http_client

      true ->
        __MODULE__
    end
  end

  defp request(method, path, body, opts) do
    context = context_from_opts(opts)

    case prepare_payload(body, opts) do
      {:ok, payload, runtime_opts} ->
        {payload, runtime_opts} = normalize_payload(method, payload, runtime_opts)
        endpoint_id = Keyword.get(runtime_opts, :endpoint_id, raw_endpoint_id(method))
        endpoint = PristineManifest.fetch_endpoint!(@manifest, endpoint_id)

        maybe_log_dump_headers(context, endpoint, method, path, runtime_opts)

        Runtime.execute(
          @manifest,
          endpoint_id,
          payload,
          context,
          runtime_opts
          |> Keyword.put(:path, path)
        )

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, validation_error(reason)}
    end
  end

  defp prepare_payload(body, opts) do
    case Keyword.get(opts, :files) do
      nil ->
        {:ok, body, opts}

      files ->
        with {:ok, normalized_files} <- FileTransform.transform_files(files),
             {:ok, fields} <- normalize_form_payload(body) do
          payload =
            fields
            |> Map.merge(files_to_map(normalized_files))

          {:ok, payload,
           opts
           |> Keyword.delete(:files)
           |> Keyword.put(:body_type, "multipart")}
        end
    end
  end

  defp normalize_form_payload(nil), do: {:ok, %{}}
  defp normalize_form_payload(body) when is_map(body), do: {:ok, body}

  defp normalize_form_payload(body) when is_list(body) do
    if Enum.all?(body, &match?({_, _}, &1)) do
      {:ok, Map.new(body)}
    else
      {:error, {:invalid_multipart_body, body}}
    end
  end

  defp normalize_form_payload(body) when is_binary(body),
    do: {:error, {:invalid_multipart_body, :binary}}

  defp normalize_form_payload(body), do: {:error, {:invalid_multipart_body, body}}

  defp files_to_map(files) when is_map(files), do: files
  defp files_to_map(files) when is_list(files), do: Map.new(files)
  defp files_to_map(_), do: %{}

  defp put_stream_accept_header(opts) do
    headers = Keyword.get(opts, :headers, %{})

    headers =
      case headers do
        list when is_list(list) -> Map.new(list)
        map when is_map(map) -> map
        _ -> %{}
      end

    if Map.has_key?(headers, "accept") or Map.has_key?(headers, "Accept") do
      opts
    else
      Keyword.put(opts, :headers, Map.put(headers, "accept", "text/event-stream"))
    end
  end

  defp raw_endpoint_id(:get), do: :raw_get
  defp raw_endpoint_id(:post), do: :raw_post
  defp raw_endpoint_id(:delete), do: :raw_delete

  defp raw_stream_endpoint_id(:get), do: :raw_stream_get
  defp raw_stream_endpoint_id(:post), do: :raw_stream_post
  defp raw_stream_endpoint_id(_), do: :raw_stream_get

  defp decode_event(%Event{} = event, :raw), do: event

  defp decode_event(%Event{} = event, parser) when is_function(parser, 1),
    do: parser.(event)

  defp decode_event(%Event{} = event, _parser) do
    case Event.json(event) do
      {:ok, decoded} -> decoded
      {:error, _} -> nil
    end
  end

  defp headers_to_map(headers) when is_map(headers), do: headers

  defp maybe_log_dump_headers(%Pristine.Core.Context{} = context, endpoint, method, path, opts) do
    if context.dump_headers? do
      headers =
        context.headers
        |> Map.merge(normalize_header_map(maybe_extra_headers(context, endpoint, opts)))
        |> Map.merge(normalize_header_map(Keyword.get(opts, :headers, %{})))

      redacted = redact_headers(headers, context)

      Logger.info("HTTP #{format_method(method)} #{path} headers=#{inspect(redacted)}")
    end
  end

  defp normalize_header_map(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_header_map(headers) when is_list(headers) do
    if Enum.all?(headers, &match?({_, _}, &1)) do
      Map.new(headers, fn {key, value} -> {to_string(key), value} end)
    else
      %{}
    end
  end

  defp normalize_header_map(_), do: %{}

  defp maybe_extra_headers(%Pristine.Core.Context{extra_headers: fun} = context, endpoint, opts)
       when is_function(fun, 3) do
    fun.(endpoint, context, opts)
  end

  defp maybe_extra_headers(%Pristine.Core.Context{extra_headers: fun}, endpoint, opts)
       when is_function(fun, 2) do
    fun.(endpoint, opts)
  end

  defp maybe_extra_headers(%Pristine.Core.Context{extra_headers: fun}, _endpoint, opts)
       when is_function(fun, 1) do
    fun.(opts)
  end

  defp maybe_extra_headers(_context, _endpoint, _opts), do: %{}

  defp redact_headers(headers, %Pristine.Core.Context{redact_headers: fun})
       when is_function(fun, 1) do
    fun.(headers)
  end

  defp redact_headers(headers, _context), do: headers

  defp format_method(method) when is_atom(method),
    do: method |> Atom.to_string() |> String.upcase()

  defp normalize_payload(method, payload, opts) do
    cond do
      is_nil(payload) and no_body_method?(method) ->
        {nil, Keyword.put_new(opts, :body_type, "raw")}

      is_nil(payload) ->
        {%{}, opts}

      true ->
        {payload, opts}
    end
  end

  defp no_body_method?(method) when is_atom(method),
    do: method in [:get, :delete, :head, :options]

  defp no_body_method?(method) when is_binary(method) do
    String.upcase(method) in ["GET", "DELETE", "HEAD", "OPTIONS"]
  end

  defp no_body_method?(_), do: false

  defp validation_error(reason) do
    Error.new(:validation, format_error(reason), category: :user, data: %{reason: reason})
  end

  defp format_error({:invalid_multipart_body, :binary}),
    do: "multipart body must be a map or keyword list"

  defp format_error({:invalid_multipart_body, value}),
    do: "multipart body must be a map, got: #{inspect(value)}"

  defp format_error({:invalid_request_files, value}),
    do: "invalid files option #{inspect(value)}"

  defp format_error({:invalid_file_type, value}),
    do: "invalid file input #{inspect(value)}"

  defp format_error(reason), do: inspect(reason)

  defp context_from_opts(opts) do
    case Keyword.get(opts, :context) do
      %Pristine.Core.Context{} = context -> context
      _ -> Context.new(Keyword.fetch!(opts, :config))
    end
  end
end
