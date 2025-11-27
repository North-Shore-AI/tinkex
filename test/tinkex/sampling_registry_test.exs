defmodule Tinkex.SamplingRegistryTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.SamplingRegistry

  setup do
    {:ok, _} = Application.ensure_all_started(:tinkex)
    :ok
  end

  test "registers ETS entry and cleans up on process exit" do
    {:ok, pid} = Task.start(fn -> receive do: (:stop -> :ok) end)
    config = %{sampling_session_id: "session-1"}

    on_exit(fn -> :ets.delete(:tinkex_sampling_clients, {:config, pid}) end)

    assert :ok = SamplingRegistry.register(pid, config)
    assert [{_, ^config}] = :ets.lookup(:tinkex_sampling_clients, {:config, pid})

    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)
    assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}

    wait_for_cleanup({:config, pid})
  end

  test "handles multiple registrations independently" do
    {:ok, pid1} = Task.start(fn -> receive do: (:stop -> :ok) end)
    {:ok, pid2} = Task.start(fn -> receive do: (:stop -> :ok) end)

    config1 = %{sampling_session_id: "session-1"}
    config2 = %{sampling_session_id: "session-2"}

    on_exit(fn ->
      Enum.each([pid1, pid2], fn pid ->
        :ets.delete(:tinkex_sampling_clients, {:config, pid})
      end)
    end)

    :ok = SamplingRegistry.register(pid1, config1)
    :ok = SamplingRegistry.register(pid2, config2)

    assert [{_, ^config1}] = :ets.lookup(:tinkex_sampling_clients, {:config, pid1})
    assert [{_, ^config2}] = :ets.lookup(:tinkex_sampling_clients, {:config, pid2})

    ref1 = Process.monitor(pid1)
    Process.exit(pid1, :shutdown)
    assert_receive {:DOWN, ^ref1, :process, ^pid1, :shutdown}

    wait_for_cleanup({:config, pid1})
    assert [{_, ^config2}] = :ets.lookup(:tinkex_sampling_clients, {:config, pid2})

    ref2 = Process.monitor(pid2)
    Process.exit(pid2, :shutdown)
    assert_receive {:DOWN, ^ref2, :process, ^pid2, :shutdown}

    wait_for_cleanup({:config, pid2})
  end

  defp wait_for_cleanup(key, timeout \\ 1000) do
    wait_for_cleanup_until(key, System.monotonic_time(:millisecond) + timeout)
  end

  defp wait_for_cleanup_until(key, deadline) do
    case :ets.lookup(:tinkex_sampling_clients, key) do
      [] ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          receive do
          after
            1 -> wait_for_cleanup_until(key, deadline)
          end
        else
          flunk("ETS entry #{inspect(key)} was not cleaned up within timeout")
        end
    end
  end
end
