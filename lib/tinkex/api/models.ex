defmodule Tinkex.API.Models do
  @moduledoc """
  Model metadata and lifecycle endpoints.
  """

  alias Tinkex.Types.{GetInfoResponse, UnloadModelResponse}

  @doc """
  Retrieve metadata for a model.
  """
  @spec get_info(map(), keyword()) ::
          {:ok, GetInfoResponse.t()} | {:error, Tinkex.Error.t()}
  def get_info(request, opts) do
    client = Tinkex.API.client_module(opts)

    case client.post(
           "/api/v1/get_info",
           request,
           opts
           |> Keyword.put(:pool_type, :training)
           |> Keyword.put(:endpoint_id, :get_info)
         ) do
      {:ok, json} -> {:ok, GetInfoResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Unload model weights and end the session. May return a future or a direct payload.
  """
  @spec unload_model(map(), keyword()) ::
          {:ok, UnloadModelResponse.t() | map()} | {:error, Tinkex.Error.t()}
  def unload_model(request, opts) do
    client = Tinkex.API.client_module(opts)

    case client.post(
           "/api/v1/unload_model",
           request,
           opts
           |> Keyword.put(:pool_type, :training)
           |> Keyword.put(:endpoint_id, :unload_model)
         ) do
      {:ok, %{"request_id" => _} = future} -> {:ok, future}
      {:ok, %{request_id: _} = future} -> {:ok, future}
      {:ok, json} -> {:ok, UnloadModelResponse.from_json(json)}
      {:error, _} = error -> error
    end
  end
end
