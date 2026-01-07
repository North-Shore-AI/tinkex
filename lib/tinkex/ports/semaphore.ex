defmodule Tinkex.Ports.Semaphore do
  @moduledoc """
  Port for semaphore operations.
  """

  @callback acquire_blocking(term(), term(), pos_integer(), term(), keyword()) :: :ok
  @callback release(term(), term()) :: :ok
end
