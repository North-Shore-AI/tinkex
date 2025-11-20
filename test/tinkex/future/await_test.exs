defmodule Tinkex.Future.AwaitTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  @moduletag capture_log: true

  alias Tinkex.Error
  alias Tinkex.Future

  setup do
    %{task_supervisor: start_supervised!(Task.Supervisor)}
  end

  describe "await/2" do
    test "returns the task result on success", %{task_supervisor: task_supervisor} do
      task = Task.Supervisor.async_nolink(task_supervisor, fn -> {:ok, :result} end)
      assert Future.await(task, 1_000) == {:ok, :result}
    end

    test "converts Task timeouts into api_timeout errors", %{task_supervisor: task_supervisor} do
      task = Task.Supervisor.async_nolink(task_supervisor, fn -> Process.sleep(:infinity) end)

      assert {:error, %Error{type: :api_timeout}} = Future.await(task, 10)

      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "await_many/2" do
    test "preserves order and returns each task result", %{task_supervisor: task_supervisor} do
      slow =
        Task.Supervisor.async_nolink(task_supervisor, fn ->
          Process.sleep(20)
          {:ok, :slow}
        end)

      fast = Task.Supervisor.async_nolink(task_supervisor, fn -> {:ok, :fast} end)

      assert [{:ok, :slow}, {:ok, :fast}] = Future.await_many([slow, fast], 1_000)
    end

    test "returns errors instead of raising when tasks exit", %{task_supervisor: task_supervisor} do
      success = Task.Supervisor.async_nolink(task_supervisor, fn -> {:ok, :value} end)
      crashing = Task.Supervisor.async_nolink(task_supervisor, fn -> raise "boom" end)
      stalled = Task.Supervisor.async_nolink(task_supervisor, fn -> Process.sleep(:infinity) end)

      results = Future.await_many([success, crashing, stalled], 10)

      assert match?({:ok, :value}, Enum.at(results, 0))
      assert match?({:error, %Error{type: :api_timeout}}, Enum.at(results, 1))
      assert match?({:error, %Error{type: :api_timeout}}, Enum.at(results, 2))

      Task.shutdown(stalled, :brutal_kill)
    end
  end
end
