defmodule Tinkex.RetrySemaphoreTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.RetrySemaphore

  test "reuses semaphore for same max_connections" do
    sem1 = RetrySemaphore.get_semaphore(2)
    sem2 = RetrySemaphore.get_semaphore(2)

    assert sem1 == sem2
  end

  test "limits concurrent executions" do
    test_pid = self()
    counter = :atomics.new(1, [])
    max_seen = :atomics.new(1, [])

    fun = fn ->
      # Increment counter and track max
      current = :atomics.add_get(counter, 1, 1)
      max_current = :atomics.get(max_seen, 1)

      if current > max_current do
        :atomics.put(max_seen, 1, current)
      end

      # Signal test process that we're in the critical section
      send(test_pid, {:entered, self()})

      # Wait for permission to proceed
      receive do
        :proceed -> :ok
      end

      :atomics.add_get(counter, 1, -1)
      :ok
    end

    tasks =
      for _ <- 1..3 do
        Task.async(fn -> RetrySemaphore.with_semaphore(1, fun) end)
      end

    # Wait for first task to enter critical section
    assert_receive {:entered, pid1}, 1_000

    # Give a moment for other tasks to attempt entry (they should be blocked)
    # Use receive with timeout instead of sleep
    receive do
      {:entered, _pid2} -> flunk("Second task should not enter while first holds semaphore")
    after
      100 -> :ok
    end

    # Allow first task to complete
    send(pid1, :proceed)

    # Wait for second task to enter
    assert_receive {:entered, pid2}, 1_000

    # Verify third task is still blocked
    receive do
      {:entered, _pid3} -> flunk("Third task should not enter while second holds semaphore")
    after
      100 -> :ok
    end

    # Allow second task to complete
    send(pid2, :proceed)

    # Wait for third task to enter
    assert_receive {:entered, pid3}, 1_000

    # Allow third task to complete
    send(pid3, :proceed)

    # Wait for all tasks to complete
    Enum.each(tasks, &Task.await(&1, 2_000))

    # Verify max concurrent was never more than 1
    assert :atomics.get(max_seen, 1) <= 1
  end
end
