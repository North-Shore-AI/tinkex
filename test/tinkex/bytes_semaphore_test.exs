defmodule Tinkex.BytesSemaphoreTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Foundation.Semaphore.Weighted, as: WeightedSemaphore

  test "allows acquisition up to budget and blocks when negative" do
    {:ok, sem} = WeightedSemaphore.start_link(max_weight: 1_000)

    task1 = Task.async(fn -> WeightedSemaphore.acquire(sem, 500) end)
    assert Task.await(task1) == :ok

    task2 = Task.async(fn -> WeightedSemaphore.acquire(sem, 600) end)
    assert Task.await(task2) == :ok

    task3 = Task.async(fn -> WeightedSemaphore.acquire(sem, 100) end)
    refute Task.yield(task3, 50)

    WeightedSemaphore.release(sem, 500)

    assert Task.await(task3) == :ok
  end

  test "with_acquire releases on normal return" do
    {:ok, sem} = WeightedSemaphore.start_link(max_weight: 100)

    assert :done == WeightedSemaphore.with_acquire(sem, 50, fn -> :done end)

    # Budget should be restored
    assert :ok == WeightedSemaphore.acquire(sem, 100)
  end

  test "with_acquire releases on exception" do
    {:ok, sem} = WeightedSemaphore.start_link(max_weight: 100)

    assert_raise RuntimeError, fn ->
      WeightedSemaphore.with_acquire(sem, 50, fn -> raise "oops" end)
    end

    assert :ok == WeightedSemaphore.acquire(sem, 100)
  end
end
