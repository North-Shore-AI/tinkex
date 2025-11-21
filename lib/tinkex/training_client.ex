defmodule Tinkex.TrainingClient do
  @moduledoc """
  GenServer that coordinates training operations for a single model.

  Requests are **sent sequentially** within the GenServer while polling is
  performed concurrently in background tasks. This keeps request ordering
  deterministic at the cost of blocking the GenServer during the send phase.

  Use `Tinkex.Types.ModelInput.from_text/2` to turn raw strings into
  tokenized `ModelInput` structs before constructing training data. Chat
  templates are not applied automatically; provide fully formatted text.
  """

  use GenServer

  alias Tinkex.API.{Service, Training, Weights}
  alias Tinkex.Error
  alias Tinkex.Future.Combiner

  alias Tinkex.Types.{
    CreateModelRequest,
    CreateModelResponse,
    ForwardBackwardInput,
    ForwardBackwardOutput,
    ForwardBackwardRequest,
    LoraConfig,
    OptimStepRequest,
    OptimStepResponse,
    SaveWeightsForSamplerRequest
  }

  @max_chunk_len 128
  @max_chunk_number_count 500_000

  @type t :: pid()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Fetch model metadata for the training client.

  Used by tokenizer resolution to obtain `model_data.tokenizer_id`. Returns an
  error until the info endpoint is wired.
  """
  @spec get_info(t()) :: {:ok, map()} | {:error, Error.t()}
  def get_info(client) do
    GenServer.call(client, :get_info)
  end

  @doc """
  Run a forward-backward pass over the provided data.

  Returns a `Task.t()` that yields `{:ok, %ForwardBackwardOutput{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec forward_backward(t(), [map()], atom() | String.t(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def forward_backward(client, data, loss_fn, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:forward_backward, data, loss_fn, opts}, :infinity)
     end)}
  end

  @doc """
  Perform an optimizer step.

  Returns a `Task.t()` that yields `{:ok, %OptimStepResponse{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec optim_step(t(), map(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def optim_step(client, adam_params, opts \\ []) do
    {:ok,
     Task.async(fn -> GenServer.call(client, {:optim_step, adam_params, opts}, :infinity) end)}
  end

  @doc """
  Save weights for downstream sampling.

  Returns a `Task.t()` that yields `{:ok, map()}` or `{:error, %Tinkex.Error{}}`.
  """
  @spec save_weights_for_sampler(t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def save_weights_for_sampler(client, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:save_weights_for_sampler, opts}, :infinity)
     end)}
  end

  @doc """
  Create a sampling client from this training client asynchronously.

  Takes a model_path (checkpoint path) and returns a Task that resolves to a sampling client.

  ## Examples

      task = TrainingClient.create_sampling_client_async(training_pid, "tinker://run-1/weights/0001")
      {:ok, sampling_pid} = Task.await(task)
  """
  @spec create_sampling_client_async(t(), String.t(), keyword()) :: Task.t()
  def create_sampling_client_async(client, model_path, opts \\ []) do
    Task.async(fn ->
      GenServer.call(client, {:create_sampling_client, model_path, opts}, :infinity)
    end)
  end

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    session_id = Keyword.fetch!(opts, :session_id)
    model_seq_id = Keyword.fetch!(opts, :model_seq_id)
    service_api = Keyword.get(opts, :service_api, Service)
    training_api = Keyword.get(opts, :training_api, Training)
    weights_api = Keyword.get(opts, :weights_api, Weights)
    future_module = Keyword.get(opts, :future_module, Tinkex.Future)
    client_supervisor = Keyword.get(opts, :client_supervisor, Tinkex.ClientSupervisor)

    case ensure_model(opts, session_id, model_seq_id, config, service_api) do
      {:ok, model_id} ->
        state = %{
          model_id: model_id,
          session_id: session_id,
          model_seq_id: model_seq_id,
          config: config,
          http_pool: config.http_pool,
          request_id_counter: 0,
          training_api: training_api,
          weights_api: weights_api,
          future_module: future_module,
          client_supervisor: client_supervisor
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:forward_backward, data, loss_fn, opts}, from, state) do
    chunks = chunk_data(data)
    {seq_ids, new_counter} = allocate_request_ids(length(chunks), state.request_id_counter)

    send_result =
      Enum.reduce_while(Enum.zip(seq_ids, chunks), {:ok, []}, fn {seq_id, chunk}, {:ok, acc} ->
        case send_forward_backward_request(chunk, loss_fn, seq_id, opts, state) do
          {:ok, future} -> {:cont, {:ok, [future | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case send_result do
      {:error, reason} ->
        {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

      {:ok, futures_rev} ->
        futures = Enum.reverse(futures_rev)

        Task.start(fn ->
          reply =
            try do
              polling_tasks =
                Enum.map(futures, fn future ->
                  task =
                    state.future_module.poll(
                      future,
                      poll_opts_with_type(state, opts, "ForwardBackward")
                    )

                  unlink_task(task)
                  task
                end)

              case await_forward_backward_results(polling_tasks, state.future_module) do
                {:ok, outputs} ->
                  {:ok, Combiner.combine_forward_backward_results(outputs)}

                {:error, %Error{} = error} ->
                  {:error, error}
              end
            rescue
              e ->
                {:error,
                 %Error{
                   message: "Polling failed: #{Exception.message(e)}",
                   type: :request_failed,
                   data: %{exception: e, stacktrace: __STACKTRACE__}
                 }}
            end

          try do
            GenServer.reply(from, reply)
          rescue
            ArgumentError -> :ok
          end
        end)

        {:noreply, %{state | request_id_counter: new_counter}}
    end
  end

  @impl true
  def handle_call({:optim_step, adam_params, opts}, from, state) do
    seq_id = state.request_id_counter
    new_counter = seq_id + 1

    case send_optim_step_request(adam_params, seq_id, opts, state) do
      {:error, reason} ->
        {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

      {:ok, future} ->
        Task.start(fn ->
          reply =
            try do
              task =
                state.future_module.poll(
                  future,
                  poll_opts_with_type(state, opts, "OptimStep")
                )

              unlink_task(task)

              case safe_await(state.future_module, task, await_timeout(opts)) do
                {:ok, result} ->
                  {:ok, OptimStepResponse.from_json(result)}

                {:error, %Error{} = error} ->
                  {:error, error}
              end
            rescue
              e ->
                {:error,
                 %Error{
                   message: "Polling failed: #{Exception.message(e)}",
                   type: :request_failed,
                   data: %{exception: e, stacktrace: __STACKTRACE__}
                 }}
            end

          try do
            GenServer.reply(from, reply)
          rescue
            ArgumentError -> :ok
          end
        end)

        {:noreply, %{state | request_id_counter: new_counter}}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    {:reply, {:error, Error.new(:validation, "get_info not implemented")}, state}
  end

  @impl true
  def handle_call({:save_weights_for_sampler, opts}, from, state) do
    seq_id = state.request_id_counter
    new_counter = seq_id + 1

    case send_save_weights_for_sampler_request(seq_id, opts, state) do
      {:error, reason} ->
        {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

      {:ok, response} ->
        Task.start(fn ->
          reply =
            try do
              handle_save_weights_response(response, state, opts)
            rescue
              e ->
                {:error,
                 %Error{
                   message: "Save weights failed: #{Exception.message(e)}",
                   type: :request_failed,
                   data: %{exception: e, stacktrace: __STACKTRACE__}
                 }}
            end

          try do
            GenServer.reply(from, reply)
          rescue
            ArgumentError -> :ok
          end
        end)

        {:noreply, %{state | request_id_counter: new_counter}}
    end
  end

  @impl true
  def handle_call({:create_sampling_client, model_path, opts}, _from, state) do
    # Create a sampling client with the given model_path
    # Uses the training client's session_id and config
    child_opts =
      opts
      |> Keyword.put(:session_id, state.session_id)
      |> Keyword.put(:config, state.config)
      |> Keyword.put(:model_path, model_path)
      |> Keyword.put(:sampling_client_id, state.request_id_counter)

    case DynamicSupervisor.start_child(
           state.client_supervisor,
           {Tinkex.SamplingClient, child_opts}
         ) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, %{state | request_id_counter: state.request_id_counter + 1}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(_message, _from, state), do: {:reply, {:error, :unsupported}, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp ensure_model(opts, session_id, model_seq_id, config, service_api) do
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
                 config: config
               ) do
          {:ok, parse_model_id(response)}
        end
    end
  end

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

  defp send_forward_backward_request(chunk, loss_fn, seq_id, opts, state) do
    request = %ForwardBackwardRequest{
      forward_backward_input: %ForwardBackwardInput{
        data: chunk,
        loss_fn: loss_fn,
        loss_fn_config: Keyword.get(opts, :loss_fn_config)
      },
      model_id: state.model_id,
      seq_id: seq_id
    }

    case state.training_api.forward_backward_future(request, config: state.config) do
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

  defp send_optim_step_request(adam_params, seq_id, _opts, state) do
    request = %OptimStepRequest{
      adam_params: adam_params,
      model_id: state.model_id,
      seq_id: seq_id
    }

    case state.training_api.optim_step_future(request, config: state.config) do
      {:ok, %{"request_id" => request_id}} -> {:ok, %{request_id: request_id}}
      {:ok, %{request_id: _} = future} -> {:ok, future}
      {:error, %Error{} = error} -> {:error, error}
      other -> {:error, Error.new(:validation, "Invalid optim_step response: #{inspect(other)}")}
    end
  end

  defp send_save_weights_for_sampler_request(seq_id, opts, state) do
    request = %SaveWeightsForSamplerRequest{
      model_id: state.model_id,
      path: Keyword.get(opts, :path),
      sampling_session_seq_id: Keyword.get(opts, :sampling_session_seq_id),
      seq_id: seq_id
    }

    case state.weights_api.save_weights_for_sampler(request, config: state.config) do
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

  defp await_forward_backward_results([], _future_module), do: {:ok, []}

  defp await_forward_backward_results([task | rest], future_module) do
    case safe_await(future_module, task, :infinity) do
      {:ok, result} ->
        with {:ok, remaining} <- await_forward_backward_results(rest, future_module) do
          {:ok, [ForwardBackwardOutput.from_json(result) | remaining]}
        end

      {:error, %Error{} = error} ->
        Enum.each(rest, &Task.shutdown(&1, :brutal_kill))
        {:error, error}
    end
  end

  defp chunk_data(data) do
    data
    |> Enum.chunk_while(
      {[], 0},
      fn datum, {chunk, count} ->
        estimated = estimate_number_count(datum)

        cond do
          length(chunk) >= @max_chunk_len ->
            {:cont, chunk, {[datum], estimated}}

          count + estimated > @max_chunk_number_count ->
            {:cont, chunk, {[datum], estimated}}

          true ->
            {:cont, {chunk ++ [datum], count + estimated}}
        end
      end,
      fn
        {[], 0} -> {:cont, []}
        {chunk, _count} -> {:cont, chunk, {[], 0}}
      end
    )
  end

  defp estimate_number_count(%{model_input: model_input, loss_fn_inputs: loss_inputs}) do
    model_input_count =
      case model_input do
        nil -> 0
        %_{} -> Tinkex.Types.ModelInput.length(model_input)
        _ -> 0
      end

    loss_count =
      loss_inputs
      |> Map.values()
      |> Enum.reduce(0, fn
        %{data: data}, acc when is_list(data) -> acc + length(data)
        _other, acc -> acc
      end)

    model_input_count + loss_count
  end

  defp allocate_request_ids(count, counter) when count <= 0, do: {[], counter}

  defp allocate_request_ids(count, counter) do
    ids = Enum.to_list(counter..(counter + count - 1))
    {ids, counter + count}
  end

  defp unlink_task(%Task{pid: pid}) when is_pid(pid) do
    Process.unlink(pid)
    :ok
  end

  defp unlink_task(_), do: :ok

  defp handle_save_weights_response(%{"request_id" => _} = future, state, opts) do
    poll_save_weights_future(future, state, opts)
  end

  defp handle_save_weights_response(%{request_id: _} = future, state, opts) do
    poll_save_weights_future(future, state, opts)
  end

  defp handle_save_weights_response(result, _state, _opts), do: {:ok, result}

  defp poll_save_weights_future(future, state, opts) do
    task =
      state.future_module.poll(
        future,
        poll_opts_with_type(state, opts, "SaveWeightsForSampler")
      )

    unlink_task(task)
    safe_await(state.future_module, task, await_timeout(opts))
  end

  defp poll_opts(state, opts) do
    opts
    |> Keyword.take([
      :timeout,
      :http_timeout,
      :telemetry_metadata,
      :queue_state_observer,
      :sleep_fun
    ])
    |> Keyword.put(:config, state.config)
  end

  defp poll_opts_with_type(state, opts, request_type) do
    poll_opts(state, opts)
    |> Keyword.put(:tinker_request_type, request_type)
  end

  defp safe_await(future_module, task, timeout) do
    try do
      future_module.await(task, timeout)
    rescue
      e ->
        {:error,
         Error.new(:request_failed, "Polling task failed: #{Exception.message(e)}",
           data: %{exception: e, stacktrace: __STACKTRACE__}
         )}
    catch
      :exit, reason ->
        {:error,
         Error.new(:request_failed, "Polling task exited: #{inspect(reason)}",
           data: %{exit_reason: reason}
         )}
    end
  end

  defp await_timeout(opts), do: Keyword.get(opts, :await_timeout, :infinity)
end
