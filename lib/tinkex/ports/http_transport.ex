defmodule Tinkex.Ports.HTTPTransport do
  @moduledoc """
  Port for HTTP transport operations.
  """

  @type method :: :get | :post | :put | :delete | :patch
  @type headers :: [{String.t(), String.t()}]
  @type response :: %{
          status: integer(),
          headers: headers(),
          body: term()
        }

  @callback request(method(), String.t(), headers(), term(), keyword()) ::
              {:ok, response()} | {:error, term()}

  @callback stream(method(), String.t(), headers(), term(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
end
