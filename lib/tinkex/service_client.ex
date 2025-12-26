defmodule Tinkex.ServiceClient do
  @moduledoc """
  Entry point for Tinkex operations.

  Starts a session via `Tinkex.SessionManager`, tracks sequencing counters, and
  spawns Training/Sampling clients under `Tinkex.ClientSupervisor`.
  """

  use GenServer
  use Tinkex.Telemetry.Provider

  require Logger

  alias Tinkex.API.Service
  alias Tinkex.Config
  alias Tinkex.Error
  alias Tinkex.RestClient
  alias Tinkex.SessionManager
  alias Tinkex.Telemetry
  alias Tinkex.Telemetry.Capture, as: TelemetryCapture
  alias Tinkex.Telemetry.Reporter
  require TelemetryCapture
  alias Tinkex.Types.LoraConfig

  @type t :: pid()

  @doc """
  Start a ServiceClient process.

  Accepts `:config` (`Tinkex.Config.t()`) and optional client modules via
  `:training_client_module` / `:sampling_client_module`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Create a training client from this ServiceClient.

  `base_model` is a required second argument specifying the base model name
  (e.g., "meta-llama/Llama-3.1-8B").
  Pass `call_timeout: :infinity` (or a larger timeout in ms) via opts if model
  creation may take longer than the default 5000ms GenServer call timeout.
  """
  @spec create_lora_training_client(t(), String.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def create_lora_training_client(service_client, base_model, opts \\ [])
      when is_binary(base_model) do
    {call_timeout, training_opts} = Keyword.pop(opts, :call_timeout, 5_000)

    GenServer.call(
      service_client,
      {:create_training_client, base_model, training_opts},
      call_timeout
    )
  end

  @doc """
  Create a LoRA training client asynchronously.

  Returns a Task that resolves to `{:ok, pid}` or `{:error, reason}`.
  """
  @spec create_lora_training_client_async(t(), String.t(), keyword()) :: Task.t()
  def create_lora_training_client_async(service_client, base_model, opts \\ [])
      when is_binary(base_model) do
    reporter = telemetry_reporter_for(service_client)

    TelemetryCapture.async_capture reporter: reporter, fatal?: true do
      create_lora_training_client(service_client, base_model, opts)
    end
  end

  @doc """
  Create a training client from a saved checkpoint path.

  Uses checkpoint metadata to configure the client, then loads the weights.
  To include optimizer state, pass `load_optimizer: true` or use
  `create_training_client_from_state_with_optimizer/3`.
  """
  @spec create_training_client_from_state(t(), String.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def create_training_client_from_state(service_client, path, opts \\ []) when is_binary(path) do
    GenServer.call(service_client, {:create_training_client_from_state, path, opts}, :infinity)
  end

  @doc """
  Create a training client from a saved checkpoint path, loading optimizer state.

  Convenience wrapper around `create_training_client_from_state/3` that sets
  `load_optimizer: true`.
  """
  @spec create_training_client_from_state_with_optimizer(t(), String.t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def create_training_client_from_state_with_optimizer(service_client, path, opts \\ [])
      when is_binary(path) do
    opts = Keyword.put(opts, :load_optimizer, true)
    create_training_client_from_state(service_client, path, opts)
  end

  @doc """
  Create a training client from checkpoint asynchronously.

  Returns a Task that resolves to `{:ok, pid}` or `{:error, reason}`.
  """
  @spec create_training_client_from_state_async(t(), String.t(), keyword()) :: Task.t()
  def create_training_client_from_state_async(service_client, path, opts \\ [])
      when is_binary(path) do
    reporter = telemetry_reporter_for(service_client)

    TelemetryCapture.async_capture reporter: reporter, fatal?: true do
      create_training_client_from_state(service_client, path, opts)
    end
  end

  @doc """
  Async variant of `create_training_client_from_state_with_optimizer/3`.
  """
  @spec create_training_client_from_state_with_optimizer_async(t(), String.t(), keyword()) ::
          Task.t()
  def create_training_client_from_state_with_optimizer_async(service_client, path, opts \\ [])
      when is_binary(path) do
    reporter = telemetry_reporter_for(service_client)

    TelemetryCapture.async_capture reporter: reporter, fatal?: true do
      create_training_client_from_state_with_optimizer(service_client, path, opts)
    end
  end

  @doc """
  Create a sampling client from this ServiceClient.
  """
  @spec create_sampling_client(t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def create_sampling_client(service_client, opts \\ []) do
    GenServer.call(service_client, {:create_sampling_client, opts})
  end

  @doc """
  Fetch server capabilities (supported models/features) via the Service API.
  """
  @spec get_server_capabilities(t()) ::
          {:ok, Tinkex.Types.GetServerCapabilitiesResponse.t()} | {:error, term()}
  def get_server_capabilities(service_client) do
    GenServer.call(service_client, :get_server_capabilities)
  end

  @doc """
  Async helper for `get_server_capabilities/1`.
  """
  @spec get_server_capabilities_async(t()) :: Task.t()
  def get_server_capabilities_async(service_client) do
    reporter = telemetry_reporter_for(service_client)

    TelemetryCapture.async_capture reporter: reporter, fatal?: true do
      get_server_capabilities(service_client)
    end
  end

  @doc """
  Create a sampling client asynchronously.

  Returns a Task that resolves to `{:ok, pid}` or `{:error, reason}`.

  ## Examples

      task = ServiceClient.create_sampling_client_async(service_pid, base_model: "meta-llama/Llama-3.2-1B")
      {:ok, sampling_pid} = Task.await(task)
  """
  @spec create_sampling_client_async(t(), keyword()) :: Task.t()
  def create_sampling_client_async(service_client, opts \\ []) do
    reporter = telemetry_reporter_for(service_client)

    TelemetryCapture.async_capture reporter: reporter, fatal?: true do
      create_sampling_client(service_client, opts)
    end
  end

  @doc """
  Return a REST client for session and checkpoint management.
  """
  @spec create_rest_client(t()) :: {:ok, Tinkex.RestClient.t()}
  def create_rest_client(service_client) do
    GenServer.call(service_client, :create_rest_client)
  end

  @doc """
  Return the telemetry reporter pid if backend telemetry is enabled.
  """
  @spec telemetry_reporter(t()) :: {:ok, pid()} | {:error, :disabled}
  def telemetry_reporter(service_client) do
    GenServer.call(service_client, :telemetry_reporter)
  end

  @impl true
  def init(opts) do
    client_supervisor = Keyword.get(opts, :client_supervisor, :local)

    with {:ok, _} <- Application.ensure_all_started(:tinkex),
         :ok <- ensure_core_tables(),
         {:ok, client_supervisor_pid} <- ensure_client_supervisor(client_supervisor),
         :ok <- ensure_sampling_registry() do
      do_init(opts, client_supervisor_pid)
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp do_init(opts, client_supervisor) do
    config = opts[:config] || Config.new(opts)

    training_module = Keyword.get(opts, :training_client_module, Tinkex.TrainingClient)
    sampling_module = Keyword.get(opts, :sampling_client_module, Tinkex.SamplingClient)
    session_manager = Keyword.get(opts, :session_manager, SessionManager)

    case SessionManager.start_session(config, session_manager) do
      {:ok, session_id} ->
        telemetry_metadata = %{session_id: session_id}
        telemetry = init_telemetry(session_id, config, opts)

        state = %{
          session_id: session_id,
          training_client_counter: 0,
          sampling_client_counter: 0,
          config: config,
          training_client_module: training_module,
          sampling_client_module: sampling_module,
          session_manager: session_manager,
          client_supervisor: client_supervisor,
          telemetry: telemetry,
          telemetry_metadata: telemetry_metadata
        }

        put_telemetry(state.telemetry)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp ensure_client_supervisor(:local) do
    DynamicSupervisor.start_link(strategy: :one_for_one)
  end

  defp ensure_client_supervisor(pid) when is_pid(pid), do: {:ok, pid}

  defp ensure_client_supervisor(name) when is_atom(name) do
    case Process.whereis(name) do
      nil ->
        DynamicSupervisor.start_link(strategy: :one_for_one, name: name)

      pid ->
        {:ok, pid}
    end
  end

  defp ensure_sampling_registry do
    case Process.whereis(Tinkex.SamplingRegistry) do
      nil ->
        case Tinkex.SamplingRegistry.start_link(name: Tinkex.SamplingRegistry) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        :ok
    end
  end

  defp ensure_core_tables do
    ensure_table(:tinkex_sampling_clients, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    ensure_table(:tinkex_rate_limiters, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    ensure_table(:tinkex_tokenizers, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    :ok
  end

  defp ensure_table(name, options) do
    case :ets.whereis(name) do
      :undefined ->
        try do
          :ets.new(name, options)
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  @impl true
  def handle_call({:create_training_client, base_model, opts}, _from, state) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      model_seq_id = state.training_client_counter

      with {:ok, normalized_opts} <- normalize_training_opts(opts),
           child_opts <-
             normalized_opts
             |> Keyword.put(:base_model, base_model)
             |> Keyword.put(:session_id, state.session_id)
             |> Keyword.put(:config, state.config)
             |> Keyword.put(:model_seq_id, model_seq_id)
             |> Keyword.put(:client_supervisor, state.client_supervisor)
             |> Keyword.put(:telemetry, state.telemetry)
             |> Keyword.put(:telemetry_metadata, state.telemetry_metadata),
           {:ok, pid} <-
             DynamicSupervisor.start_child(
               state.client_supervisor,
               {state.training_client_module, child_opts}
             ) do
        {:reply, {:ok, pid}, %{state | training_client_counter: model_seq_id + 1}}
      else
        {:error, %Error{} = error} ->
          {:reply, {:error, error}, state}

        {:error, _} = error ->
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call({:create_training_client_from_state, path, opts}, _from, state) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      rest_client = RestClient.new(state.session_id, state.config)

      case create_training_client_from_checkpoint(rest_client, path, opts, state) do
        {:ok, training_client, new_counter} ->
          {:reply, {:ok, training_client}, %{state | training_client_counter: new_counter}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:create_sampling_client, opts}, _from, state) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      sampling_client_id = state.sampling_client_counter

      with :ok <- validate_sampling_opts(opts),
           child_opts <-
             opts
             |> Keyword.put(:session_id, state.session_id)
             |> Keyword.put(:config, state.config)
             |> Keyword.put(:sampling_client_id, sampling_client_id)
             |> Keyword.put(:telemetry, state.telemetry)
             |> Keyword.put(:telemetry_metadata, state.telemetry_metadata),
           {:ok, pid} <-
             DynamicSupervisor.start_child(
               state.client_supervisor,
               {state.sampling_client_module, child_opts}
             ) do
        {:reply, {:ok, pid}, %{state | sampling_client_counter: sampling_client_id + 1}}
      else
        {:error, %Error{} = error} ->
          {:reply, {:error, error}, state}

        {:error, _} = error ->
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call(:get_server_capabilities, _from, state) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      case Service.get_server_capabilities(
             config: state.config,
             telemetry_metadata: state.telemetry_metadata
           ) do
        {:ok, %Tinkex.Types.GetServerCapabilitiesResponse{} = resp} ->
          {:reply, {:ok, resp}, state}

        {:error, _} = error ->
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call(:create_rest_client, _from, state) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      client = Tinkex.RestClient.new(state.session_id, state.config)
      {:reply, {:ok, client}, state}
    end
  end

  @impl true
  def handle_call(:telemetry_reporter, _from, %{telemetry: nil} = state) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      {:reply, {:error, :disabled}, state}
    end
  end

  def handle_call(:telemetry_reporter, _from, %{telemetry: pid} = state) when is_pid(pid) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    TelemetryCapture.capture_exceptions reporter: state.telemetry, fatal?: true do
      {:reply, state.telemetry, state}
    end
  end

  @impl true
  def get_telemetry do
    :erlang.get({__MODULE__, :telemetry})
  end

  def get_telemetry(server) when is_pid(server) do
    GenServer.call(server, :get_telemetry)
  end

  defp telemetry_reporter_for(server) do
    case telemetry_reporter(server) do
      {:ok, pid} -> pid
      _ -> nil
    end
  catch
    _, _ -> nil
  end

  @impl true
  def terminate(_reason, %{session_id: session_id, session_manager: session_manager} = state) do
    Reporter.stop(state[:telemetry])
    SessionManager.stop_session(session_id, session_manager)
    :ok
  end

  def terminate(_reason, state) do
    Reporter.stop(state[:telemetry])
    :ok
  end

  defp create_training_client_from_checkpoint(rest_client, path, opts, state) do
    with {:ok, weights_info} <- RestClient.get_weights_info_by_tinker_path(rest_client, path),
         {:ok, training_client, new_counter} <-
           start_training_client_from_weights(weights_info, opts, state),
         {:ok, load_task} <-
           load_checkpoint(state.training_client_module, training_client, path, opts),
         {:ok, _response} <- await_load_task(load_task, opts) do
      {:ok, training_client, new_counter}
    else
      {:error, _reason} = error ->
        maybe_stop_training_client_on_error(error, opts, state, path)
        error
    end
  end

  defp maybe_stop_training_client_on_error(_error, _opts, _state, _path) do
    # Training client cleanup is handled implicitly since with-else
    # only triggers when an error occurs before training client is returned.
    :ok
  end

  defp start_training_client_from_weights(weights_info, opts, state) do
    model_seq_id = state.training_client_counter

    with {:ok, lora_config} <- validate_lora_config(lora_config_from_weights_info(weights_info)),
         child_opts <-
           opts
           |> Keyword.put(:session_id, state.session_id)
           |> Keyword.put(:config, state.config)
           |> Keyword.put(:model_seq_id, model_seq_id)
           |> Keyword.put(:base_model, weights_info.base_model)
           |> Keyword.put(:lora_config, lora_config)
           |> Keyword.put(:client_supervisor, state.client_supervisor)
           |> Keyword.put(:telemetry, state.telemetry)
           |> Keyword.put(:telemetry_metadata, state.telemetry_metadata),
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             state.client_supervisor,
             {state.training_client_module, child_opts}
           ) do
      {:ok, pid, model_seq_id + 1}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, _} = error ->
        error
    end
  end

  defp load_checkpoint(training_client_module, training_client, path, opts) do
    load_fn =
      if Keyword.get(opts, :load_optimizer, false) do
        &training_client_module.load_state_with_optimizer/3
      else
        &training_client_module.load_state/3
      end

    load_opts = Keyword.get(opts, :load_opts, [])
    load_fn.(training_client, path, load_opts)
  end

  defp await_load_task(task, opts) do
    timeout = Keyword.get(opts, :load_timeout, :infinity)

    try do
      Task.await(task, timeout)
    catch
      :exit, reason ->
        {:error, reason}
    end
  end

  defp lora_config_from_weights_info(%{lora_rank: nil}), do: %LoraConfig{}

  defp lora_config_from_weights_info(%{lora_rank: rank}) when is_integer(rank),
    do: %LoraConfig{rank: rank}

  defp normalize_training_opts(opts) do
    with {:ok, lora_config} <- build_lora_config(opts) do
      {:ok,
       opts
       |> Keyword.put(:lora_config, lora_config)
       |> Keyword.drop([:rank, :seed, :train_mlp, :train_attn, :train_unembed])}
    end
  end

  defp resolve_lora_config(opts) do
    base =
      case Keyword.get(opts, :lora_config) do
        %LoraConfig{} = config ->
          config

        map when is_map(map) ->
          defaults = Map.from_struct(%LoraConfig{})

          merged =
            Map.merge(
              defaults,
              Map.take(map, [:rank, :seed, :train_mlp, :train_attn, :train_unembed])
            )

          struct(LoraConfig, merged)

        _ ->
          %LoraConfig{}
      end

    base
    |> maybe_override(:rank, opts[:rank])
    |> maybe_override(:seed, opts[:seed])
    |> maybe_override(:train_mlp, opts[:train_mlp])
    |> maybe_override(:train_attn, opts[:train_attn])
    |> maybe_override(:train_unembed, opts[:train_unembed])
  end

  defp maybe_override(config, _field, nil), do: config
  defp maybe_override(%LoraConfig{} = config, field, value), do: Map.put(config, field, value)

  defp build_lora_config(opts) do
    opts
    |> resolve_lora_config()
    |> validate_lora_config()
  end

  defp validate_lora_config(%LoraConfig{} = config) do
    if config.train_mlp or config.train_attn or config.train_unembed do
      {:ok, config}
    else
      {:error,
       Error.new(
         :validation,
         "At least one of train_mlp, train_attn, or train_unembed must be true",
         category: :user
       )}
    end
  end

  defp validate_sampling_opts(opts) do
    case {Keyword.get(opts, :model_path), Keyword.get(opts, :base_model)} do
      {nil, nil} ->
        {:error,
         Error.new(:validation, "Either model_path or base_model must be provided",
           category: :user
         )}

      _ ->
        :ok
    end
  end

  defp init_telemetry(session_id, config, opts) do
    telemetry_opts = Keyword.get(opts, :telemetry_opts, [])

    init_opts =
      [session_id: session_id, config: config, telemetry_opts: telemetry_opts]
      |> maybe_put_enabled?(Keyword.get(opts, :telemetry_enabled?))

    case Telemetry.init(init_opts) do
      {:ok, pid} ->
        pid

      :ignore ->
        nil

      {:error, reason} ->
        Logger.debug("Telemetry disabled for session #{session_id}: #{inspect(reason)}")
        nil
    end
  end

  defp put_telemetry(nil), do: :ok

  defp put_telemetry(pid) do
    :erlang.put({__MODULE__, :telemetry}, pid)
  end

  defp maybe_put_enabled?(opts, nil), do: opts
  defp maybe_put_enabled?(opts, value), do: Keyword.put(opts, :enabled?, value)
end
