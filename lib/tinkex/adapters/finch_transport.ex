defmodule Tinkex.Adapters.FinchTransport do
  @moduledoc """
  Finch-based HTTP transport adapter.
  """

  @behaviour Tinkex.Ports.HTTPTransport

  @impl true
  def request(method, url, headers, body, opts) do
    finch = Keyword.get(opts, :finch, Finch)
    pool = Keyword.get(opts, :pool_name, finch)
    request = Finch.build(method, url, headers, body)
    finch_opts = finch_opts(opts)

    case Finch.request(request, pool, finch_opts) do
      {:ok, %Finch.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status: status, headers: resp_headers, body: resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream(method, url, headers, body, opts) do
    with {:ok, %{body: resp_body}} <- request(method, url, headers, body, opts) do
      {:ok, Stream.concat([[resp_body]])}
    end
  end

  defp finch_opts(opts) do
    timeout = Keyword.get(opts, :timeout)
    receive_timeout = Keyword.get(opts, :receive_timeout, timeout)

    opts
    |> Keyword.drop([:timeout, :receive_timeout, :pool_name, :finch])
    |> maybe_put_receive_timeout(receive_timeout)
  end

  defp maybe_put_receive_timeout(opts, nil), do: opts
  defp maybe_put_receive_timeout(opts, timeout), do: Keyword.put(opts, :receive_timeout, timeout)
end
