defmodule Tinkex.CircuitBreaker.RegistryTest do
  @moduledoc """
  Tests for the circuit breaker registry.
  """
  use ExUnit.Case, async: true

  alias Foundation.CircuitBreaker.Registry

  setup do
    registry = Registry.new_registry()
    {:ok, registry: registry}
  end

  describe "call/3" do
    test "executes function and returns result", %{registry: registry} do
      result = Registry.call(registry, "test-endpoint", fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
    end

    test "creates circuit breaker if not exists", %{registry: registry} do
      Registry.delete(registry, "new-endpoint")
      _result = Registry.call(registry, "new-endpoint", fn -> {:ok, "test"} end)

      assert Registry.state(registry, "new-endpoint") == :closed
    end

    test "records failures and opens circuit", %{registry: registry} do
      for _i <- 1..5 do
        Registry.call(registry, "fail-endpoint", fn -> {:error, "failed"} end,
          failure_threshold: 5
        )
      end

      assert Registry.state(registry, "fail-endpoint") == :open
    end

    test "returns circuit_open when circuit is open", %{registry: registry} do
      # Trip the circuit
      for _i <- 1..2 do
        Registry.call(registry, "open-endpoint", fn -> {:error, "failed"} end,
          failure_threshold: 2
        )
      end

      result = Registry.call(registry, "open-endpoint", fn -> {:ok, "should not run"} end)
      assert result == {:error, :circuit_open}
    end
  end

  describe "state/1" do
    test "returns :closed for non-existent circuit", %{registry: registry} do
      assert Registry.state(registry, "nonexistent") == :closed
    end

    test "returns current state", %{registry: registry} do
      Registry.call(registry, "state-test", fn -> {:ok, "test"} end)
      assert Registry.state(registry, "state-test") == :closed
    end
  end

  describe "reset/1" do
    test "resets circuit to closed", %{registry: registry} do
      # Trip the circuit
      for _i <- 1..2 do
        Registry.call(registry, "reset-test", fn -> {:error, "failed"} end, failure_threshold: 2)
      end

      assert Registry.state(registry, "reset-test") == :open

      Registry.reset(registry, "reset-test")
      assert Registry.state(registry, "reset-test") == :closed
    end

    test "is safe for non-existent circuit", %{registry: registry} do
      assert :ok == Registry.reset(registry, "nonexistent")
    end
  end

  describe "delete/1" do
    test "removes circuit from registry", %{registry: registry} do
      Registry.call(registry, "delete-test", fn -> {:ok, "test"} end)
      assert Registry.state(registry, "delete-test") == :closed

      Registry.delete(registry, "delete-test")

      # Should return :closed for non-existent (default)
      assert Registry.state(registry, "delete-test") == :closed
    end
  end

  describe "list/0" do
    test "returns all circuits with states", %{registry: registry} do
      Registry.call(registry, "list-a", fn -> {:ok, "a"} end)
      Registry.call(registry, "list-b", fn -> {:ok, "b"} end)

      circuits = Registry.list(registry)

      assert {"list-a", :closed} in circuits
      assert {"list-b", :closed} in circuits
    end
  end
end
