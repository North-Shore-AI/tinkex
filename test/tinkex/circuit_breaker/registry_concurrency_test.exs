defmodule Tinkex.CircuitBreaker.RegistryConcurrencyTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Foundation.CircuitBreaker.Registry

  setup do
    registry = Registry.new_registry()
    {:ok, registry: registry}
  end

  test "opens circuit under concurrent failures", %{registry: registry} do
    name = "concurrent-endpoint"
    total = 20
    gate = make_ref()
    parent = self()

    fun = fn ->
      send(parent, {:ready, self()})

      receive do
        ^gate -> :ok
      end

      {:error, :boom}
    end

    tasks =
      for _ <- 1..total do
        Task.async(fn -> Registry.call(registry, name, fun, failure_threshold: total) end)
      end

    ready_pids =
      for _ <- 1..total do
        assert_receive {:ready, pid}, 1_000
        pid
      end

    Enum.each(ready_pids, &send(&1, gate))
    Enum.each(tasks, &Task.await(&1, 2_000))

    assert Registry.state(registry, name) == :open
  end
end
