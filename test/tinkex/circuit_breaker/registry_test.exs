defmodule Tinkex.CircuitBreaker.RegistryTest do
  @moduledoc """
  Tests for the circuit breaker registry.
  """
  use ExUnit.Case, async: true

  alias Tinkex.CircuitBreaker.Registry

  setup do
    # Ensure registry is initialized
    Registry.init()

    # Clean up any existing circuit breakers
    for {name, _state} <- Registry.list() do
      Registry.delete(name)
    end

    :ok
  end

  describe "init/0" do
    test "creates ETS table" do
      # Already initialized in setup
      assert :ets.whereis(:tinkex_circuit_breakers) != :undefined
    end

    test "is idempotent" do
      assert :ok == Registry.init()
      assert :ok == Registry.init()
    end
  end

  describe "call/3" do
    test "executes function and returns result" do
      result = Registry.call("test-endpoint", fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
    end

    test "creates circuit breaker if not exists" do
      Registry.delete("new-endpoint")
      _result = Registry.call("new-endpoint", fn -> {:ok, "test"} end)

      assert Registry.state("new-endpoint") == :closed
    end

    test "records failures and opens circuit" do
      for _i <- 1..5 do
        Registry.call("fail-endpoint", fn -> {:error, "failed"} end, failure_threshold: 5)
      end

      assert Registry.state("fail-endpoint") == :open
    end

    test "returns circuit_open when circuit is open" do
      # Trip the circuit
      for _i <- 1..2 do
        Registry.call("open-endpoint", fn -> {:error, "failed"} end, failure_threshold: 2)
      end

      result = Registry.call("open-endpoint", fn -> {:ok, "should not run"} end)
      assert result == {:error, :circuit_open}
    end
  end

  describe "state/1" do
    test "returns :closed for non-existent circuit" do
      assert Registry.state("nonexistent") == :closed
    end

    test "returns current state" do
      Registry.call("state-test", fn -> {:ok, "test"} end)
      assert Registry.state("state-test") == :closed
    end
  end

  describe "reset/1" do
    test "resets circuit to closed" do
      # Trip the circuit
      for _i <- 1..2 do
        Registry.call("reset-test", fn -> {:error, "failed"} end, failure_threshold: 2)
      end

      assert Registry.state("reset-test") == :open

      Registry.reset("reset-test")
      assert Registry.state("reset-test") == :closed
    end

    test "is safe for non-existent circuit" do
      assert :ok == Registry.reset("nonexistent")
    end
  end

  describe "delete/1" do
    test "removes circuit from registry" do
      Registry.call("delete-test", fn -> {:ok, "test"} end)
      assert Registry.state("delete-test") == :closed

      Registry.delete("delete-test")

      # Should return :closed for non-existent (default)
      assert Registry.state("delete-test") == :closed
    end
  end

  describe "list/0" do
    test "returns all circuits with states" do
      Registry.call("list-a", fn -> {:ok, "a"} end)
      Registry.call("list-b", fn -> {:ok, "b"} end)

      circuits = Registry.list()

      assert {"list-a", :closed} in circuits
      assert {"list-b", :closed} in circuits
    end
  end
end
