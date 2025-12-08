defmodule Tinkex.TrainingClient.Operations do
  @moduledoc """
  Request building and sending operations for TrainingClient.

  This module handles:
  - Building and sending forward/backward requests
  - Building and sending optimizer step requests
  - Building and sending save/load weights requests
  - Creating sampling clients from saved weights
  - Handling response parsing and future extraction
  """

  require Logger

  alias Tinkex.Error
  alias Tinkex.Training.CustomLoss

  alias Tinkex.Types.{
    CreateModelRequest,
    CreateModelResponse,
    ForwardBackwardInput,
    ForwardBackwardOutput,
    ForwardBackwardRequest,
    ForwardRequest,
    LoadWeightsRequest,
    LoadWeightsResponse,
    LoraConfig,
    OptimStepRequest,
    SaveWeightsForSamplerRequest,
    SaveWeightsForSamplerResponse,
    SaveWeightsRequest,
    SaveWeightsResponse
  }

  @doc """
  Ensure a model exists, creating one if necessary.

  Returns `{:ok, model_id}` on success.
  """
  @spec ensure_model(keyword(), String.t(), integer(), map(), module(), map()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def ensure_model(opts, session_id, model_seq_id, config, service_api, telemetry_metadata) do
    case opts[:model_id] do
      model_id when is_binary(model_id) ->
        {:ok, model_id}

      _ ->
        with {:ok, base_model} <- fetch_base_model(opts),
             {:ok, response} <-
               service_api.create_model(
                 %CreateModelRequest{
                   session_id: session_id,
                   model_seq_id: model_seq_id,
                   base_model: base_model,
                   user_metadata: Keyword.get(opts, :user_metadata, config.user_metadata),
                   lora_config: Keyword.get(opts, :lora_config, %LoraConfig{})
                 },
                 config: config,
                 telemetry_metadata: Map.merge(telemetry_metadata, %{model_seq_id: model_seq_id})
               ) do
          {:ok, parse_model_id(response)}
        end
    end
  end

  @doc """
  Send a forward-backward request and return a future.
  """
  @spec send_forward_backward_request(list(), atom() | String.t(), integer(), keyword(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def send_forward_backward_request(chunk, loss_fn, seq_id, opts, state) do
    request = %ForwardBackwardRequest{
      forward_backward_input: %ForwardBackwardInput{
        data: chunk,
        loss_fn: loss_fn,
        loss_fn_config: Keyword.get(opts, :loss_fn_config)
      },
      model_id: state.model_id,
      seq_id: seq_id
    }

    case state.training_api.forward_backward_future(request,
           config: state.config,
           telemetry_metadata:
             base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
         ) do
      {:ok, %{"request_id" => request_id}} ->
        {:ok, %{request_id: request_id}}

      {:ok, %{request_id: _} = future} ->
        {:ok, future}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, Error.new(:validation, "Invalid forward_backward response: #{inspect(other)}")}
    end
  end

  @doc """
  Send a forward-only request and return a future.
  """
  @spec send_forward_request(list(), atom() | String.t(), integer(), keyword(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def send_forward_request(chunk, loss_fn, seq_id, opts, state) do
    request = %ForwardRequest{
      forward_input: %ForwardBackwardInput{
        data: chunk,
        loss_fn: loss_fn,
        loss_fn_config: Keyword.get(opts, :loss_fn_config)
      },
      model_id: state.model_id,
      seq_id: seq_id
    }

    case state.training_api.forward_future(request,
           config: state.config,
           telemetry_metadata:
             base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
         ) do
      {:ok, %{"request_id" => request_id}} ->
        {:ok, %{request_id: request_id}}

      {:ok, %{request_id: _} = future} ->
        {:ok, future}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, Error.new(:validation, "Invalid forward response: #{inspect(other)}")}
    end
  end

  @doc """
  Send an optimizer step request and return a future.
  """
  @spec send_optim_step_request(map(), integer(), keyword(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def send_optim_step_request(adam_params, seq_id, _opts, state) do
    request = %OptimStepRequest{
      adam_params: adam_params,
      model_id: state.model_id,
      seq_id: seq_id
    }

    case state.training_api.optim_step_future(request,
           config: state.config,
           telemetry_metadata:
             base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
         ) do
      {:ok, %{"request_id" => request_id}} -> {:ok, %{request_id: request_id}}
      {:ok, %{request_id: _} = future} -> {:ok, future}
      {:error, %Error{} = error} -> {:error, error}
      other -> {:error, Error.new(:validation, "Invalid optim_step response: #{inspect(other)}")}
    end
  end

  @doc """
  Send a save state (weights) request.
  """
  @spec send_save_state_request(String.t(), integer(), keyword(), map()) ::
          {:ok, map() | SaveWeightsResponse.t()} | {:error, Error.t()}
  def send_save_state_request(name, seq_id, _opts, state) do
    request = %SaveWeightsRequest{
      model_id: state.model_id,
      path: name,
      seq_id: seq_id
    }

    case state.weights_api.save_weights(
           request,
           config: state.config,
           telemetry_metadata:
             base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
         ) do
      {:ok, %{"request_id" => _} = future} ->
        {:ok, future}

      {:ok, %{request_id: _} = future} ->
        {:ok, future}

      {:ok, result} ->
        {:ok, result}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, Error.new(:validation, "Invalid save_weights response: #{inspect(other)}")}
    end
  end

  @doc """
  Send a load state (weights) request.
  """
  @spec send_load_state_request(String.t(), boolean(), integer(), keyword(), map()) ::
          {:ok, map() | LoadWeightsResponse.t()} | {:error, Error.t()}
  def send_load_state_request(path, optimizer, seq_id, _opts, state) do
    request = %LoadWeightsRequest{
      model_id: state.model_id,
      path: path,
      seq_id: seq_id,
      optimizer: optimizer
    }

    case state.weights_api.load_weights(
           request,
           config: state.config,
           telemetry_metadata:
             base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
         ) do
      {:ok, %{"request_id" => _} = future} ->
        {:ok, future}

      {:ok, %{request_id: _} = future} ->
        {:ok, future}

      {:ok, result} ->
        {:ok, result}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, Error.new(:validation, "Invalid load_weights response: #{inspect(other)}")}
    end
  end

  @doc """
  Send a save weights for sampler request.
  """
  @spec send_save_weights_for_sampler_request(integer(), keyword(), map()) ::
          {:ok, map() | SaveWeightsForSamplerResponse.t()} | {:error, Error.t()}
  def send_save_weights_for_sampler_request(seq_id, opts, state) do
    request = %SaveWeightsForSamplerRequest{
      model_id: state.model_id,
      path: Keyword.get(opts, :path),
      sampling_session_seq_id: Keyword.get(opts, :sampling_session_seq_id),
      seq_id: seq_id
    }

    case state.weights_api.save_weights_for_sampler(request,
           config: state.config,
           telemetry_metadata:
             base_telemetry_metadata(state, %{model_id: state.model_id, seq_id: seq_id})
         ) do
      {:ok, %{"request_id" => _} = future} ->
        {:ok, future}

      {:ok, %{request_id: _} = future} ->
        {:ok, future}

      {:ok, result} ->
        {:ok, result}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error,
         Error.new(:validation, "Invalid save_weights_for_sampler response: #{inspect(other)}")}
    end
  end

  @doc """
  Handle save state response, polling if necessary.
  """
  @spec handle_save_state_response(map() | SaveWeightsResponse.t(), map(), keyword()) ::
          {:ok, SaveWeightsResponse.t() | map()} | {:error, Error.t()}
  def handle_save_state_response(%{"request_id" => _} = future, state, opts) do
    poll_save_state_future(future, state, opts)
  end

  def handle_save_state_response(%{request_id: _} = future, state, opts) do
    poll_save_state_future(future, state, opts)
  end

  def handle_save_state_response(%SaveWeightsResponse{} = resp, _state, _opts), do: {:ok, resp}

  def handle_save_state_response(%{"path" => _} = result, _state, _opts) do
    {:ok, SaveWeightsResponse.from_json(result)}
  end

  def handle_save_state_response(result, _state, _opts), do: {:ok, result}

  @doc """
  Handle load state response, polling if necessary.
  """
  @spec handle_load_state_response(map() | LoadWeightsResponse.t(), map(), keyword()) ::
          {:ok, LoadWeightsResponse.t() | map()} | {:error, Error.t()}
  def handle_load_state_response(%{"request_id" => _} = future, state, opts) do
    poll_load_state_future(future, state, opts)
  end

  def handle_load_state_response(%{request_id: _} = future, state, opts) do
    poll_load_state_future(future, state, opts)
  end

  def handle_load_state_response(%LoadWeightsResponse{} = resp, _state, _opts), do: {:ok, resp}

  def handle_load_state_response(%{"path" => _} = result, _state, _opts) do
    {:ok, LoadWeightsResponse.from_json(result)}
  end

  def handle_load_state_response(result, _state, _opts), do: {:ok, result}

  @doc """
  Handle save weights for sampler response, polling if necessary.
  """
  @spec handle_save_weights_response(
          map() | SaveWeightsForSamplerResponse.t(),
          map(),
          keyword()
        ) ::
          {:ok, SaveWeightsForSamplerResponse.t() | map()} | {:error, Error.t()}
  def handle_save_weights_response(%{"request_id" => _} = future, state, opts) do
    poll_save_weights_future(future, state, opts)
  end

  def handle_save_weights_response(%{request_id: _} = future, state, opts) do
    poll_save_weights_future(future, state, opts)
  end

  def handle_save_weights_response(%SaveWeightsForSamplerResponse{} = resp, _state, _opts),
    do: {:ok, resp}

  def handle_save_weights_response(%{"path" => _} = result, _state, _opts),
    do: {:ok, SaveWeightsForSamplerResponse.from_json(result)}

  def handle_save_weights_response(%{"sampling_session_id" => _} = result, _state, _opts),
    do: {:ok, SaveWeightsForSamplerResponse.from_json(result)}

  def handle_save_weights_response(result, _state, _opts) when is_map(result),
    do: {:ok, SaveWeightsForSamplerResponse.from_json(result)}

  def handle_save_weights_response(result, _state, _opts), do: {:ok, result}

  @doc """
  Start a sampling client from save response data.

  Handles both path-based and sampling_session_id-based responses.
  """
  @spec start_sampling_client_from_save(
          SaveWeightsForSamplerResponse.t() | map(),
          integer(),
          keyword(),
          map()
        ) ::
          {:ok, pid()} | {:error, Error.t() | any()}
  def start_sampling_client_from_save(save_response, sampling_client_id, opts, state) do
    path = Map.get(save_response, :path) || Map.get(save_response, "path")

    sampling_session_id =
      Map.get(save_response, :sampling_session_id) ||
        Map.get(save_response, "sampling_session_id")

    if is_nil(path) and is_nil(sampling_session_id) do
      {:error,
       Error.new(:validation, "save_weights_for_sampler returned neither path nor session")}
    else
      child_opts =
        opts
        |> Keyword.put(:session_id, state.session_id)
        |> Keyword.put(:config, state.config)
        |> Keyword.put(:sampling_client_id, sampling_client_id)
        |> Keyword.put(:telemetry, state.telemetry)
        |> Keyword.put(:telemetry_metadata, state.telemetry_metadata)
        |> maybe_put(:model_path, path)
        |> maybe_put(:sampling_session_id, sampling_session_id)

      case DynamicSupervisor.start_child(
             state.client_supervisor,
             {state.sampling_client_module, child_opts}
           ) do
        {:ok, pid} -> {:ok, pid}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Normalize save weights options, generating sampling_session_seq_id if needed.

  Returns `{normalized_opts, new_counter}`.
  """
  @spec normalize_save_weights_opts(keyword(), map()) :: {keyword(), integer()}
  def normalize_save_weights_opts(opts, state) do
    cond do
      Keyword.get(opts, :path) ->
        {opts, state.sampling_session_counter}

      Keyword.has_key?(opts, :sampling_session_seq_id) ->
        {opts, state.sampling_session_counter}

      true ->
        counter = state.sampling_session_counter
        {Keyword.put(opts, :sampling_session_seq_id, counter), counter + 1}
    end
  end

  @doc """
  Poll forward futures for custom loss computation.
  """
  @spec poll_forward_custom_loss([map()], keyword(), map()) ::
          {:ok, [ForwardBackwardOutput.t()]} | {:error, Error.t()}
  def poll_forward_custom_loss(futures, opts, state) do
    polling_tasks =
      Enum.map(futures, fn future ->
        task =
          state.future_module.poll(
            future,
            Tinkex.TrainingClient.Polling.poll_opts_with_type(state, opts, "ForwardCustomLoss")
          )

        Tinkex.TrainingClient.Polling.unlink_task(task)
        task
      end)

    Tinkex.TrainingClient.Polling.await_forward_results_for_custom_loss(
      polling_tasks,
      state.future_module
    )
  end

  @doc """
  Build linear loss data safely with validation.
  """
  @spec build_linear_loss_data_safe(list(), [Nx.Tensor.t()]) ::
          {:ok, list()} | {:error, Error.t()}
  def build_linear_loss_data_safe(data, gradients) do
    if length(data) != length(gradients) do
      {:error, Error.new(:validation, "Gradient count does not match data count")}
    else
      {:ok, CustomLoss.build_linear_loss_data(data, gradients)}
    end
  rescue
    e ->
      {:error,
       Error.new(:request_failed, "Failed to build linear loss data: #{Exception.message(e)}",
         data: %{exception: e, stacktrace: __STACKTRACE__}
       )}
  end

  @doc """
  Send backward pass for custom loss computation.
  """
  @spec send_backward_for_custom_loss(list(), [integer()], keyword(), map()) ::
          {:ok, [ForwardBackwardOutput.t()]} | {:error, Error.t()}
  def send_backward_for_custom_loss(linear_data, seq_ids, opts, state) do
    chunks = Tinkex.TrainingClient.DataProcessor.chunk_data(linear_data)

    if length(chunks) != length(seq_ids) do
      {:error,
       Error.new(
         :validation,
         "Chunk count mismatch for custom loss backward: expected #{length(seq_ids)}, got #{length(chunks)}"
       )}
    else
      send_result =
        Enum.reduce_while(Enum.zip(seq_ids, chunks), {:ok, []}, fn {seq_id, chunk}, {:ok, acc} ->
          case send_forward_backward_request(chunk, :cross_entropy, seq_id, opts, state) do
            {:ok, future} -> {:cont, {:ok, [future | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case send_result do
        {:error, _} = error ->
          error

        {:ok, futures_rev} ->
          futures = Enum.reverse(futures_rev)

          polling_tasks =
            Enum.map(futures, fn future ->
              task =
                state.future_module.poll(
                  future,
                  Tinkex.TrainingClient.Polling.poll_opts_with_type(
                    state,
                    opts,
                    "ForwardBackwardCustomLoss"
                  )
                )

              Tinkex.TrainingClient.Polling.unlink_task(task)
              task
            end)

          Tinkex.TrainingClient.Polling.await_forward_backward_results(
            polling_tasks,
            state.future_module
          )
      end
    end
  end

  @doc """
  Merge custom loss metrics into ForwardBackwardOutput.
  """
  @spec merge_custom_metrics(ForwardBackwardOutput.t(), map()) :: ForwardBackwardOutput.t()
  def merge_custom_metrics(%ForwardBackwardOutput{} = output, metrics) when is_map(metrics) do
    normalized =
      metrics
      |> Enum.map(fn {k, v} -> {to_string(k), normalize_metric_value(v)} end)
      |> Map.new()

    %ForwardBackwardOutput{output | metrics: Map.merge(output.metrics, normalized)}
  end

  # Private helpers

  defp fetch_base_model(opts) do
    case opts[:base_model] do
      nil -> {:error, Error.new(:validation, "base_model is required to create a model")}
      base when is_binary(base) -> {:ok, base}
      other -> {:error, Error.new(:validation, "invalid base_model: #{inspect(other)}")}
    end
  end

  defp parse_model_id(%CreateModelResponse{model_id: model_id}), do: model_id
  defp parse_model_id(%{"model_id" => model_id}), do: model_id
  defp parse_model_id(%{model_id: model_id}), do: model_id

  defp parse_model_id(other),
    do: raise(ArgumentError, "Invalid create_model response: #{inspect(other)}")

  defp poll_save_state_future(future, state, opts) do
    task =
      state.future_module.poll(
        future,
        Tinkex.TrainingClient.Polling.poll_opts_with_type(state, opts, "SaveWeights")
      )

    Tinkex.TrainingClient.Polling.unlink_task(task)

    case Tinkex.TrainingClient.Polling.safe_await(
           state.future_module,
           task,
           await_timeout(opts)
         ) do
      {:ok, result} -> {:ok, SaveWeightsResponse.from_json(result)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp poll_load_state_future(future, state, opts) do
    task =
      state.future_module.poll(
        future,
        Tinkex.TrainingClient.Polling.poll_opts_with_type(state, opts, "LoadWeights")
      )

    Tinkex.TrainingClient.Polling.unlink_task(task)

    case Tinkex.TrainingClient.Polling.safe_await(
           state.future_module,
           task,
           await_timeout(opts)
         ) do
      {:ok, result} -> {:ok, LoadWeightsResponse.from_json(result)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp poll_save_weights_future(future, state, opts) do
    task =
      state.future_module.poll(
        future,
        Tinkex.TrainingClient.Polling.poll_opts_with_type(state, opts, "SaveWeightsForSampler")
      )

    Tinkex.TrainingClient.Polling.unlink_task(task)
    Tinkex.TrainingClient.Polling.safe_await(state.future_module, task, await_timeout(opts))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp base_telemetry_metadata(state, extra) when is_map(extra) do
    Map.merge(state.telemetry_metadata, extra)
  end

  defp normalize_metric_value(%Nx.Tensor{} = tensor), do: Nx.to_number(tensor)
  defp normalize_metric_value(other), do: other

  defp await_timeout(opts), do: Keyword.get(opts, :await_timeout, :infinity)
end
