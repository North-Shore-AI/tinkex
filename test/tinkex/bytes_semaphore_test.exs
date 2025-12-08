defmodule Tinkex.BytesSemaphoreTest do
  use ExUnit.Case, async: true

  alias Tinkex.BytesSemaphore

  test "allows acquisition up to budget and blocks when negative" do
    {:ok, sem} = BytesSemaphore.start_link(max_bytes: 1_000)

    task1 = Task.async(fn -> BytesSemaphore.acquire(sem, 500) end)
    assert Task.await(task1) == :ok

    task2 = Task.async(fn -> BytesSemaphore.acquire(sem, 600) end)
    assert Task.await(task2) == :ok

    task3 = Task.async(fn -> BytesSemaphore.acquire(sem, 100) end)
    refute Task.yield(task3, 50)

    BytesSemaphore.release(sem, 500)

    assert Task.await(task3) == :ok
  end

  test "with_bytes releases on normal return" do
    {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

    assert :done == BytesSemaphore.with_bytes(sem, 50, fn -> :done end)

    # Budget should be restored
    assert :ok == BytesSemaphore.acquire(sem, 100)
  end

  test "with_bytes releases on exception" do
    {:ok, sem} = BytesSemaphore.start_link(max_bytes: 100)

    assert_raise RuntimeError, fn ->
      BytesSemaphore.with_bytes(sem, 50, fn -> raise "oops" end)
    end

    assert :ok == BytesSemaphore.acquire(sem, 100)
  end
end
