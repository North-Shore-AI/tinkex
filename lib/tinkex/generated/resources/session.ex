defmodule Tinkex.Generated.Session do
  @moduledoc """
  Session resource endpoints.

  This module provides functions for interacting with session resources.
  """

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc "Create a resource module instance with the given client."
  @spec with_client(Tinkex.Generated.Client.t()) :: t()
  def with_client(%{context: context}) do
    %__MODULE__{context: context}
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.heartbeat()
  """
  @spec heartbeat(t(), keyword()) :: {:ok, term()} | {:error, Pristine.Error.t()}
  def heartbeat(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "heartbeat",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `session_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:type` - Optional parameter.
      * `:timeout` - Request timeout in milliseconds.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.session_heartbeat(session_id, [])
  """
  @spec session_heartbeat(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.SessionHeartbeatResponse.t()}
          | {:error, Pristine.Error.t()}
  def session_heartbeat(%__MODULE__{context: context}, session_id, opts \\ []) do
    payload =
      %{
        "session_id" => session_id
      }
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "session_heartbeat",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_server_capabilities()
  """
  @spec get_server_capabilities(t(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GetServerCapabilitiesResponse.t()}
          | {:error, Pristine.Error.t()}
  def get_server_capabilities(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "get_server_capabilities",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `sampling_session_seq_id` - Required parameter.
    * `session_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:base_model` - Optional parameter.
      * `:model_path` - Optional parameter.
      * `:type` - Optional parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.create_sampling_session(sampling_session_seq_id, session_id, [])
  """
  @spec create_sampling_session(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.CreateSamplingSessionResponse.t()}
          | {:error, Pristine.Error.t()}
  def create_sampling_session(
        %__MODULE__{context: context},
        sampling_session_seq_id,
        session_id,
        opts \\ []
      ) do
    payload =
      %{
        "sampling_session_seq_id" => sampling_session_seq_id,
        "session_id" => session_id
      }
      |> maybe_put("base_model", Keyword.get(opts, :base_model))
      |> maybe_put("model_path", Keyword.get(opts, :model_path))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "create_sampling_session",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `base_model` - Required parameter.
    * `model_seq_id` - Required parameter.
    * `session_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:lora_config` - Optional parameter.
      * `:type` - Optional parameter.
      * `:user_metadata` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.create_model(base_model, model_seq_id, session_id, [])
  """
  @spec create_model(t(), term(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.CreateModelResponse.t()} | {:error, Pristine.Error.t()}
  def create_model(
        %__MODULE__{context: context},
        base_model,
        model_seq_id,
        session_id,
        opts \\ []
      ) do
    payload =
      %{
        "base_model" => base_model,
        "model_seq_id" => model_seq_id,
        "session_id" => session_id
      }
      |> maybe_put("lora_config", Keyword.get(opts, :lora_config))
      |> maybe_put("type", Keyword.get(opts, :type))
      |> maybe_put("user_metadata", Keyword.get(opts, :user_metadata))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "create_model",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.healthz()
  """
  @spec healthz(t(), keyword()) ::
          {:ok, Tinkex.Generated.Types.HealthResponse.t()} | {:error, Pristine.Error.t()}
  def healthz(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "healthz",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `sdk_version` - Required parameter.
    * `tags` - Required parameter.
    * `opts` - Optional parameters:
      * `:type` - Optional parameter.
      * `:user_metadata` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.create_session(sdk_version, tags, [])
  """
  @spec create_session(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.CreateSessionResponse.t()} | {:error, Pristine.Error.t()}
  def create_session(%__MODULE__{context: context}, sdk_version, tags, opts \\ []) do
    payload =
      %{
        "sdk_version" => sdk_version,
        "tags" => tags
      }
      |> maybe_put("type", Keyword.get(opts, :type))
      |> maybe_put("user_metadata", Keyword.get(opts, :user_metadata))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "create_session",
      payload,
      context,
      opts
    )
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, Sinter.NotGiven), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
