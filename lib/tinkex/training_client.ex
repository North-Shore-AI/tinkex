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

      [warning] Training is paused for model-xyz. Reason: concurrent models rate limit hit

  Logs are debounced to once per 60 seconds per model to avoid spam.
  """

  use GenServer
  use Tinkex.Telemetry.Provider

  @behaviour Tinkex.QueueStateObserver

  require Logger

  alias Tinkex.API.{Models, Service, Training, Weights}
  alias Tinkex.Error
  alias Tinkex.Future.Combiner
  alias Tinkex.QueueStateLogger
  alias Tinkex.Telemetry.Reporter
  alias Tinkex.Training.CustomLoss

  alias Tinkex.Types.{
    Datum,
    CreateModelRequest,
    CreateModelResponse,
    ForwardBackwardInput,
    ForwardBackwardOutput,
    ForwardBackwardRequest,
    ForwardRequest,
    GetInfoRequest,
    GetInfoResponse,
    LoraConfig,
    LoadWeightsRequest,
    LoadWeightsResponse,
    OptimStepRequest,
    OptimStepResponse,
    TensorData,
    SaveWeightsForSamplerRequest,
    SaveWeightsForSamplerResponse,
    SaveWeightsRequest,
    SaveWeightsResponse,
    UnloadModelRequest,
    UnloadModelResponse
  }

  @max_chunk_len 128
  @max_chunk_number_count 500_000

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

      {:ok, tokenizer} = TrainingClient.get_tokenizer(client)
      {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, "Hello world")

  ## Errors

  Returns `{:error, %Tinkex.Error{}}` if:
    * Model info cannot be fetched
    * Tokenizer cannot be loaded
  """
  @spec get_tokenizer(t(), keyword()) ::
          {:ok, Tokenizers.Tokenizer.t()} | {:error, Error.t()}
  def get_tokenizer(client, opts \\ []) do
    info_fun = Keyword.get(opts, :info_fun, &get_info/1)

    with {:ok, info} <- info_fun.(client) do
      model_name = get_model_name_from_info(info)
      tokenizer_id = Tinkex.Tokenizer.get_tokenizer_id(model_name, client, opts)
      Tinkex.Tokenizer.get_or_load_tokenizer(tokenizer_id, opts)
    end
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
    info_fun = Keyword.get(opts, :info_fun, &get_info/1)

    with {:ok, info} <- info_fun.(client) do
      model_name = get_model_name_from_info(info)
      Tinkex.Tokenizer.encode(text, model_name, Keyword.put(opts, :training_client, client))
    end
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
    info_fun = Keyword.get(opts, :info_fun, &get_info/1)

    with {:ok, info} <- info_fun.(client) do
      model_name = get_model_name_from_info(info)
      Tinkex.Tokenizer.decode(ids, model_name, Keyword.put(opts, :training_client, client))
    end
  end

  # Extract model name from GetInfoResponse for tokenizer resolution
  defp get_model_name_from_info(%GetInfoResponse{model_data: %{base_model: base}})
       when is_binary(base),
       do: base

  defp get_model_name_from_info(%GetInfoResponse{model_data: %{model_name: name}})
       when is_binary(name),
       do: name

  defp get_model_name_from_info(%{model_data: %{base_model: base}})
       when is_binary(base),
       do: base

  defp get_model_name_from_info(%{model_data: %{model_name: name}})
       when is_binary(name),
       do: name

  defp get_model_name_from_info(_), do: "unknown"

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

    case ensure_model(opts, session_id, model_seq_id, config, service_api, telemetry_metadata) do
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
    {:reply, state.telemetry, state}
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

        start_background_task(
          fn ->
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

            safe_reply(from, reply)
          end,
          from
        )

        {:noreply, %{state | request_id_counter: new_counter}}
    end
  end

  @impl true
  def handle_call({:forward, data, loss_fn, opts}, from, state) do
    chunks = chunk_data(data)
    {seq_ids, new_counter} = allocate_request_ids(length(chunks), state.request_id_counter)

    send_result =
      Enum.reduce_while(Enum.zip(seq_ids, chunks), {:ok, []}, fn {seq_id, chunk}, {:ok, acc} ->
        case send_forward_request(chunk, loss_fn, seq_id, opts, state) do
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
                        poll_opts_with_type(state, opts, "Forward")
                      )

                    unlink_task(task)
                    task
                  end)

                case await_forward_results(polling_tasks, state.future_module) do
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
          from
        )

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
        start_background_task(
          fn ->
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

            safe_reply(from, reply)
          end,
          from
        )

        {:noreply, %{state | request_id_counter: new_counter}}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
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
  end

  @impl true
  def handle_call(:unload_model, _from, state) do
    case state.models_api.unload_model(
           %UnloadModelRequest{model_id: state.model_id},
           config: state.config,
           telemetry_metadata: base_telemetry_metadata(state, %{model_id: state.model_id})
         ) do
      {:ok, %{"request_id" => _} = future} ->
        reply = await_unload_future(future, state)
        {:reply, reply, state}

      {:ok, %{request_id: _} = future} ->
        reply = await_unload_future(future, state)
        {:reply, reply, state}

      {:ok, %UnloadModelResponse{} = response} ->
        {:reply, {:ok, response}, state}

      {:ok, %{} = payload} ->
        {:reply, {:ok, UnloadModelResponse.from_json(payload)}, state}

      {:error, %Error{} = error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:save_state, name, opts}, from, state) do
    seq_id = state.request_id_counter
    new_counter = seq_id + 1

    case send_save_state_request(name, seq_id, opts, state) do
      {:error, reason} ->
        {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

      {:ok, response} ->
        start_background_task(
          fn ->
            reply =
              try do
                handle_save_state_response(response, state, opts)
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
          from
        )

        {:noreply, %{state | request_id_counter: new_counter}}
    end
  end

  @impl true
  def handle_call({:load_state, path, optimizer, opts}, from, state) do
    seq_id = state.request_id_counter
    new_counter = seq_id + 1

    case send_load_state_request(path, optimizer, seq_id, opts, state) do
      {:error, reason} ->
        {:reply, {:error, reason}, %{state | request_id_counter: new_counter}}

      {:ok, response} ->
        start_background_task(
          fn ->
            reply =
              try do
                handle_load_state_response(response, state, opts)
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
          from
        )

        {:noreply, %{state | request_id_counter: new_counter}}
    end
  end

  @impl true
  def handle_call({:save_weights_for_sampler, name, opts}, from, state) do
    seq_id = state.request_id_counter
    new_counter = seq_id + 1

    # Put name as path in opts for the request
    opts_with_path = Keyword.put(opts, :path, name)
    {normalized_opts, next_sampling_counter} = normalize_save_weights_opts(opts_with_path, state)

    case send_save_weights_for_sampler_request(seq_id, normalized_opts, state) do
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
                handle_save_weights_response(response, state, normalized_opts)
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
          from
        )

        {:noreply,
         %{
           state
           | request_id_counter: new_counter,
             sampling_session_counter: next_sampling_counter
         }}
    end
  end

  @impl true
  def handle_call({:save_weights_and_get_sampling_client, opts}, from, state) do
    seq_id = state.request_id_counter
    new_counter = seq_id + 1

    {normalized_opts, next_sampling_counter} = normalize_save_weights_opts(opts, state)

    case send_save_weights_for_sampler_request(seq_id, normalized_opts, state) do
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
                     handle_save_weights_response(response, state, normalized_opts),
                   {:ok, sampling_client} <-
                     start_sampling_client_from_save(save_response, seq_id, opts, state) do
                {:ok, sampling_client}
              else
                {:error, %Error{} = error} -> {:error, error}
                {:error, reason} -> {:error, reason}
              end

            safe_reply(from, reply)
          end,
          from
        )

        {:noreply,
         %{
           state
           | request_id_counter: new_counter,
             sampling_session_counter: next_sampling_counter
         }}
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
           {state.sampling_client_module, child_opts}
         ) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, %{state | request_id_counter: state.request_id_counter + 1}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:forward_backward_custom, data, loss_fn, opts}, from, state) do
    with {:ok, placeholder_gradients} <- build_placeholder_gradients(data) do
      placeholder_linear_data = CustomLoss.build_linear_loss_data(data, placeholder_gradients)
      linear_chunks = chunk_data(placeholder_linear_data)
      chunks = chunk_data(data)

      forward_count = length(chunks)
      backward_count = length(linear_chunks)

      {seq_ids, new_counter} =
        allocate_request_ids(forward_count + backward_count, state.request_id_counter)

      {forward_seq_ids, backward_seq_ids} = Enum.split(seq_ids, forward_count)

      send_result =
        Enum.reduce_while(Enum.zip(forward_seq_ids, chunks), {:ok, []}, fn {seq_id, chunk},
                                                                           {:ok, acc} ->
          case send_forward_request(chunk, :cross_entropy, seq_id, opts, state) do
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
                         poll_forward_custom_loss(forward_futures, opts, state),
                       {:ok, logprobs} <-
                         CustomLoss.extract_per_datum_logprobs(forward_outputs),
                       {:ok, {gradients, metrics}} <-
                         CustomLoss.compute_gradients(data, logprobs, loss_fn),
                       {:ok, linear_data} <- build_linear_loss_data_safe(data, gradients),
                       {:ok, backward_outputs} <-
                         send_backward_for_custom_loss(
                           linear_data,
                           backward_seq_ids,
                           opts,
                           state
                         ) do
                    combined = Combiner.combine_forward_backward_results(backward_outputs)
                    {:ok, merge_custom_metrics(combined, metrics)}
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
            from
          )

          {:noreply, %{state | request_id_counter: new_counter}}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(_message, _from, state), do: {:reply, {:error, :unsupported}, state}

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Reporter.stop(state[:telemetry])
    :ok
  end

  # QueueStateObserver implementation
  # This callback is invoked by Future.poll when queue state changes (e.g., rate limit hit).
  # We use metadata to identify the model and :persistent_term to track debouncing per model.
  @impl Tinkex.QueueStateObserver
  def on_queue_state_change(queue_state, metadata \\ %{}) do
    model_id = metadata[:model_id] || "unknown"

    # Use :persistent_term for debounce tracking keyed by model_id
    debounce_key = {:training_queue_state_debounce, model_id}

    last_logged =
      case :persistent_term.get(debounce_key, nil) do
        nil -> nil
        ts -> ts
      end

    new_timestamp = QueueStateLogger.maybe_log(queue_state, :training, model_id, last_logged)

    # Update the debounce timestamp if it changed
    if new_timestamp != last_logged do
      :persistent_term.put(debounce_key, new_timestamp)
    end

    :ok
  end

  defp ensure_model(opts, session_id, model_seq_id, config, service_api, telemetry_metadata) do
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

  defp send_forward_request(chunk, loss_fn, seq_id, opts, state) do
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

  defp send_optim_step_request(adam_params, seq_id, _opts, state) do
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

  defp send_save_state_request(name, seq_id, _opts, state) do
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

  defp send_load_state_request(path, optimizer, seq_id, _opts, state) do
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

  defp send_save_weights_for_sampler_request(seq_id, opts, state) do
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

  defp await_forward_results([], _future_module), do: {:ok, []}

  defp await_forward_results([task | rest], future_module) do
    case safe_await(future_module, task, :infinity) do
      {:ok, result} ->
        with {:ok, remaining} <- await_forward_results(rest, future_module) do
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
        %Tinkex.Types.ModelInput{chunks: chunks} when is_list(chunks) ->
          Enum.reduce(chunks, 0, fn chunk, acc ->
            acc + _estimate_number_count_in_chunk(chunk)
          end)

        _ ->
          0
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

  defp _estimate_number_count_in_chunk(%Tinkex.Types.ImageChunk{data: data}) when is_binary(data),
    do: byte_size(data)

  defp _estimate_number_count_in_chunk(%Tinkex.Types.ImageAssetPointerChunk{
         location: location
       })
       when is_binary(location),
       do: byte_size(location)

  defp _estimate_number_count_in_chunk(%Tinkex.Types.EncodedTextChunk{} = chunk),
    do: Tinkex.Types.EncodedTextChunk.length(chunk)

  defp _estimate_number_count_in_chunk(%{__struct__: mod} = chunk) do
    if function_exported?(mod, :length, 1) do
      mod.length(chunk)
    else
      0
    end
  end

  defp _estimate_number_count_in_chunk(_chunk), do: 0

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

  defp await_unload_future(future, state) do
    task =
      state.future_module.poll(
        future,
        poll_opts_with_type(state, [], "UnloadModel")
      )

    unlink_task(task)

    case safe_await(state.future_module, task, await_timeout([])) do
      {:ok, result} -> {:ok, UnloadModelResponse.from_json(result)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp safe_reply(from, reply) do
    try do
      GenServer.reply(from, reply)
    rescue
      ArgumentError -> :ok
    end
  end

  defp start_background_task(fun, from) when is_function(fun, 0) do
    try do
      case Task.Supervisor.async_nolink(Tinkex.TaskSupervisor, fun) do
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

  defp handle_save_state_response(%{"request_id" => _} = future, state, opts) do
    poll_save_state_future(future, state, opts)
  end

  defp handle_save_state_response(%{request_id: _} = future, state, opts) do
    poll_save_state_future(future, state, opts)
  end

  defp handle_save_state_response(%SaveWeightsResponse{} = resp, _state, _opts), do: {:ok, resp}

  defp handle_save_state_response(%{"path" => _} = result, _state, _opts) do
    {:ok, SaveWeightsResponse.from_json(result)}
  end

  defp handle_save_state_response(result, _state, _opts), do: {:ok, result}

  defp poll_save_state_future(future, state, opts) do
    task =
      state.future_module.poll(
        future,
        poll_opts_with_type(state, opts, "SaveWeights")
      )

    unlink_task(task)

    case safe_await(state.future_module, task, await_timeout(opts)) do
      {:ok, result} -> {:ok, SaveWeightsResponse.from_json(result)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp handle_load_state_response(%{"request_id" => _} = future, state, opts) do
    poll_load_state_future(future, state, opts)
  end

  defp handle_load_state_response(%{request_id: _} = future, state, opts) do
    poll_load_state_future(future, state, opts)
  end

  defp handle_load_state_response(%LoadWeightsResponse{} = resp, _state, _opts), do: {:ok, resp}

  defp handle_load_state_response(%{"path" => _} = result, _state, _opts) do
    {:ok, LoadWeightsResponse.from_json(result)}
  end

  defp handle_load_state_response(result, _state, _opts), do: {:ok, result}

  defp poll_load_state_future(future, state, opts) do
    task =
      state.future_module.poll(
        future,
        poll_opts_with_type(state, opts, "LoadWeights")
      )

    unlink_task(task)

    case safe_await(state.future_module, task, await_timeout(opts)) do
      {:ok, result} -> {:ok, LoadWeightsResponse.from_json(result)}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp handle_save_weights_response(%{"request_id" => _} = future, state, opts) do
    poll_save_weights_future(future, state, opts)
  end

  defp handle_save_weights_response(%{request_id: _} = future, state, opts) do
    poll_save_weights_future(future, state, opts)
  end

  defp handle_save_weights_response(%SaveWeightsForSamplerResponse{} = resp, _state, _opts),
    do: {:ok, resp}

  defp handle_save_weights_response(%{"path" => _} = result, _state, _opts),
    do: {:ok, SaveWeightsForSamplerResponse.from_json(result)}

  defp handle_save_weights_response(%{"sampling_session_id" => _} = result, _state, _opts),
    do: {:ok, SaveWeightsForSamplerResponse.from_json(result)}

  defp handle_save_weights_response(result, _state, _opts) when is_map(result),
    do: {:ok, SaveWeightsForSamplerResponse.from_json(result)}

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

  defp start_sampling_client_from_save(save_response, sampling_client_id, opts, state) do
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

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_save_weights_opts(opts, state) do
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

  defp poll_opts(state, opts) do
    telemetry_metadata =
      state.telemetry_metadata
      |> Map.merge(Map.new(Keyword.get(opts, :telemetry_metadata, %{})))
      |> Map.put(:model_id, state.model_id)

    # Use __MODULE__ as observer by default for automatic queue state logging
    # Users can override with their own observer via opts[:queue_state_observer]
    observer = Keyword.get(opts, :queue_state_observer, __MODULE__)

    opts
    |> Keyword.take([
      :timeout,
      :http_timeout,
      :telemetry_metadata,
      :sleep_fun
    ])
    |> Keyword.put(:config, state.config)
    |> Keyword.put(:telemetry_metadata, telemetry_metadata)
    |> Keyword.put(:queue_state_observer, observer)
  end

  defp poll_opts_with_type(state, opts, request_type) do
    poll_opts(state, opts)
    |> Keyword.put(:tinker_request_type, request_type)
  end

  defp base_telemetry_metadata(state, extra) when is_map(extra) do
    Map.merge(state.telemetry_metadata, extra)
  end

  defp put_telemetry(nil), do: :ok
  defp put_telemetry(pid), do: :erlang.put({__MODULE__, :telemetry}, pid)

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

  defp build_placeholder_gradients(data) do
    data
    |> Enum.reduce_while({:ok, []}, fn datum, {:ok, acc} ->
      case fetch_target_tokens_tensor(datum) do
        {:ok, target_tensor} ->
          zero =
            Nx.broadcast(
              Nx.tensor(0.0, type: {:f, 32}),
              Nx.shape(target_tensor)
            )

          {:cont, {:ok, [zero | acc]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, grads_rev} -> {:ok, Enum.reverse(grads_rev)}
      {:error, _} = error -> error
    end
  end

  defp fetch_target_tokens_tensor(%Datum{loss_fn_inputs: inputs}) do
    case inputs["target_tokens"] || inputs[:target_tokens] do
      %TensorData{} = td ->
        {:ok, TensorData.to_nx(td)}

      %Nx.Tensor{} = tensor ->
        {:ok, tensor}

      nil ->
        {:error, Error.new(:validation, "target_tokens missing from loss_fn_inputs")}

      other ->
        {:error,
         Error.new(
           :validation,
           "Invalid target_tokens in loss_fn_inputs: #{inspect(other)}"
         )}
    end
  end

  defp poll_forward_custom_loss(futures, opts, state) do
    polling_tasks =
      Enum.map(futures, fn future ->
        task =
          state.future_module.poll(
            future,
            poll_opts_with_type(state, opts, "ForwardCustomLoss")
          )

        unlink_task(task)
        task
      end)

    await_forward_results_for_custom_loss(polling_tasks, state.future_module)
  end

  defp build_linear_loss_data_safe(data, gradients) do
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

  defp send_backward_for_custom_loss(linear_data, seq_ids, opts, state) do
    chunks = chunk_data(linear_data)

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
                  poll_opts_with_type(state, opts, "ForwardBackwardCustomLoss")
                )

              unlink_task(task)
              task
            end)

          await_forward_backward_results(polling_tasks, state.future_module)
      end
    end
  end

  defp merge_custom_metrics(%ForwardBackwardOutput{} = output, metrics) when is_map(metrics) do
    normalized =
      metrics
      |> Enum.map(fn {k, v} -> {to_string(k), normalize_metric_value(v)} end)
      |> Map.new()

    %ForwardBackwardOutput{output | metrics: Map.merge(output.metrics, normalized)}
  end

  defp normalize_metric_value(%Nx.Tensor{} = tensor), do: Nx.to_number(tensor)
  defp normalize_metric_value(other), do: other

  defp await_forward_results_for_custom_loss([], _future_module), do: {:ok, []}

  defp await_forward_results_for_custom_loss([task | rest], future_module) do
    case safe_await(future_module, task, :infinity) do
      {:ok, result} ->
        with {:ok, remaining} <- await_forward_results_for_custom_loss(rest, future_module) do
          {:ok, [ForwardBackwardOutput.from_json(result) | remaining]}
        end

      {:error, %Error{} = error} ->
        Enum.each(rest, &Task.shutdown(&1, :brutal_kill))
        {:error, error}
    end
  end
end
