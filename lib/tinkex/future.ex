defmodule Tinkex.Future do
  @moduledoc false

  alias Tinkex.Domain.Futures.Poller

  def poll(request_or_payload, opts \\ []), do: Poller.poll(request_or_payload, opts)
  def await(task, timeout \\ :infinity), do: Poller.await(task, timeout)
  def await_many(tasks, timeout \\ :infinity), do: Poller.await_many(tasks, timeout)
end
