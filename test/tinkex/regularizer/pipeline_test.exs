defmodule Tinkex.Regularizer.PipelineTest do
  use ExUnit.Case, async: true

  alias Tinkex.Regularizer.Pipeline
  alias Tinkex.Types.{CustomLossOutput, RegularizerSpec}

  describe "compute/4 with base loss only" do
    test "computes base loss when no regularizers" do
      data = []
      logprobs = Nx.tensor([-1.0, -2.0, -3.0])

      base_loss_fn = fn _data, lp ->
        loss = Nx.negate(Nx.mean(lp))
        {loss, %{"mean_nll" => Nx.to_number(loss)}}
      end

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn)

      assert %CustomLossOutput{} = output
      assert output.loss_total == 2.0
      assert output.base_loss.value == 2.0
      assert output.base_loss.custom == %{"mean_nll" => 2.0}
      assert output.regularizer_total == 0.0
      assert output.regularizers == %{}
    end

    test "computes base loss with empty regularizers list" do
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      base_loss_fn = fn _data, lp ->
        {Nx.sum(lp), %{}}
      end

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn, regularizers: [])

      assert output.loss_total == 6.0
      assert output.regularizer_total == 0.0
    end
  end

  describe "compute/4 with regularizers" do
    test "composes base loss with single regularizer" do
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      base_loss_fn = fn _data, _lp ->
        {Nx.tensor(1.0), %{}}
      end

      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(10.0), %{"reg_metric" => 10.0}} end,
          weight: 0.1,
          name: "reg_a"
        }
      ]

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)

      # base: 1.0, reg_a: 0.1 * 10 = 1.0
      # total: 1.0 + 1.0 = 2.0
      assert output.loss_total == 2.0
      assert output.regularizer_total == 1.0
      assert Map.has_key?(output.regularizers, "reg_a")
      assert output.regularizers["reg_a"].contribution == 1.0
    end

    test "composes base loss with multiple regularizers" do
      data = []
      logprobs = Nx.tensor([1.0])

      base_loss_fn = fn _data, _lp ->
        {Nx.tensor(1.0), %{}}
      end

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

      {:ok, output} = Pipeline.compute(data, logprobs, base_loss_fn, regularizers: regularizers)

      # base: 1.0, reg_a: 0.1*10=1.0, reg_b: 0.5*20=10.0
      # total: 1.0 + 1.0 + 10.0 = 12.0
      assert output.loss_total == 12.0
      assert output.regularizer_total == 11.0
      assert output.regularizers["reg_a"].contribution == 1.0
      assert output.regularizers["reg_b"].contribution == 10.0
    end
  end

  describe "compute/4 with gradient tracking" do
    test "includes base_grad_norm when track_grad_norms is true" do
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      base_loss_fn = fn _data, lp ->
        {Nx.sum(lp), %{}}
      end

      {:ok, output} =
        Pipeline.compute(data, logprobs, base_loss_fn, track_grad_norms: true)

      assert output.base_loss.grad_norm != nil
      # gradient of sum is [1, 1, 1], L2 norm = sqrt(3)
      assert_in_delta output.base_loss.grad_norm, :math.sqrt(3.0), 0.001
    end

    test "includes total_grad_norm when track_grad_norms is true with regularizers" do
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      base_loss_fn = fn _data, lp ->
        {Nx.sum(lp), %{}}
      end

      regularizers = [
        %RegularizerSpec{
          fn: fn _d, lp -> {Nx.sum(Nx.pow(lp, 2)), %{}} end,
          weight: 0.5,
          name: "l2"
        }
      ]

      {:ok, output} =
        Pipeline.compute(data, logprobs, base_loss_fn,
          regularizers: regularizers,
          track_grad_norms: true
        )

      assert output.total_grad_norm != nil
      assert output.regularizers["l2"].grad_norm != nil
    end
  end

  describe "compute/4 validation" do
    test "returns error for non-function base_loss_fn" do
      {:error, {:pipeline_failed, %ArgumentError{}}} =
        Pipeline.compute([], Nx.tensor([1.0]), "not a function")
    end

    test "returns error for invalid regularizer spec" do
      base_loss_fn = fn _d, _l -> {Nx.tensor(1.0), %{}} end

      {:error, {:pipeline_failed, %ArgumentError{}}} =
        Pipeline.compute([], Nx.tensor([1.0]), base_loss_fn, regularizers: [%{invalid: true}])
    end

    test "returns error for duplicate regularizer names" do
      base_loss_fn = fn _d, _l -> {Nx.tensor(1.0), %{}} end

      regularizers = [
        %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end, weight: 0.1, name: "dup"},
        %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(1.0), %{}} end, weight: 0.2, name: "dup"}
      ]

      {:error, {:pipeline_failed, %ArgumentError{message: msg}}} =
        Pipeline.compute([], Nx.tensor([1.0]), base_loss_fn, regularizers: regularizers)

      assert msg =~ "Duplicate regularizer names"
    end
  end

  describe "compute/4 parallel vs sequential" do
    test "parallel execution produces same results as sequential" do
      data = []
      logprobs = Nx.tensor([1.0, 2.0, 3.0])

      base_loss_fn = fn _data, lp -> {Nx.sum(lp), %{}} end

      regularizers = [
        %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(5.0), %{}} end, weight: 0.1, name: "a"},
        %RegularizerSpec{fn: fn _d, _l -> {Nx.tensor(10.0), %{}} end, weight: 0.2, name: "b"}
      ]

      {:ok, parallel_output} =
        Pipeline.compute(data, logprobs, base_loss_fn,
          regularizers: regularizers,
          parallel: true
        )

      {:ok, sequential_output} =
        Pipeline.compute(data, logprobs, base_loss_fn,
          regularizers: regularizers,
          parallel: false
        )

      assert parallel_output.loss_total == sequential_output.loss_total
      assert parallel_output.regularizer_total == sequential_output.regularizer_total
    end
  end

  describe "compute/4 error handling" do
    test "returns error when base loss fails" do
      base_loss_fn = fn _d, _l ->
        raise "Base loss error"
      end

      {:error, {:pipeline_failed, %RuntimeError{}}} =
        Pipeline.compute([], Nx.tensor([1.0]), base_loss_fn)
    end

    test "returns error when regularizer fails" do
      base_loss_fn = fn _d, _l -> {Nx.tensor(1.0), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> raise "Regularizer error" end,
          weight: 0.1,
          name: "bad_reg"
        }
      ]

      {:error, _reason} =
        Pipeline.compute([], Nx.tensor([1.0]), base_loss_fn, regularizers: regularizers)
    end
  end

  describe "compute/4 telemetry" do
    test "emits custom_loss telemetry events" do
      ref = make_ref()
      parent = self()

      :telemetry.attach_many(
        ref,
        [
          [:tinkex, :custom_loss, :start],
          [:tinkex, :custom_loss, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      base_loss_fn = fn _d, _l -> {Nx.tensor(1.0), %{}} end

      {:ok, _} = Pipeline.compute([], Nx.tensor([1.0]), base_loss_fn)

      assert_receive {:telemetry, [:tinkex, :custom_loss, :start], _, _}
      assert_receive {:telemetry, [:tinkex, :custom_loss, :stop], %{loss_total: _}, _}

      :telemetry.detach(ref)
    end
  end
end
