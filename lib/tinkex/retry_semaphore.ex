defmodule Tinkex.RetrySemaphore do
  @moduledoc """
  Blocking semaphore wrapper used to cap concurrent sampling retry executions.

  Uses the `semaphore` library's global ETS-backed semaphore. Each distinct
  `max_connections` value maps to its own semaphore name.
  """

  use GenServer

  @type semaphore_name :: {:tinkex_retry, term(), pos_integer()}
  @default_backoff_base_ms 2
  @default_backoff_max_ms 50
  @default_backoff_jitter 0.25
  @max_backoff_exponent 20

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
    with_semaphore(max_connections, [], fun)
  end

  @spec with_semaphore(pos_integer(), keyword(), (-> term())) :: term()
  def with_semaphore(max_connections, opts, fun)
      when is_integer(max_connections) and max_connections > 0 and is_list(opts) and
             is_function(fun, 0) do
    name = get_semaphore(max_connections)
    backoff = build_backoff(opts)
    acquire_blocking(name, max_connections, backoff)

    try do
      fun.()
    after
      backoff.release_fun.(name)
    end
  end

  @doc """
  Execute `fun` while holding a keyed semaphore. Callers can provide a unique
  key to isolate capacity between clients even when max_connections matches.
  """
  @spec with_semaphore(term(), pos_integer(), (-> term())) :: term()
  def with_semaphore(key, max_connections, fun)
      when is_integer(max_connections) and max_connections > 0 and is_function(fun, 0) do
    with_semaphore(key, max_connections, [], fun)
  end

  @spec with_semaphore(term(), pos_integer(), keyword(), (-> term())) :: term()
  def with_semaphore(key, max_connections, opts, fun)
      when is_integer(max_connections) and max_connections > 0 and is_list(opts) and
             is_function(fun, 0) do
    name = get_semaphore(key, max_connections)
    backoff = build_backoff(opts)
    acquire_blocking(name, max_connections, backoff)

    try do
      fun.()
    after
      backoff.release_fun.(name)
    end
  end

  @impl true
  def init(:ok) do
    ensure_semaphore_server()
    {:ok, %{}}
  end

  defp acquire_blocking(name, max_connections, backoff, attempt \\ 0) do
    case backoff.acquire_fun.(name, max_connections) do
      true ->
        :ok

      false ->
        backoff.sleep_fun.(backoff_delay(backoff, attempt))
        acquire_blocking(name, max_connections, backoff, attempt + 1)
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

  defp build_backoff(opts) when is_list(opts) do
    backoff =
      %{
        base_ms: @default_backoff_base_ms,
        max_ms: @default_backoff_max_ms,
        jitter: @default_backoff_jitter,
        sleep_fun: &Process.sleep/1,
        rand_fun: &:rand.uniform/0,
        acquire_fun: &Semaphore.acquire/2,
        release_fun: &Semaphore.release/1
      }
      |> Map.merge(Map.new(opts[:backoff] || []))

    %{
      base_ms: positive_or_default(backoff.base_ms, @default_backoff_base_ms),
      max_ms:
        positive_or_default(backoff.max_ms, @default_backoff_max_ms)
        |> max(positive_or_default(backoff.base_ms, @default_backoff_base_ms)),
      jitter: normalize_jitter(backoff.jitter),
      sleep_fun: normalize_sleep_fun(backoff.sleep_fun),
      rand_fun: normalize_rand_fun(backoff.rand_fun),
      acquire_fun: normalize_acquire_fun(backoff.acquire_fun),
      release_fun: normalize_release_fun(backoff.release_fun)
    }
  end

  defp backoff_delay(backoff, attempt) when is_integer(attempt) and attempt >= 0 do
    capped_attempt = min(attempt, @max_backoff_exponent)
    base_delay = trunc(backoff.base_ms * :math.pow(2, capped_attempt))
    capped_delay = min(base_delay, backoff.max_ms)
    apply_jitter(capped_delay, backoff.jitter, backoff.rand_fun)
  end

  defp backoff_delay(backoff, _attempt), do: backoff.base_ms

  defp apply_jitter(delay, jitter, _rand_fun) when jitter <= 0, do: delay

  defp apply_jitter(delay, jitter, rand_fun) do
    factor = 1 - jitter + rand_fun.() * jitter
    max(trunc(delay * factor), 0)
  end

  defp positive_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or_default(_value, default), do: default

  defp normalize_jitter(value) when is_float(value) and value >= 0 and value <= 1, do: value
  defp normalize_jitter(value) when is_integer(value) and value in [0, 1], do: value * 1.0
  defp normalize_jitter(_value), do: @default_backoff_jitter

  defp normalize_sleep_fun(fun) when is_function(fun, 1), do: fun
  defp normalize_sleep_fun(_fun), do: &Process.sleep/1

  defp normalize_rand_fun(fun) when is_function(fun, 0), do: fun
  defp normalize_rand_fun(_fun), do: &:rand.uniform/0

  defp normalize_acquire_fun(fun) when is_function(fun, 2), do: fun
  defp normalize_acquire_fun(_fun), do: &Semaphore.acquire/2

  defp normalize_release_fun(fun) when is_function(fun, 1), do: fun
  defp normalize_release_fun(_fun), do: &Semaphore.release/1
end
