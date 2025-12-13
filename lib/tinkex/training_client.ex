defmodule Tinkex.TrainingClient do
  @moduledoc """
  GenServer that coordinates training operations for a single model.

  Requests are **sent sequentially** within the GenServer while polling is
  performed concurrently in background tasks. This keeps request ordering
  deterministic at the cost of blocking the GenServer during the send phase.

  Use `Tinkex.Types.ModelInput.from_text/2` to turn raw strings into
  tokenized `ModelInput` structs before constructing training data. Chat
  templates are not applied automatically; provide fully formatted text.

  ## Queue State Observer

  This client implements `Tinkex.QueueStateObserver` and automatically logs
  human-readable warnings when queue state changes indicate rate limiting
  or capacity issues:

      [warning] Training is paused for model-xyz. Reason: concurrent training clients rate limit hit

  Logs are debounced to once per 60 seconds per model to avoid spam.
  """

  use GenServer
  use Tinkex.Telemetry.Provider

  @behaviour Tinkex.QueueStateObserver

  require Logger

  alias Tinkex.API.{Models, Service, Training, Weights}
  alias Tinkex.Error
  alias Tinkex.Future.Combiner
  alias Tinkex.Telemetry.Reporter
  alias Tinkex.Telemetry.Capture, as: TelemetryCapture
  require TelemetryCapture
  alias Tinkex.Training.CustomLoss

  alias Tinkex.TrainingClient.{DataProcessor, Observer, Operations, Polling, Tokenizer}

  alias Tinkex.Types.{
    GetInfoRequest,
    GetInfoResponse,
    OptimStepResponse,
    UnloadModelRequest,
    UnloadModelResponse
  }

  @type t :: pid()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc """
  Fetch model metadata for the training client.

  Used by tokenizer resolution to obtain `model_data.tokenizer_id`.
  """
  @spec get_info(t()) :: {:ok, GetInfoResponse.t()} | {:error, Error.t()}
  def get_info(client) do
    GenServer.call(client, :get_info)
  end

  @doc """
  Get a tokenizer for this training client's model.

  Fetches model info to determine the tokenizer ID, applies heuristics
  (e.g., Llama-3 gating workaround), and loads/caches the tokenizer.

  ## Options

    * `:load_fun` - Custom tokenizer loader function (default: HuggingFace)
    * `:info_fun` - Custom info fetcher for testing

  ## Examples

      {:ok, _tokenizer} = TrainingClient.get_tokenizer(client)
      {:ok, ids} = TrainingClient.encode(client, "Hello world")

  ## Errors

  Returns `{:error, %Tinkex.Error{}}` if:
    * Model info cannot be fetched
    * Tokenizer cannot be loaded
  """
  @spec get_tokenizer(t(), keyword()) ::
          {:ok, Tinkex.Tokenizer.handle()} | {:error, Error.t()}
  def get_tokenizer(client, opts \\ []) do
    Tokenizer.get_tokenizer(client, opts)
  end

  @doc """
  Encode text using this training client's tokenizer.

  Convenience wrapper around `Tinkex.Tokenizer.encode/3` that automatically
  resolves the tokenizer from the training client's model info.

  ## Examples

      {:ok, ids} = TrainingClient.encode(client, "Hello world")

  ## Options

    * `:load_fun` - Custom tokenizer loader function
    * `:info_fun` - Custom info fetcher for testing
  """
  @spec encode(t(), String.t(), keyword()) ::
          {:ok, [integer()]} | {:error, Error.t()}
  def encode(client, text, opts \\ []) when is_binary(text) do
    Tokenizer.encode(client, text, opts)
  end

  @doc """
  Decode token IDs using this training client's tokenizer.

  Convenience wrapper around `Tinkex.Tokenizer.decode/3` that automatically
  resolves the tokenizer from the training client's model info.

  ## Examples

      {:ok, text} = TrainingClient.decode(client, [1, 2, 3])

  ## Options

    * `:load_fun` - Custom tokenizer loader function
    * `:info_fun` - Custom info fetcher for testing
  """
  @spec decode(t(), [integer()], keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def decode(client, ids, opts \\ []) when is_list(ids) do
    Tokenizer.decode(client, ids, opts)
  end

  @doc """
  Unload the active model and end the session.
  """
  @spec unload_model(t()) :: {:ok, UnloadModelResponse.t() | map()} | {:error, Error.t()}
  def unload_model(client) do
    GenServer.call(client, :unload_model)
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
  Run a forward-only pass over the provided data (inference without backward).

  Returns logprobs that can be converted to Nx tensors via `TensorData.to_nx/1`.
  Useful for custom loss computation where gradients are computed in Elixir/Nx.

  Returns a `Task.t()` that yields `{:ok, %ForwardBackwardOutput{}}` or
  `{:error, %Tinkex.Error{}}`.

  ## Examples

      {:ok, task} = TrainingClient.forward(client, data, :cross_entropy)
      {:ok, output} = Task.await(task)

      # Access logprobs from output.loss_fn_outputs
      [%{"logprobs" => logprobs_data}] = output.loss_fn_outputs
      tensor = TensorData.to_nx(%TensorData{...logprobs_data})
  """
  @spec forward(t(), [map()], atom() | String.t(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def forward(client, data, loss_fn, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:forward, data, loss_fn, opts}, :infinity)
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

  ## Parameters
  - `client` - The TrainingClient pid
  - `name` - Name/path for the saved sampler weights (required)
  - `opts` - Additional options

  Returns a `Task.t()` that yields `{:ok, %SaveWeightsForSamplerResponse{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec save_weights_for_sampler(t(), String.t(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def save_weights_for_sampler(client, name, opts \\ []) when is_binary(name) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:save_weights_for_sampler, name, opts}, :infinity)
     end)}
  end

  @doc """
  Save weights for sampling and immediately create a SamplingClient.

  Supports both persisted sampler checkpoints (path-based) and ephemeral
  sampling sessions (sampling_session_id-only responses).
  """
  @spec save_weights_and_get_sampling_client(t(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def save_weights_and_get_sampling_client(client, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:save_weights_and_get_sampling_client, opts}, :infinity)
     end)}
  end

  @doc """
  Synchronous helper for `save_weights_and_get_sampling_client/2`.

  Waits for sampler save + SamplingClient creation and returns the pid directly.
  """
  @spec save_weights_and_get_sampling_client_sync(t(), keyword()) ::
          {:ok, pid()} | {:error, Error.t()}
  def save_weights_and_get_sampling_client_sync(client, opts \\ []) do
    with {:ok, task} <- save_weights_and_get_sampling_client(client, opts) do
      timeout = Keyword.get(opts, :await_timeout, :infinity)

      try do
        Task.await(task, timeout)
      catch
        :exit, reason ->
          {:error,
           Error.new(:request_failed, "save_weights_and_get_sampling_client failed",
             data: %{exit_reason: reason}
           )}
      end
    end
  end

  @doc """
  Save model weights as a training checkpoint.

  Returns a `Task.t()` that yields `{:ok, %SaveWeightsResponse{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec save_state(t(), String.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def save_state(client, name, opts \\ []) when is_binary(name) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:save_state, name, opts}, :infinity)
     end)}
  end

  @doc """
  Load model weights from a checkpoint (without optimizer state).

  Returns a `Task.t()` that yields `{:ok, %LoadWeightsResponse{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec load_state(t(), String.t(), keyword()) :: {:ok, Task.t()} | {:error, Error.t()}
  def load_state(client, path, opts \\ []) when is_binary(path) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:load_state, path, false, opts}, :infinity)
     end)}
  end

  @doc """
  Load model weights and optimizer state from a checkpoint.

  Returns a `Task.t()` that yields `{:ok, %LoadWeightsResponse{}}` or
  `{:error, %Tinkex.Error{}}`.
  """
  @spec load_state_with_optimizer(t(), String.t(), keyword()) ::
          {:ok, Task.t()} | {:error, Error.t()}
  def load_state_with_optimizer(client, path, opts \\ []) when is_binary(path) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:load_state, path, true, opts}, :infinity)
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

  @doc """
  Compute forward/backward pass with a custom loss function.

  This mirrors the Python SDK: performs a forward pass to obtain per-datum
  logprobs, computes a custom loss, turns gradients into synthetic weights,
  and sends them back via `forward_backward/4`. The returned
  `ForwardBackwardOutput` is compatible with `optim_step/2`.

  ## Parameters
  - client: TrainingClient pid
  - data: List of training data (Datum structs)
  - loss_fn: `(data, logprobs_list) -> {loss_tensor, metrics_map}`
    * `logprobs_list` is a list of Nx tensors, one per datum
  - opts: Options forwarded to the underlying forward/forward_backward requests

  ## Returns
  `{:ok, Task.t()}` that yields `{:ok, ForwardBackwardOutput.t()}` or `{:error, Error.t()}`

  ## Examples

      {:ok, task} = TrainingClient.forward_backward_custom(
        client, data, &my_loss_fn/2
      )
      {:ok, %ForwardBackwardOutput{} = output} = Task.await(task)
  """
  @spec forward_backward_custom(
          t(),
          list(Tinkex.Types.Datum.t()),
          loss_fn ::
            (list(Tinkex.Types.Datum.t()), [Nx.Tensor.t()] ->
               {Nx.Tensor.t(), map()}),
          keyword()
        ) :: {:ok, Task.t()} | {:error, Error.t()}
  def forward_backward_custom(client, data, loss_fn, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:forward_backward_custom, data, loss_fn, opts}, :infinity)
     end)}
  end

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    session_id = Keyword.fetch!(opts, :session_id)
    model_seq_id = Keyword.fetch!(opts, :model_seq_id)
    service_api = Keyword.get(opts, :service_api, Service)
    training_api = Keyword.get(opts, :training_api, Training)
    models_api = Keyword.get(opts, :models_api, Models)
    weights_api = Keyword.get(opts, :weights_api, Weights)
    sampling_client_module = Keyword.get(opts, :sampling_client_module, Tinkex.SamplingClient)
    future_module = Keyword.get(opts, :future_module, Tinkex.Future)
    client_supervisor = Keyword.get(opts, :client_supervisor, Tinkex.ClientSupervisor)

    telemetry_metadata =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> Map.new()
      |> Map.put_new(:session_id, session_id)

    case Operations.ensure_model(
           opts,
           session_id,
           model_seq_id,
           config,
           service_api,
           telemetry_metadata
         ) do
      {:ok, model_id} ->
        state = %{
          model_id: model_id,
          session_id: session_id,
          model_seq_id: model_seq_id,
          config: config,
          http_pool: config.http_pool,
          request_id_counter: 1,
          sampling_session_counter: 0,
          training_api: training_api,
          models_api: models_api,
          weights_api: weights_api,
          sampling_client_module: sampling_client_module,
          future_module: future_module,
          client_supervisor: client_supervisor,
          telemetry_metadata: telemetry_metadata,
          telemetry: Keyword.get(opts, :telemetry)
        }

        put_telemetry(state.telemetry)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def get_telemetry do
    :erlang.get({__MODULE__, :telemetry})
  end

  def get_telemetry(client) when is_pid(client) do
    GenServer.call(client, :get_telemetry)
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    capture_telemetry(state, fn -> {:reply, state.telemetry, state} end)
  end

  @impl true
  def handle_call({:forward_backward, data, loss_fn, opts}, from, state) do
    capture_telemetry(state, fn ->
      chunks = DataProcessor.chunk_data(data)

      {seq_ids, new_counter} =
        DataProcessor.allocate_request_ids(length(chunks), state.request_id_counter)

      send_result =
        Enum.reduce_while(Enum.zip(seq_ids, chunks), {:ok, []}, fn {seq_id, chunk}, {:ok, acc} ->
          case Operations.send_forward_backward_request(chunk, loss_fn, seq_id, opts, state) do
            {:ok, future} -> {:cont, {:ok, [future | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case send_result do
        {:error, reason} ->
          {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

        {:ok, futures_rev} ->
          futures = Enum.reverse(futures_rev)

          start_background_task(
            fn ->
              reply =
                try do
                  polling_tasks =
                    Enum.map(futures, fn future ->
                      task =
                        state.future_module.poll(
                          future,
                          Polling.poll_opts_with_type(state, opts, "ForwardBackward")
                        )

                      Polling.unlink_task(task)
                      task
                    end)

                  case Polling.await_forward_backward_results(polling_tasks, state.future_module) do
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

              safe_reply(from, reply)
            end,
            from,
            state.telemetry
          )

          {:noreply, %{state | request_id_counter: new_counter}}
      end
    end)
  end

  @impl true
  def handle_call({:forward, data, loss_fn, opts}, from, state) do
    capture_telemetry(state, fn ->
      chunks = DataProcessor.chunk_data(data)

      {seq_ids, new_counter} =
        DataProcessor.allocate_request_ids(length(chunks), state.request_id_counter)

      send_result =
        Enum.reduce_while(Enum.zip(seq_ids, chunks), {:ok, []}, fn {seq_id, chunk}, {:ok, acc} ->
          case Operations.send_forward_request(chunk, loss_fn, seq_id, opts, state) do
            {:ok, future} -> {:cont, {:ok, [future | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case send_result do
        {:error, reason} ->
          {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

        {:ok, futures_rev} ->
          futures = Enum.reverse(futures_rev)

          start_background_task(
            fn ->
              reply =
                try do
                  polling_tasks =
                    Enum.map(futures, fn future ->
                      task =
                        state.future_module.poll(
                          future,
                          Polling.poll_opts_with_type(state, opts, "Forward")
                        )

                      Polling.unlink_task(task)
                      task
                    end)

                  case Polling.await_forward_results(polling_tasks, state.future_module) do
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

              safe_reply(from, reply)
            end,
            from,
            state.telemetry
          )

          {:noreply, %{state | request_id_counter: new_counter}}
      end
    end)
  end

  @impl true
  def handle_call({:optim_step, adam_params, opts}, from, state) do
    capture_telemetry(state, fn ->
      seq_id = state.request_id_counter
      new_counter = seq_id + 1

      case Operations.send_optim_step_request(adam_params, seq_id, opts, state) do
        {:error, reason} ->
          {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

        {:ok, future} ->
          start_background_task(
            fn ->
              reply =
                try do
                  task =
                    state.future_module.poll(
                      future,
                      Polling.poll_opts_with_type(state, opts, "OptimStep")
                    )

                  Polling.unlink_task(task)

                  case Polling.safe_await(state.future_module, task, await_timeout(opts)) do
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

              safe_reply(from, reply)
            end,
            from,
            state.telemetry
          )

          {:noreply, %{state | request_id_counter: new_counter}}
      end
    end)
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    capture_telemetry(state, fn ->
      case state.models_api.get_info(
             %GetInfoRequest{model_id: state.model_id},
             config: state.config,
             telemetry_metadata: base_telemetry_metadata(state, %{model_id: state.model_id})
           ) do
        {:ok, %GetInfoResponse{} = response} ->
          {:reply, {:ok, response}, state}

        {:error, %Error{} = error} ->
          {:reply, {:error, error}, state}
      end
    end)
  end

  @impl true
  def handle_call(:unload_model, _from, state) do
    capture_telemetry(state, fn ->
      case state.models_api.unload_model(
             %UnloadModelRequest{model_id: state.model_id},
             config: state.config,
             telemetry_metadata: base_telemetry_metadata(state, %{model_id: state.model_id})
           ) do
        {:ok, %{"request_id" => _} = future} ->
          reply = Polling.poll_and_await_unload(future, state, [])
          {:reply, reply, state}

        {:ok, %{request_id: _} = future} ->
          reply = Polling.poll_and_await_unload(future, state, [])
          {:reply, reply, state}

        {:ok, %UnloadModelResponse{} = response} ->
          {:reply, {:ok, response}, state}

        {:ok, %{} = payload} ->
          {:reply, {:ok, UnloadModelResponse.from_json(payload)}, state}

        {:error, %Error{} = error} ->
          {:reply, {:error, error}, state}
      end
    end)
  end

  @impl true
  def handle_call({:save_state, name, opts}, from, state) do
    capture_telemetry(state, fn ->
      seq_id = state.request_id_counter
      new_counter = seq_id + 1

      case Operations.send_save_state_request(name, seq_id, opts, state) do
        {:error, reason} ->
          {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

        {:ok, response} ->
          start_background_task(
            fn ->
              reply =
                try do
                  Operations.handle_save_state_response(response, state, opts)
                rescue
                  e ->
                    {:error,
                     %Error{
                       message: "Save state failed: #{Exception.message(e)}",
                       type: :request_failed,
                       data: %{exception: e, stacktrace: __STACKTRACE__}
                     }}
                end

              safe_reply(from, reply)
            end,
            from,
            state.telemetry
          )

          {:noreply, %{state | request_id_counter: new_counter}}
      end
    end)
  end

  @impl true
  def handle_call({:load_state, path, optimizer, opts}, from, state) do
    capture_telemetry(state, fn ->
      seq_id = state.request_id_counter
      new_counter = seq_id + 1

      case Operations.send_load_state_request(path, optimizer, seq_id, opts, state) do
        {:error, reason} ->
          {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

        {:ok, response} ->
          start_background_task(
            fn ->
              reply =
                try do
                  Operations.handle_load_state_response(response, state, opts)
                rescue
                  e ->
                    {:error,
                     %Error{
                       message: "Load state failed: #{Exception.message(e)}",
                       type: :request_failed,
                       data: %{exception: e, stacktrace: __STACKTRACE__}
                     }}
                end

              safe_reply(from, reply)
            end,
            from,
            state.telemetry
          )

          {:noreply, %{state | request_id_counter: new_counter}}
      end
    end)
  end

  @impl true
  def handle_call({:save_weights_for_sampler, name, opts}, from, state) do
    capture_telemetry(state, fn ->
      seq_id = state.request_id_counter
      new_counter = seq_id + 1

      # Put name as path in opts for the request
      opts_with_path = Keyword.put(opts, :path, name)

      {normalized_opts, next_sampling_counter} =
        Operations.normalize_save_weights_opts(opts_with_path, state)

      case Operations.send_save_weights_for_sampler_request(seq_id, normalized_opts, state) do
        {:error, reason} ->
          {:reply, {:error, reason},
           %{
             state
             | request_id_counter: new_counter,
               sampling_session_counter: next_sampling_counter
           }}

        {:ok, response} ->
          start_background_task(
            fn ->
              reply =
                try do
                  Operations.handle_save_weights_response(response, state, normalized_opts)
                rescue
                  e ->
                    {:error,
                     %Error{
                       message: "Save weights failed: #{Exception.message(e)}",
                       type: :request_failed,
                       data: %{exception: e, stacktrace: __STACKTRACE__}
                     }}
                end

              safe_reply(from, reply)
            end,
            from,
            state.telemetry
          )

          {:noreply,
           %{
             state
             | request_id_counter: new_counter,
               sampling_session_counter: next_sampling_counter
           }}
      end
    end)
  end

  @impl true
  def handle_call({:save_weights_and_get_sampling_client, opts}, from, state) do
    capture_telemetry(state, fn ->
      seq_id = state.request_id_counter
      new_counter = seq_id + 1

      {normalized_opts, next_sampling_counter} =
        Operations.normalize_save_weights_opts(opts, state)

      case Operations.send_save_weights_for_sampler_request(seq_id, normalized_opts, state) do
        {:error, reason} ->
          {:reply, {:error, reason},
           %{
             state
             | request_id_counter: new_counter,
               sampling_session_counter: next_sampling_counter
           }}

        {:ok, response} ->
          start_background_task(
            fn ->
              reply =
                with {:ok, save_response} <-
                       Operations.handle_save_weights_response(response, state, normalized_opts),
                     {:ok, sampling_client} <-
                       Operations.start_sampling_client_from_save(
                         save_response,
                         seq_id,
                         opts,
                         state
                       ) do
                  {:ok, sampling_client}
                else
                  {:error, %Error{} = error} -> {:error, error}
                  {:error, reason} -> {:error, reason}
                end

              safe_reply(from, reply)
            end,
            from,
            state.telemetry
          )

          {:noreply,
           %{
             state
             | request_id_counter: new_counter,
               sampling_session_counter: next_sampling_counter
           }}
      end
    end)
  end

  @impl true
  def handle_call({:create_sampling_client, model_path, opts}, _from, state) do
    capture_telemetry(state, fn ->
      child_opts =
        opts
        |> Keyword.put(:session_id, state.session_id)
        |> Keyword.put(:config, state.config)
        |> Keyword.put(:model_path, model_path)
        |> Keyword.put(:sampling_client_id, state.request_id_counter)

      case DynamicSupervisor.start_child(
             state.client_supervisor,
             {state.sampling_client_module, child_opts}
           ) do
        {:ok, pid} ->
          {:reply, {:ok, pid}, %{state | request_id_counter: state.request_id_counter + 1}}

        {:error, _} = error ->
          {:reply, error, state}
      end
    end)
  end

  @impl true
  def handle_call({:forward_backward_custom, data, loss_fn, opts}, from, state) do
    capture_telemetry(state, fn ->
      with {:ok, placeholder_gradients} <- DataProcessor.build_placeholder_gradients(data) do
        placeholder_linear_data = CustomLoss.build_linear_loss_data(data, placeholder_gradients)
        linear_chunks = DataProcessor.chunk_data(placeholder_linear_data)
        chunks = DataProcessor.chunk_data(data)

        forward_count = length(chunks)
        backward_count = length(linear_chunks)

        {seq_ids, new_counter} =
          DataProcessor.allocate_request_ids(
            forward_count + backward_count,
            state.request_id_counter
          )

        {forward_seq_ids, backward_seq_ids} = Enum.split(seq_ids, forward_count)

        send_result =
          Enum.reduce_while(Enum.zip(forward_seq_ids, chunks), {:ok, []}, fn {seq_id, chunk},
                                                                             {:ok, acc} ->
            case Operations.send_forward_request(chunk, :cross_entropy, seq_id, opts, state) do
              {:ok, future} -> {:cont, {:ok, [future | acc]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case send_result do
          {:error, reason} ->
            {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

          {:ok, forward_futures_rev} ->
            forward_futures = Enum.reverse(forward_futures_rev)

            start_background_task(
              fn ->
                reply =
                  try do
                    with {:ok, forward_outputs} <-
                           Operations.poll_forward_custom_loss(forward_futures, opts, state),
                         {:ok, logprobs} <-
                           CustomLoss.extract_per_datum_logprobs(forward_outputs),
                         {:ok, {gradients, metrics}} <-
                           CustomLoss.compute_gradients(data, logprobs, loss_fn),
                         {:ok, linear_data} <-
                           Operations.build_linear_loss_data_safe(data, gradients),
                         {:ok, backward_outputs} <-
                           Operations.send_backward_for_custom_loss(
                             linear_data,
                             backward_seq_ids,
                             opts,
                             state
                           ) do
                      combined = Combiner.combine_forward_backward_results(backward_outputs)
                      {:ok, Operations.merge_custom_metrics(combined, metrics)}
                    else
                      {:error, %Error{} = error} ->
                        {:error, error}

                      {:error, reason} ->
                        {:error,
                         Error.new(:request_failed, "Custom loss failed: #{inspect(reason)}")}
                    end
                  rescue
                    e ->
                      {:error,
                       %Error{
                         message: "Custom loss failed: #{Exception.message(e)}",
                         type: :request_failed,
                         data: %{exception: e, stacktrace: __STACKTRACE__}
                       }}
                  end

                safe_reply(from, reply)
              end,
              from,
              state.telemetry
            )

            {:noreply, %{state | request_id_counter: new_counter}}
        end
      else
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end)
  end

  @impl true
  def handle_call(_message, _from, state),
    do: capture_telemetry(state, fn -> {:reply, {:error, :unsupported}, state} end)

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Reporter.stop(state[:telemetry])
    :ok
  end

  # QueueStateObserver implementation
  # Delegates to the Observer module
  @impl Tinkex.QueueStateObserver
  def on_queue_state_change(queue_state, metadata \\ %{}) do
    Observer.on_queue_state_change(queue_state, metadata)
  end

  # Private helpers

  defp safe_reply(from, reply) do
    try do
      GenServer.reply(from, reply)
    rescue
      ArgumentError -> :ok
    end
  end

  defp capture_telemetry(state, fun) when is_function(fun, 0) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      fun.()
    end
  end

  defp start_background_task(fun, from, reporter) when is_function(fun, 0) do
    wrapped_fun =
      if reporter do
        fn ->
          TelemetryCapture.capture_exceptions reporter: reporter, fatal?: true do
            fun.()
          end
        end
      else
        fun
      end

    try do
      case Task.Supervisor.async_nolink(Tinkex.TaskSupervisor, wrapped_fun) do
        %Task{pid: pid} ->
          ref = Process.monitor(pid)

          # Monitor abnormal exits so callers get an explicit error instead of hanging.
          Task.Supervisor.start_child(Tinkex.TaskSupervisor, fn ->
            receive do
              {:DOWN, ^ref, :process, _pid, :normal} ->
                :ok

              {:DOWN, ^ref, :process, _pid, reason} ->
                safe_reply(
                  from,
                  {:error,
                   Error.new(:request_failed, "Background task crashed",
                     data: %{exit_reason: reason}
                   )}
                )
            end
          end)

          :ok
      end
    rescue
      exception ->
        Logger.error("Failed to start training background task: #{Exception.message(exception)}")
        safe_reply(from, {:error, Error.new(:request_failed, "Background task failed to start")})
        :error
    end
  end

  defp base_telemetry_metadata(state, extra) when is_map(extra) do
    Map.merge(state.telemetry_metadata, extra)
  end

  defp put_telemetry(nil), do: :ok
  defp put_telemetry(pid), do: :erlang.put({__MODULE__, :telemetry}, pid)

  defp await_timeout(opts), do: Keyword.get(opts, :await_timeout, :infinity)
end
