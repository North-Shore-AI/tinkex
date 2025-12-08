defmodule Tinkex.RetrySemaphore do
  @moduledoc """
  Blocking semaphore wrapper used to cap concurrent sampling retry executions.

  Uses the `semaphore` library's global ETS-backed semaphore. Each distinct
  `max_connections` value maps to its own semaphore name.
  """

  use GenServer

  @type semaphore_name :: {:tinkex_retry, term(), pos_integer()}

  @doc """
  Start the semaphore supervisor and underlying semaphore server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Return the semaphore name for a given max_connections.
  """
  @spec get_semaphore(pos_integer()) :: semaphore_name()
  def get_semaphore(max_connections) when is_integer(max_connections) and max_connections > 0 do
    get_semaphore({:default, max_connections}, max_connections)
  end

  @doc """
  Return the semaphore name for a given key and max_connections.
  """
  @spec get_semaphore(term(), pos_integer()) :: semaphore_name()
  def get_semaphore(key, max_connections)
      when is_integer(max_connections) and max_connections > 0 do
    ensure_started()
    {:tinkex_retry, key, max_connections}
  end

  @doc """
  Execute `fun` while holding the semaphore for `max_connections`.
  Blocks until capacity is available.
  """
  @spec with_semaphore(pos_integer(), (-> term())) :: term()
  def with_semaphore(max_connections, fun) when is_function(fun, 0) do
    name = get_semaphore(max_connections)
    acquire_blocking(name, max_connections)

    try do
      fun.()
    after
      Semaphore.release(name)
    end
  end

  @doc """
  Execute `fun` while holding a keyed semaphore. Callers can provide a unique
  key to isolate capacity between clients even when max_connections matches.
  """
  @spec with_semaphore(term(), pos_integer(), (-> term())) :: term()
  def with_semaphore(key, max_connections, fun) when is_function(fun, 0) do
    name = get_semaphore(key, max_connections)
    acquire_blocking(name, max_connections)

    try do
      fun.()
    after
      Semaphore.release(name)
    end
  end

  @impl true
  def init(:ok) do
    ensure_semaphore_server()
    {:ok, %{}}
  end

  defp acquire_blocking(name, max_connections) do
    case Semaphore.acquire(name, max_connections) do
      true ->
        :ok

      false ->
        Process.sleep(2)
        acquire_blocking(name, max_connections)
    end
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        {:ok, _pid} = start_link()
        :ok

      _pid ->
        :ok
    end
  end

  defp ensure_semaphore_server do
    case Process.whereis(Semaphore) do
      nil ->
        {:ok, _pid} = Semaphore.start_link()
        :ok

      _pid ->
        :ok
    end
  end
end
