defmodule Tinkex.ServiceClient do
  @moduledoc """
  Entry point for Tinkex operations.

  Starts a session via `Tinkex.SessionManager`, tracks sequencing counters, and
  spawns Training/Sampling clients under `Tinkex.ClientSupervisor`.
  """

  use GenServer

  alias Tinkex.Config
  alias Tinkex.SessionManager

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
  Return a thin REST client representation (session + config).
  """
  @spec create_rest_client(t()) :: {:ok, map()}
  def create_rest_client(service_client) do
    GenServer.call(service_client, :create_rest_client)
  end

  @impl true
  def init(opts) do
    config = opts[:config] || Config.new(opts)

    training_module = Keyword.get(opts, :training_client_module, Tinkex.TrainingClient)
    sampling_module = Keyword.get(opts, :sampling_client_module, Tinkex.SamplingClient)
    session_manager = Keyword.get(opts, :session_manager, SessionManager)

    with {:ok, session_id} <- SessionManager.start_session(config, session_manager) do
      state = %{
        session_id: session_id,
        training_client_counter: 0,
        sampling_client_counter: 0,
        config: config,
        training_client_module: training_module,
        sampling_client_module: sampling_module,
        session_manager: session_manager
      }

      {:ok, state}
    else
      {:error, reason} ->
        {:stop, reason}
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

    case DynamicSupervisor.start_child(
           Tinkex.ClientSupervisor,
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

    case DynamicSupervisor.start_child(
           Tinkex.ClientSupervisor,
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
    {:reply, {:ok, %{session_id: state.session_id, config: state.config}}, state}
  end

  @impl true
  def terminate(_reason, %{session_id: session_id, session_manager: session_manager}) do
    SessionManager.stop_session(session_id, session_manager)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
