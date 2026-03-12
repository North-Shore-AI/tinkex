defmodule Tinkex.CircuitBreaker.RegistryOwner do
  @moduledoc false

  use GenServer

  @table_name :tinkex_circuit_breakers

  @spec ensure_started() :: :ok
  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, pid} ->
            Process.unlink(pid)
            :ok

          {:error, {:already_started, _pid}} ->
            :ok
        end

      _pid ->
        :ok
    end
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  rescue
    ArgumentError ->
      {:ok, %{}}
  end
end
