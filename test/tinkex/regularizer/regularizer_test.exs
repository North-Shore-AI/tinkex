defmodule Tinkex.RegularizerTest do
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer

  # Test module implementing the behaviour
  defmodule TestL1Regularizer do
    @behaviour Tinkex.Regularizer

    @impl true
    def compute(_data, logprobs, _opts) do
      l1 = Nx.sum(Nx.abs(logprobs))
      {l1, %{"l1_value" => Nx.to_number(l1)}}
    end

    @impl true
    def name, do: "test_l1"
  end

  defmodule TestRegWithoutName do
    @behaviour Tinkex.Regularizer

    @impl true
    def compute(_data, logprobs, _opts) do
      {Nx.mean(logprobs), %{}}
    end
  end

  describe "execute/4 with anonymous functions" do
    test "executes arity-2 function" do
      fun = fn _data, logprobs -> {Nx.sum(logprobs), %{"sum" => true}} end
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {loss, metrics} = Regularizer.execute(fun, data, logprobs)

      assert Nx.to_number(loss) == 6.0
      assert metrics == %{"sum" => true}
    end

    test "executes arity-3 function with opts" do
      fun = fn _data, logprobs, opts ->
        multiplier = Keyword.get(opts, :multiplier, 1.0)
        {Nx.multiply(Nx.sum(logprobs), multiplier), %{}}
      end

      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {loss, _} = Regularizer.execute(fun, data, logprobs, multiplier: 2.0)

      assert Nx.to_number(loss) == 12.0
    end
  end

  describe "execute/4 with behaviour modules" do
    test "executes module implementing behaviour" do
      data = []
      logprobs = Nx.tensor([-1.0, 2.0, -3.0])

      {loss, metrics} = Regularizer.execute(TestL1Regularizer, data, logprobs)

      assert Nx.to_number(loss) == 6.0
      assert metrics["l1_value"] == 6.0
    end

    test "executes module without optional name callback" do
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      {loss, metrics} = Regularizer.execute(TestRegWithoutName, data, logprobs)

      assert Nx.to_number(loss) == 2.0
      assert metrics == %{}
    end
  end

  describe "behaviour callbacks" do
    test "TestL1Regularizer.name returns expected name" do
      assert TestL1Regularizer.name() == "test_l1"
    end

    test "TestRegWithoutName does not need name callback" do
      # This should compile without name callback since it's optional
      {loss, _} = TestRegWithoutName.compute([], Nx.tensor([1.0]), [])
      assert Nx.to_number(loss) == 1.0
    end
  end
end
