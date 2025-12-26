defmodule Tinkex.API.Response do
  @moduledoc """
  Wrapper around HTTP responses with metadata and parsing helpers.
  """

  @enforce_keys [:status, :headers, :method, :url, :body, :elapsed_ms, :retries]
  defstruct [:status, :headers, :method, :url, :body, :data, :elapsed_ms, :retries]

  @type t :: %__MODULE__{
          status: integer(),
          headers: map(),
          method: atom(),
          url: String.t(),
          body: binary(),
          data: term() | nil,
          elapsed_ms: non_neg_integer(),
          retries: non_neg_integer()
        }

  @doc """
  Build a response wrapper from a Finch response.
  """
  @spec new(Finch.Response.t(), keyword()) :: t()
  def new(%Finch.Response{status: status, headers: headers, body: body}, opts) do
    method = Keyword.fetch!(opts, :method)
    url = Keyword.fetch!(opts, :url)
    elapsed_ms = Keyword.get(opts, :elapsed_ms, 0)
    retries = Keyword.get(opts, :retries, 0)
    data = Keyword.get_lazy(opts, :data, fn -> decode_json(body) end)

    %__MODULE__{
      status: status,
      headers: normalize_headers(headers),
      method: method,
      url: url,
      body: body,
      data: data,
      elapsed_ms: elapsed_ms,
      retries: retries
    }
  end

  @doc """
  Retrieve a header value (case-insensitive).
  """
  @spec header(t(), String.t()) :: String.t() | nil
  def header(%__MODULE__{headers: headers}, name) do
    Map.get(headers, String.downcase(name))
  end

  @doc """
  Parse the response body using a module or function.

  - Module parser: must export `from_json/1`
  - Function parser: unary function that accepts the decoded JSON
  - nil parser: returns the decoded JSON map
  """
  @spec parse(t(), module() | (term() -> term()) | nil) :: {:ok, term()} | {:error, term()}
  def parse(resp, parser \\ nil)

  def parse(%__MODULE__{} = resp, nil) do
    ensure_data(resp)
  end

  def parse(%__MODULE__{} = resp, parser) when is_function(parser, 1) do
    with {:ok, data} <- ensure_data(resp) do
      try do
        {:ok, parser.(data)}
      rescue
        error -> {:error, error}
      end
    end
  end

  def parse(%__MODULE__{} = resp, module) when is_atom(module) do
    if function_exported?(module, :from_json, 1) do
      parse(resp, &module.from_json/1)
    else
      {:error, {:invalid_parser, module}}
    end
  end

  defp ensure_data(%__MODULE__{data: data, body: body}) do
    if data do
      {:ok, data}
    else
      case Jason.decode(body) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp normalize_headers(headers) do
    Enum.reduce(headers, %{}, fn
      {name, value}, acc -> Map.put(acc, String.downcase(name), value)
      _, acc -> acc
    end)
  end

  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  end
end
