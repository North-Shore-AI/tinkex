defmodule Tinkex.RetrySemaphoreTest do
  use ExUnit.Case, async: true

  alias Tinkex.RetrySemaphore

  test "reuses semaphore for same max_connections" do
    sem1 = RetrySemaphore.get_semaphore(2)
    sem2 = RetrySemaphore.get_semaphore(2)

    assert sem1 == sem2
  end

  test "limits concurrent executions" do
    counter = :atomics.new(1, [])
    max_seen = :atomics.new(1, [])

    fun = fn ->
      current = :atomics.add_get(counter, 1, 1)
      max_current = :atomics.get(max_seen, 1)

      if current > max_current do
        :atomics.put(max_seen, 1, current)
      end

      Process.sleep(50)
      :atomics.add_get(counter, 1, -1)
      :ok
    end

    tasks =
      for _ <- 1..3 do
        Task.async(fn -> RetrySemaphore.with_semaphore(1, fun) end)
      end

    Enum.each(tasks, &Task.await(&1, 2_000))

    assert :atomics.get(max_seen, 1) <= 1
  end
end
