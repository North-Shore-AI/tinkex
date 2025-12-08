defmodule Tinkex.TestSupport.Recovery.ServiceStub do
  @default_state %{test_pid: nil, failures: 0}

  def set_test_pid(pid, service_pid \\ :default),
    do: update_state(service_pid, &Map.put(&1, :test_pid, pid))

  def set_failures(count, service_pid \\ :default),
    do: update_state(service_pid, &Map.put(&1, :failures, count))

  def clear(service_pid \\ :default) do
    :persistent_term.erase({__MODULE__, service_pid})
    # Clear legacy storage if still present so we do not leak across test runs.
    :persistent_term.erase({__MODULE__, :state})
  end

  def create_training_client_from_state_with_optimizer(service_pid, path, opts) do
    notify(service_pid, {:client_created, service_pid, path, opts})
    {:ok, :new_training_client}
  end

  def create_training_client_from_state(service_pid, path, opts) do
    %{failures: remaining} = get_state(service_pid)

    if remaining > 0 do
      update_state(service_pid, &Map.put(&1, :failures, remaining - 1))
      notify(service_pid, {:attempt, remaining})
      {:error, :not_ready}
    else
      notify(service_pid, {:client_created, service_pid, path, opts})
      {:ok, :new_training_client}
    end
  end

  defp get_state(service_pid) do
    :persistent_term.get({__MODULE__, service_pid}, @default_state)
  end

  defp update_state(service_pid, fun) do
    new_state = fun.(get_state(service_pid))
    :persistent_term.put({__MODULE__, service_pid}, new_state)
    new_state
  end

  defp notify(service_pid, message) do
    %{test_pid: test_pid} = get_state(service_pid)
    if test_pid, do: send(test_pid, message)
  end
end
