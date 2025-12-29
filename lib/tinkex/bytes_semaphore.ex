defmodule Tinkex.BytesSemaphore do
  @moduledoc """
  Byte-budget semaphore for rate limiting by payload size.

  Delegates to `Foundation.Semaphore.Weighted` while preserving Tinkex semantics.
  """

  alias Foundation.Semaphore.Weighted

  @type t :: pid()

  @doc """
  Start a BytesSemaphore with the given byte budget.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, 5 * 1024 * 1024)
    Weighted.start_link(max_weight: max_bytes, name: Keyword.get(opts, :name))
  end

  @doc """
  Acquire bytes from the semaphore, blocking while the budget is negative.
  """
  @spec acquire(t(), non_neg_integer()) :: :ok
  def acquire(semaphore, bytes) when is_integer(bytes) and bytes >= 0 do
    Weighted.acquire(semaphore, bytes)
  end

  @doc """
  Release bytes back to the semaphore.
  """
  @spec release(t(), non_neg_integer()) :: :ok
  def release(semaphore, bytes) when is_integer(bytes) and bytes >= 0 do
    Weighted.release(semaphore, bytes)
  end

  @doc """
  Execute `fun` while holding the requested byte budget.
  """
  @spec with_bytes(t(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_bytes(semaphore, bytes, fun) when is_function(fun, 0) do
    Weighted.with_acquire(semaphore, bytes, fun)
  end
end
