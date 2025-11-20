defmodule Tinkex.SamplingRegistry do
  @moduledoc """
  Registry that tracks SamplingClient processes and cleans up ETS entries on exit.
  """

  use GenServer

  @type state :: %{monitors: %{reference() => pid()}}

  @doc """
  Start the registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Register a SamplingClient process with its configuration payload.
  """
  @spec register(pid(), map()) :: :ok
  def register(pid, config) when is_pid(pid) do
    GenServer.call(__MODULE__, {:register, pid, config})
  end

  @impl true
  def init(:ok) do
    {:ok, %{monitors: %{}}}
  end

  @impl true
  def handle_call({:register, pid, config}, _from, state) do
    ref = Process.monitor(pid)
    :ets.insert(:tinkex_sampling_clients, {{:config, pid}, config})

    {:reply, :ok, %{state | monitors: Map.put(state.monitors, ref, pid)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, monitors} ->
        {:noreply, %{state | monitors: monitors}}

      {pid, monitors} ->
        :ets.delete(:tinkex_sampling_clients, {:config, pid})
        {:noreply, %{state | monitors: monitors}}
    end
  end
end
