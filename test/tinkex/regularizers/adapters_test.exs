defmodule Tinkex.Regularizers.AdaptersTest do
  use ExUnit.Case, async: true

  alias Tinkex.Regularizers

  test "l1 adapter resolves targets and metrics" do
    logprobs = Nx.log(Nx.tensor([[0.5, 0.25, 0.25]]))
    data = [%{loss_fn_inputs: %{}, model_input: :placeholder}]

    {value, metrics} = Regularizers.L1.compute(data, logprobs, target: :logprobs, reduction: :sum)

    assert is_number(metrics["l1_raw"])
    assert is_number(metrics["l1_mean"])
    assert Nx.shape(value) == {}
  end

  test "l2 adapter supports centering" do
    logprobs = Nx.log(Nx.tensor([[0.4, 0.3, 0.3]]))
    data = [%{loss_fn_inputs: %{}}]

    {value, metrics} = Regularizers.L2.compute(data, logprobs, center: :mean)

    assert is_number(metrics["l2_raw"])
    assert is_number(metrics["l2_mean"])
    assert Nx.shape(value) == {}
  end

  test "elastic net adapter returns scalar" do
    logprobs = Nx.log(Nx.tensor([[0.6, 0.4]]))
    data = [%{loss_fn_inputs: %{}}]

    {value, metrics} = Regularizers.ElasticNet.compute(data, logprobs, l1_ratio: 0.5)

    assert Nx.shape(value) == {}
    assert metrics["l1_ratio"] == 0.5
  end

  test "kl divergence adapter resolves reference" do
    logprobs = Nx.log(Nx.tensor([[0.4, 0.3, 0.3]]))
    reference = Nx.log(Nx.tensor([[0.25, 0.25, 0.5]]))
    data = [%{loss_fn_inputs: %{reference_logprobs: reference}}]

    {value, metrics} =
      Regularizers.KLDivergence.compute(data, logprobs, reference_field: :reference_logprobs)

    assert Nx.shape(value) == {}
    assert is_number(metrics["kl_divergence"])
  end

  test "kl divergence adapter supports direction option" do
    logprobs = Nx.log(Nx.tensor([[0.4, 0.3, 0.3]]))
    reference = Nx.log(Nx.tensor([[0.25, 0.25, 0.5]]))
    data = [%{loss_fn_inputs: %{reference_logprobs: reference}}]

    {loss, metrics} =
      Regularizers.KLDivergence.compute(data, logprobs,
        reference_field: :reference_logprobs,
        direction: :reverse
      )

    assert Nx.shape(loss) == {}
    assert metrics["kl_direction"] == "reverse"
  end

  test "kl divergence adapter supports symmetric option" do
    logprobs = Nx.log(Nx.tensor([[0.4, 0.3, 0.3]]))
    reference = Nx.log(Nx.tensor([[0.25, 0.25, 0.5]]))
    data = [%{loss_fn_inputs: %{reference_logprobs: reference}}]

    {loss, metrics} =
      Regularizers.KLDivergence.compute(data, logprobs,
        reference_field: :reference_logprobs,
        symmetric: true
      )

    assert Nx.shape(loss) == {}
    assert metrics["kl_symmetric"] == true
  end

  test "entropy adapter supports modes" do
    logprobs = Nx.log(Nx.tensor([[0.25, 0.25, 0.25, 0.25]]))
    data = [%{loss_fn_inputs: %{}}]

    {bonus, _} = Regularizers.Entropy.compute(data, logprobs, mode: :maximize)
    {penalty, _} = Regularizers.Entropy.compute(data, logprobs, mode: :minimize)

    assert Nx.to_number(bonus) <= 0
    assert Nx.to_number(penalty) >= 0
  end

  test "entropy adapter supports temperature option" do
    logprobs = Nx.log(Nx.tensor([[0.25, 0.25, 0.25, 0.25]]))

    {loss, metrics} =
      Regularizers.Entropy.compute([], logprobs, mode: :maximize, temperature: 0.5)

    assert Nx.shape(loss) == {}
    assert metrics["temperature"] == 0.5
  end

  test "entropy adapter temperature affects output value" do
    logprobs = Nx.log(Nx.tensor([[0.6, 0.3, 0.1]]))

    {loss_default, _} = Regularizers.Entropy.compute([], logprobs, mode: :maximize)

    {loss_sharp, _} =
      Regularizers.Entropy.compute([], logprobs, mode: :maximize, temperature: 0.5)

    {loss_flat, _} = Regularizers.Entropy.compute([], logprobs, mode: :maximize, temperature: 2.0)

    refute Nx.to_number(loss_default) == Nx.to_number(loss_sharp)
    refute Nx.to_number(loss_default) == Nx.to_number(loss_flat)
  end

  test "consistency adapter uses pair field" do
    logprobs = Nx.log(Nx.tensor([[0.5, 0.5]]))
    reference = Nx.log(Nx.tensor([[0.4, 0.6]]))
    data = [%{loss_fn_inputs: %{original_logprobs: reference}}]

    {loss, metrics} =
      Regularizers.Consistency.compute(data, logprobs, pair_field: :original_logprobs)

    assert Nx.shape(loss) == {}
    assert metrics["consistency_metric"] == "mse"
  end

  test "orthogonality adapter returns scalar" do
    logprobs = Nx.log(Nx.tensor([[0.5, 0.5], [0.4, 0.6]]))
    data = [%{loss_fn_inputs: %{}}]

    {penalty, metrics} = Regularizers.Orthogonality.compute(data, logprobs, mode: :soft)

    assert Nx.shape(penalty) == {}
    assert is_number(metrics["orthogonality"])
  end

  test "gradient penalty adapter supports output mode" do
    logprobs = Nx.log(Nx.tensor([[0.5, 0.5]]))
    data = [%{loss_fn_inputs: %{}}]

    loss_fn = fn x -> Nx.sum(x) end

    {penalty, _} =
      Regularizers.GradientPenalty.compute(data, logprobs,
        mode: :output,
        loss_fn: loss_fn,
        target_norm: 1.0
      )

    assert Nx.shape(penalty) == {}
  end

  test "gradient penalty adapter supports interpolated mode" do
    logprobs = Nx.log(Nx.tensor([[0.5, 0.5]]))
    reference = Nx.log(Nx.tensor([[0.4, 0.6]]))
    data = [%{loss_fn_inputs: %{reference_logprobs: reference}}]

    loss_fn = fn x -> Nx.sum(x) end

    {penalty, _} =
      Regularizers.GradientPenalty.compute(data, logprobs,
        mode: :interpolated,
        loss_fn: loss_fn,
        reference_field: :reference_logprobs,
        target_norm: 1.0
      )

    assert Nx.shape(penalty) == {}
  end
end
