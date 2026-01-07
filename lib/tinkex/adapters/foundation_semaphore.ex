defmodule Tinkex.Adapters.FoundationSemaphore do
  @moduledoc """
  Foundation-based semaphore adapter.
  """

  @behaviour Tinkex.Ports.Semaphore

  alias Foundation.Semaphore.Counting

  @impl true
  def acquire_blocking(registry, name, max, backoff, opts \\ []) do
    Counting.acquire_blocking(registry, name, max, backoff, opts)
  end

  @impl true
  def release(registry, name) do
    Counting.release(registry, name)
  end
end
