defmodule Tinkex.ServiceClient do
  @moduledoc """
  Entry point for Tinkex operations.

  Starts a session via `Tinkex.SessionManager`, tracks sequencing counters, and
  spawns Training/Sampling clients under `Tinkex.ClientSupervisor`.
  """

  use GenServer
  use Tinkex.Telemetry.Provider

  require Logger

  alias Tinkex.Config
  alias Tinkex.SessionManager
  alias Tinkex.Telemetry
  alias Tinkex.Telemetry.Reporter

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
  """
  @spec create_lora_training_client(t(), keyword()) ::
          {:ok, pid()} | {:error, term()}
  def create_lora_training_client(service_client, opts \\ []) do
    GenServer.call(service_client, {:create_training_client, opts})
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
  Create a sampling client asynchronously.

  Returns a Task that resolves to `{:ok, pid}` or `{:error, reason}`.

  ## Examples

      task = ServiceClient.create_sampling_client_async(service_pid, base_model: "meta-llama/Llama-3.2-1B")
      {:ok, sampling_pid} = Task.await(task)
  """
  @spec create_sampling_client_async(t(), keyword()) :: Task.t()
  def create_sampling_client_async(service_client, opts \\ []) do
    Task.async(fn ->
      create_sampling_client(service_client, opts)
    end)
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
  def handle_call({:create_training_client, opts}, _from, state) do
    model_seq_id = state.training_client_counter

    child_opts =
      opts
      |> Keyword.put(:session_id, state.session_id)
      |> Keyword.put(:config, state.config)
      |> Keyword.put(:model_seq_id, model_seq_id)
      |> Keyword.put(:client_supervisor, state.client_supervisor)
      |> Keyword.put(:telemetry, state.telemetry)
      |> Keyword.put(:telemetry_metadata, state.telemetry_metadata)

    case DynamicSupervisor.start_child(
           state.client_supervisor,
           {state.training_client_module, child_opts}
         ) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, %{state | training_client_counter: model_seq_id + 1}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:create_sampling_client, opts}, _from, state) do
    sampling_client_id = state.sampling_client_counter

    child_opts =
      opts
      |> Keyword.put(:session_id, state.session_id)
      |> Keyword.put(:config, state.config)
      |> Keyword.put(:sampling_client_id, sampling_client_id)
      |> Keyword.put(:telemetry, state.telemetry)
      |> Keyword.put(:telemetry_metadata, state.telemetry_metadata)

    case DynamicSupervisor.start_child(
           state.client_supervisor,
           {state.sampling_client_module, child_opts}
         ) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, %{state | sampling_client_counter: sampling_client_id + 1}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:create_rest_client, _from, state) do
    client = Tinkex.RestClient.new(state.session_id, state.config)
    {:reply, {:ok, client}, state}
  end

  @impl true
  def handle_call(:telemetry_reporter, _from, %{telemetry: nil} = state) do
    {:reply, {:error, :disabled}, state}
  end

  def handle_call(:telemetry_reporter, _from, %{telemetry: pid} = state) when is_pid(pid) do
    {:reply, {:ok, pid}, state}
  end

  @impl true
  def handle_call(:get_telemetry, _from, state) do
    {:reply, state.telemetry, state}
  end

  @impl true
  def get_telemetry do
    :erlang.get({__MODULE__, :telemetry})
  end

  def get_telemetry(server) when is_pid(server) do
    GenServer.call(server, :get_telemetry)
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
