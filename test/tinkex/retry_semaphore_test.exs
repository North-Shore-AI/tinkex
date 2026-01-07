defmodule Tinkex.RetrySemaphoreTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Foundation.Backoff
  alias Foundation.Semaphore.Counting, as: CountingSemaphore

  test "enforces capacity per name" do
    registry = CountingSemaphore.new_registry()
    name = {:retry, self()}

    assert CountingSemaphore.acquire(registry, name, 2)
    assert CountingSemaphore.acquire(registry, name, 2)
    refute CountingSemaphore.acquire(registry, name, 2)

    assert CountingSemaphore.count(registry, name) == 2

    CountingSemaphore.release(registry, name)
    CountingSemaphore.release(registry, name)

    assert CountingSemaphore.count(registry, name) == 0
  end

  test "limits concurrent executions" do
    test_pid = self()
    counter = :atomics.new(1, [])
    max_seen = :atomics.new(1, [])
    registry = CountingSemaphore.new_registry()
    name = {:retry, test_pid}

    backoff =
      Backoff.Policy.new(
        strategy: :constant,
        base_ms: 1,
        max_ms: 1,
        jitter_strategy: :none
      )

    sleep_fun = fn _ms ->
      send(test_pid, {:blocked, self()})

      receive do
        :retry -> :ok
      end
    end

    fun = fn ->
      :ok =
        CountingSemaphore.acquire_blocking(
          registry,
          name,
          1,
          backoff,
          sleep_fun: sleep_fun
        )

      try do
        current = :atomics.add_get(counter, 1, 1)
        max_current = :atomics.get(max_seen, 1)

        if current > max_current do
          :atomics.put(max_seen, 1, current)
        end

        send(test_pid, {:entered, self()})

        receive do
          :proceed -> :ok
        end
      after
        :atomics.add_get(counter, 1, -1)
        CountingSemaphore.release(registry, name)
        send(test_pid, {:released, self()})
      end
    end

    tasks =
      for _ <- 1..3 do
        Task.async(fun)
      end

    assert_receive {:entered, pid1}, 1_000

    blocked =
      for _ <- 1..2 do
        assert_receive {:blocked, pid}, 1_000
        pid
      end

    send(pid1, :proceed)
    assert_receive {:released, ^pid1}, 1_000

    [pid2, pid3] = blocked
    send(pid2, :retry)
    assert_receive {:entered, ^pid2}, 1_000
    send(pid2, :proceed)
    assert_receive {:released, ^pid2}, 1_000

    send(pid3, :retry)
    assert_receive {:entered, ^pid3}, 1_000
    send(pid3, :proceed)
    assert_receive {:released, ^pid3}, 1_000

    Enum.each(tasks, &Task.await(&1, 2_000))

    assert :atomics.get(max_seen, 1) <= 1
  end

  test "separates capacity by semaphore key" do
    parent = self()
    registry = CountingSemaphore.new_registry()

    backoff =
      Backoff.Policy.new(
        strategy: :constant,
        base_ms: 1,
        max_ms: 1,
        jitter_strategy: :none
      )

    fun = fn key ->
      :ok =
        CountingSemaphore.acquire_blocking(
          registry,
          key,
          1,
          backoff,
          sleep_fun: fn _ -> send(parent, {:blocked, key}) end
        )

      try do
        send(parent, {:entered, key, self()})

        receive do
          :proceed -> :ok
        end
      after
        CountingSemaphore.release(registry, key)
      end
    end

    t1 = Task.async(fn -> fun.({:client, 1}) end)
    t2 = Task.async(fn -> fun.({:client, 2}) end)

    assert_receive {:entered, {:client, 1}, pid1}, 500
    assert_receive {:entered, {:client, 2}, pid2}, 500

    send(pid1, :proceed)
    send(pid2, :proceed)

    Task.await(t1, 1_000)
    Task.await(t2, 1_000)
  end

  test "backs off with exponential delay when busy" do
    parent = self()
    registry = CountingSemaphore.new_registry()
    name = {:retry, parent}

    assert CountingSemaphore.acquire(registry, name, 1)

    backoff =
      Backoff.Policy.new(
        strategy: :exponential,
        base_ms: 5,
        max_ms: 20,
        jitter_strategy: :none
      )

    sleep_fun = fn ms ->
      send(parent, {:slept, ms, self()})

      receive do
        :continue -> :ok
      end
    end

    task =
      Task.async(fn ->
        :ok =
          CountingSemaphore.acquire_blocking(
            registry,
            name,
            1,
            backoff,
            sleep_fun: sleep_fun
          )

        send(parent, {:acquired, self()})
        CountingSemaphore.release(registry, name)
      end)

    assert_receive {:slept, 5, pid}, 1_000
    send(pid, :continue)

    assert_receive {:slept, 10, ^pid}, 1_000
    send(pid, :continue)

    assert_receive {:slept, 20, ^pid}, 1_000
    CountingSemaphore.release(registry, name)
    send(pid, :continue)

    assert_receive {:acquired, ^pid}, 1_000
    refute_receive {:slept, _, _}, 50

    Task.await(task, 1_000)
  end
end
