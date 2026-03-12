defmodule Tinkex.Generated.Futures do
  @moduledoc """
  Futures resource endpoints.

  This module provides functions for interacting with futures resources.
  """

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc "Create a resource module instance with the given client."
  @spec with_client(Tinkex.Generated.Client.t()) :: t()
  def with_client(%{context: context}) do
    %__MODULE__{context: context}
  end

  @doc """
  ## Parameters
    * `request_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.retrieve_future(request_id, [])
  """
  @spec retrieve_future(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.FutureRetrieveResponse.t()} | {:error, Pristine.Error.t()}
  def retrieve_future(%__MODULE__{context: context}, request_id, opts \\ []) do
    payload =
      %{
        "request_id" => request_id
      }

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "retrieve_future",
      payload,
      context,
      opts
    )
  end
end
