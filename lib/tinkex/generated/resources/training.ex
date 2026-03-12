defmodule Tinkex.Generated.Training do
  @moduledoc """
  Training resource endpoints.

  This module provides functions for interacting with training resources.
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
    * `run_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.list_checkpoints(run_id, [])
  """
  @spec list_checkpoints(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.CheckpointsListResponse.t()} | {:error, Pristine.Error.t()}
  def list_checkpoints(%__MODULE__{context: context}, run_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "run_id" => run_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "list_checkpoints",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `run_id` - Required parameter.
    * `checkpoint_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.publish_checkpoint(run_id, checkpoint_id, [])
  """
  @spec publish_checkpoint(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def publish_checkpoint(%__MODULE__{context: context}, run_id, checkpoint_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "run_id" => run_id,
      "checkpoint_id" => checkpoint_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "publish_checkpoint",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.list_user_checkpoints()
  """
  @spec list_user_checkpoints(t(), keyword()) ::
          {:ok, Tinkex.Generated.Types.CheckpointsListResponse.t()} | {:error, Pristine.Error.t()}
  def list_user_checkpoints(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "list_user_checkpoints",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `path` - Required parameter.
    * `opts` - Optional parameters:
      * `:optimizer` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.load_weights(model_id, path, [])
  """
  @spec load_weights(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def load_weights(%__MODULE__{context: context}, model_id, path, opts \\ []) do
    payload =
      %{
        "model_id" => model_id,
        "path" => path
      }
      |> maybe_put("optimizer", Keyword.get(opts, :optimizer))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "load_weights",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `path` - Required parameter.
    * `opts` - Optional parameters:
      * `:optimizer` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, Task.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.load_weights_async(model_id, path, [])
  """
  @spec load_weights_async(t(), term(), term(), keyword()) ::
          {:ok, Task.t()} | {:error, Pristine.Error.t()}
  def load_weights_async(%__MODULE__{context: context}, model_id, path, opts \\ []) do
    payload =
      %{
        "model_id" => model_id,
        "path" => path
      }
      |> maybe_put("optimizer", Keyword.get(opts, :optimizer))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute_future(
      Tinkex.Generated.Client.manifest(),
      "load_weights",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:path` - Optional parameter.
      * `:sampling_session_seq_id` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.save_weights_for_sampler(model_id, [])
  """
  @spec save_weights_for_sampler(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def save_weights_for_sampler(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{
        "model_id" => model_id
      }
      |> maybe_put("path", Keyword.get(opts, :path))
      |> maybe_put("sampling_session_seq_id", Keyword.get(opts, :sampling_session_seq_id))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "save_weights_for_sampler",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:path` - Optional parameter.
      * `:sampling_session_seq_id` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, Task.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.save_weights_for_sampler_async(model_id, [])
  """
  @spec save_weights_for_sampler_async(t(), term(), keyword()) ::
          {:ok, Task.t()} | {:error, Pristine.Error.t()}
  def save_weights_for_sampler_async(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{
        "model_id" => model_id
      }
      |> maybe_put("path", Keyword.get(opts, :path))
      |> maybe_put("sampling_session_seq_id", Keyword.get(opts, :sampling_session_seq_id))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute_future(
      Tinkex.Generated.Client.manifest(),
      "save_weights_for_sampler",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `forward_backward_input` - Required parameter.
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:seq_id` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.forward_backward(forward_backward_input, model_id, [])
  """
  @spec forward_backward(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def forward_backward(
        %__MODULE__{context: context},
        forward_backward_input,
        model_id,
        opts \\ []
      ) do
    payload =
      %{
        "forward_backward_input" => forward_backward_input,
        "model_id" => model_id
      }
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "forward_backward",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `forward_backward_input` - Required parameter.
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:seq_id` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, Task.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.forward_backward_async(forward_backward_input, model_id, [])
  """
  @spec forward_backward_async(t(), term(), term(), keyword()) ::
          {:ok, Task.t()} | {:error, Pristine.Error.t()}
  def forward_backward_async(
        %__MODULE__{context: context},
        forward_backward_input,
        model_id,
        opts \\ []
      ) do
    payload =
      %{
        "forward_backward_input" => forward_backward_input,
        "model_id" => model_id
      }
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))

    Pristine.Runtime.execute_future(
      Tinkex.Generated.Client.manifest(),
      "forward_backward",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `tinker_path` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.weights_info(tinker_path, [])
  """
  @spec weights_info(t(), String.t(), keyword()) ::
          {:ok, Tinkex.Generated.Types.WeightsInfoResponse.t()} | {:error, Pristine.Error.t()}
  def weights_info(%__MODULE__{context: context}, tinker_path, opts \\ []) do
    payload =
      %{
        "tinker_path" => tinker_path
      }

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "weights_info",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `run_id` - Required parameter.
    * `checkpoint_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.unpublish_checkpoint(run_id, checkpoint_id, [])
  """
  @spec unpublish_checkpoint(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def unpublish_checkpoint(%__MODULE__{context: context}, run_id, checkpoint_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "run_id" => run_id,
      "checkpoint_id" => checkpoint_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "unpublish_checkpoint",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `training_run_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_training_run(training_run_id, [])
  """
  @spec get_training_run(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.TrainingRun.t()} | {:error, Pristine.Error.t()}
  def get_training_run(%__MODULE__{context: context}, training_run_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "training_run_id" => training_run_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "get_training_run",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.meta()
  """
  @spec meta(t(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def meta(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(Tinkex.Generated.Client.manifest(), "meta", payload, context, opts)
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.list_training_runs()
  """
  @spec list_training_runs(t(), keyword()) ::
          {:ok, Tinkex.Generated.Types.TrainingRunsResponse.t()} | {:error, Pristine.Error.t()}
  def list_training_runs(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "list_training_runs",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.list_sessions()
  """
  @spec list_sessions(t(), keyword()) ::
          {:ok, Tinkex.Generated.Types.ListSessionsResponse.t()} | {:error, Pristine.Error.t()}
  def list_sessions(%__MODULE__{context: context}, opts \\ []) do
    payload =
      %{}

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "list_sessions",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:path` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.save_weights(model_id, [])
  """
  @spec save_weights(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def save_weights(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{
        "model_id" => model_id
      }
      |> maybe_put("path", Keyword.get(opts, :path))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "save_weights",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:path` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, Task.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.save_weights_async(model_id, [])
  """
  @spec save_weights_async(t(), term(), keyword()) ::
          {:ok, Task.t()} | {:error, Pristine.Error.t()}
  def save_weights_async(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{
        "model_id" => model_id
      }
      |> maybe_put("path", Keyword.get(opts, :path))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute_future(
      Tinkex.Generated.Client.manifest(),
      "save_weights",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `adam_params` - Required parameter.
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:seq_id` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.optim_step(adam_params, model_id, [])
  """
  @spec optim_step(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def optim_step(%__MODULE__{context: context}, adam_params, model_id, opts \\ []) do
    payload =
      %{
        "adam_params" => adam_params,
        "model_id" => model_id
      }
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "optim_step",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `adam_params` - Required parameter.
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:seq_id` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, Task.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.optim_step_async(adam_params, model_id, [])
  """
  @spec optim_step_async(t(), term(), term(), keyword()) ::
          {:ok, Task.t()} | {:error, Pristine.Error.t()}
  def optim_step_async(%__MODULE__{context: context}, adam_params, model_id, opts \\ []) do
    payload =
      %{
        "adam_params" => adam_params,
        "model_id" => model_id
      }
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))

    Pristine.Runtime.execute_future(
      Tinkex.Generated.Client.manifest(),
      "optim_step",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_info(model_id, [])
  """
  @spec get_info(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GetInfoResponse.t()} | {:error, Pristine.Error.t()}
  def get_info(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{
        "model_id" => model_id
      }
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "get_info",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `forward_input` - Required parameter.
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:seq_id` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.forward(forward_input, model_id, [])
  """
  @spec forward(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def forward(%__MODULE__{context: context}, forward_input, model_id, opts \\ []) do
    payload =
      %{
        "forward_input" => forward_input,
        "model_id" => model_id
      }
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "forward",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `forward_input` - Required parameter.
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:seq_id` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, Task.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.forward_async(forward_input, model_id, [])
  """
  @spec forward_async(t(), term(), term(), keyword()) ::
          {:ok, Task.t()} | {:error, Pristine.Error.t()}
  def forward_async(%__MODULE__{context: context}, forward_input, model_id, opts \\ []) do
    payload =
      %{
        "forward_input" => forward_input,
        "model_id" => model_id
      }
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))

    Pristine.Runtime.execute_future(
      Tinkex.Generated.Client.manifest(),
      "forward",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `session_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_session(session_id, [])
  """
  @spec get_session(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GetSessionResponse.t()} | {:error, Pristine.Error.t()}
  def get_session(%__MODULE__{context: context}, session_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "session_id" => session_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "get_session",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `run_id` - Required parameter.
    * `checkpoint_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_checkpoint_archive_url(run_id, checkpoint_id, [])
  """
  @spec get_checkpoint_archive_url(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.CheckpointArchiveUrlResponse.t()}
          | {:error, Pristine.Error.t()}
  def get_checkpoint_archive_url(%__MODULE__{context: context}, run_id, checkpoint_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "run_id" => run_id,
      "checkpoint_id" => checkpoint_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "get_checkpoint_archive_url",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.unload_model(model_id, [])
  """
  @spec unload_model(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def unload_model(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{
        "model_id" => model_id
      }
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "unload_model",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `model_id` - Required parameter.
    * `opts` - Optional parameters:
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, Task.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.unload_model_async(model_id, [])
  """
  @spec unload_model_async(t(), term(), keyword()) ::
          {:ok, Task.t()} | {:error, Pristine.Error.t()}
  def unload_model_async(%__MODULE__{context: context}, model_id, opts \\ []) do
    payload =
      %{
        "model_id" => model_id
      }
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute_future(
      Tinkex.Generated.Client.manifest(),
      "unload_model",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `run_id` - Required parameter.
    * `checkpoint_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.delete_checkpoint(run_id, checkpoint_id, [])
  """
  @spec delete_checkpoint(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GenericMap.t()} | {:error, Pristine.Error.t()}
  def delete_checkpoint(%__MODULE__{context: context}, run_id, checkpoint_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "run_id" => run_id,
      "checkpoint_id" => checkpoint_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "delete_checkpoint",
      payload,
      context,
      opts
    )
  end

  defp merge_path_params(opts, path_params) do
    existing = Keyword.get(opts, :path_params, %{})
    Keyword.put(opts, :path_params, Map.merge(existing, path_params))
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, Sinter.NotGiven), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
