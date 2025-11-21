defmodule Tinkex.HTTPClient do
  @moduledoc """
  Behaviour for HTTP client implementations.

  This indirection lets tests or host applications swap out the HTTP layer when
  needed. The default implementation is `Tinkex.API`.
  """

  alias Tinkex.Error

  @callback post(path :: String.t(), body :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, Error.t()}

  @callback get(path :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, Error.t()}

  @callback delete(path :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, Error.t()}
end
