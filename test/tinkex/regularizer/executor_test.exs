defmodule Tinkex.Regularizer.ExecutorTest do
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer.Executor
  alias Tinkex.Types.{RegularizerSpec, RegularizerOutput}

  describe "execute_all/4 with empty list" do
    test "returns empty list for empty regularizers" do
      {:ok, results} = Executor.execute_all([], [], Nx.tensor([1.0]), [])
      assert results == []
    end
  end

  describe "execute_all/4 sequential execution" do
    test "executes single regularizer" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _data, logprobs -> {Nx.sum(logprobs), %{"sum" => true}} end,
          weight: 0.1,
          name: "sum_reg"
        }
      ]

      {:ok, results} =
        Executor.execute_all(regularizers, [], Nx.tensor([1.0, 2.0, 3.0]), parallel: false)

      assert length(results) == 1
      [output] = results
      assert output.name == "sum_reg"
      assert output.value == 6.0
      assert output.weight == 0.1
      assert_in_delta output.contribution, 0.6, 0.001
      assert output.custom == %{"sum" => true}
    end

    test "executes multiple regularizers in order" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(10.0), %{}} end,
          weight: 0.1,
          name: "reg_a"
        },
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(20.0), %{}} end,
          weight: 0.5,
          name: "reg_b"
        }
      ]

      {:ok, results} =
        Executor.execute_all(regularizers, [], Nx.tensor([1.0]), parallel: false)

      assert length(results) == 2
      assert Enum.map(results, & &1.name) == ["reg_a", "reg_b"]
    end
  end

  describe "execute_all/4 parallel execution" do
    test "executes regularizers in parallel" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(10.0), %{}} end,
          weight: 0.1,
          name: "reg_a"
        },
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(20.0), %{}} end,
          weight: 0.5,
          name: "reg_b"
        }
      ]

      {:ok, results} =
        Executor.execute_all(regularizers, [], Nx.tensor([1.0]), parallel: true)

      assert length(results) == 2
      names = Enum.map(results, & &1.name)
      assert "reg_a" in names
      assert "reg_b" in names
    end

    test "parallel is default mode" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(5.0), %{}} end,
          weight: 1.0,
          name: "test"
        }
      ]

      {:ok, results} = Executor.execute_all(regularizers, [], Nx.tensor([1.0]), [])

      assert length(results) == 1
      assert hd(results).name == "test"
    end
  end

  describe "execute_all/4 with gradient tracking" do
    test "includes grad_norm when track_grad_norms is true" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, logprobs -> {Nx.sum(logprobs), %{}} end,
          weight: 0.1,
          name: "sum_reg"
        }
      ]

      {:ok, results} =
        Executor.execute_all(
          regularizers,
          [],
          Nx.tensor([1.0, 2.0, 3.0]),
          track_grad_norms: true
        )

      [output] = results
      assert output.grad_norm != nil
      assert_in_delta output.grad_norm, :math.sqrt(3.0), 0.001
    end

    test "grad_norm is nil when track_grad_norms is false" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, logprobs -> {Nx.sum(logprobs), %{}} end,
          weight: 0.1,
          name: "sum_reg"
        }
      ]

      {:ok, results} =
        Executor.execute_all(
          regularizers,
          [],
          Nx.tensor([1.0, 2.0, 3.0]),
          track_grad_norms: false
        )

      [output] = results
      assert output.grad_norm == nil
    end
  end

  describe "execute_all/4 with async regularizers" do
    test "awaits async regularizer task" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _data, _logprobs ->
            Task.async(fn ->
              Process.sleep(10)
              {Nx.tensor(42.0), %{"async" => true}}
            end)
          end,
          weight: 0.5,
          name: "async_reg",
          async: true
        }
      ]

      {:ok, results} =
        Executor.execute_all(regularizers, [], Nx.tensor([1.0]), timeout: 5000)

      [output] = results
      assert output.name == "async_reg"
      assert output.value == 42.0
      assert output.custom == %{"async" => true}
    end
  end

  describe "execute_one/4" do
    test "executes single regularizer and returns output" do
      spec = %RegularizerSpec{
        fn: fn _d, logprobs -> {Nx.mean(logprobs), %{"mean" => true}} end,
        weight: 0.5,
        name: "mean_reg"
      }

      {:ok, output} = Executor.execute_one(spec, [], Nx.tensor([2.0, 4.0, 6.0]), [])

      assert %RegularizerOutput{} = output
      assert output.name == "mean_reg"
      assert output.value == 4.0
      assert output.weight == 0.5
      assert output.contribution == 2.0
      assert output.custom == %{"mean" => true}
    end

    test "handles regularizer that raises error" do
      spec = %RegularizerSpec{
        fn: fn _d, _l -> raise "Intentional error" end,
        weight: 0.1,
        name: "error_reg"
      }

      {:error, reason} = Executor.execute_one(spec, [], Nx.tensor([1.0]), [])
      assert {:regularizer_failed, "error_reg", %RuntimeError{}} = reason
    end
  end

  describe "execute_all/4 error handling" do
    test "returns error when regularizer fails in sequential mode" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end,
          weight: 0.1,
          name: "ok_reg"
        },
        %RegularizerSpec{
          fn: fn _d, _l -> raise "Boom!" end,
          weight: 0.1,
          name: "bad_reg"
        }
      ]

      {:error, reason} =
        Executor.execute_all(regularizers, [], Nx.tensor([1.0]), parallel: false)

      assert {:regularizer_failed, "bad_reg", _} = reason
    end

    test "returns error when regularizer fails in parallel mode" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> raise "Parallel boom!" end,
          weight: 0.1,
          name: "bad_parallel_reg"
        }
      ]

      {:error, reason} =
        Executor.execute_all(regularizers, [], Nx.tensor([1.0]), parallel: true)

      assert {:regularizer_failed, "bad_parallel_reg", _} = reason
    end
  end

  describe "timeout handling" do
    @tag timeout: 60_000
    test "handles timeout in parallel execution" do
      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l ->
            Process.sleep(10_000)
            {Nx.tensor(1.0), %{}}
          end,
          weight: 0.1,
          name: "slow_reg"
        }
      ]

      {:error, reason} =
        Executor.execute_all(regularizers, [], Nx.tensor([1.0]), timeout: 100, parallel: true)

      assert reason == :timeout
    end
  end
end
