defmodule Tinkex.Tokenizer.HTTPClient do
  @moduledoc """
  HTTP client adapter for HuggingFace downloads used by `tokenizers`.

  The upstream `Tokenizers.HTTPClient` relies on `CAStore.file_path/0`, which
  points at a `priv/` file that is not available inside an escript archive.

  This adapter uses OTP-provided CA certs (`:public_key.cacerts_get/0`) so the
  `./tinkex` CLI can download tokenizers at runtime.
  """

  @default_base_url "https://huggingface.co"

  @spec request(keyword()) ::
          {:ok, %{status: pos_integer(), headers: [{String.t(), String.t()}], body: binary()}}
          | {:error, term()}
  def request(opts) when is_list(opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    path = Keyword.get(opts, :url, "")
    method = Keyword.get(opts, :method, :get)
    headers = Keyword.get(opts, :headers, [])
    timeout_ms = Keyword.get(opts, :timeout_ms, 120_000)

    url =
      [base_url, path]
      |> Path.join()
      |> String.to_charlist()

    headers = Enum.map(headers, &normalize_header/1)

    with :ok <- ensure_httpc_started() do
      http_options = [
        timeout: timeout_ms,
        connect_timeout: timeout_ms,
        ssl: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      ]

      options = [body_format: :binary, autoredirect: true]

      case :httpc.request(method, {url, headers}, http_options, options) do
        {:ok, {{_, status, _}, resp_headers, body}} ->
          {:ok, %{status: status, headers: normalize_headers(resp_headers), body: body}}

        {:ok, {status, body}} ->
          {:ok, %{status: status, body: body, headers: []}}

        {:error, reason} ->
          {:error, "could not make request #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp ensure_httpc_started do
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      :ok
    else
      {:error, reason} ->
        {:error, "could not start :httpc dependencies: #{inspect(reason)}"}
    end
  end

  defp normalize_header({key, value}) do
    {to_charlist_value(key), to_charlist_value(value)}
  end

  defp to_charlist_value(value) when is_binary(value), do: String.to_charlist(value)
  defp to_charlist_value(value) when is_list(value), do: value
  defp to_charlist_value(value) when is_atom(value), do: Atom.to_charlist(value)
  defp to_charlist_value(value), do: value |> to_string() |> String.to_charlist()

  defp normalize_headers(headers) do
    for {key, value} <- headers do
      {List.to_string(key), List.to_string(value)}
    end
  end
end
