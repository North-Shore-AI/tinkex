defmodule Tinkex.TrainingClientCustomLossTest do
  @moduledoc """
  Tests for TrainingClient.forward_backward_custom/4.

  These tests verify the custom loss integration without requiring a real
  backend connection. We test the message passing and error handling.
  """

  use ExUnit.Case, async: true

  alias Tinkex.Types.{CustomLossOutput, RegularizerSpec}

  # We'll create a minimal mock training client for testing
  defmodule MockTrainingClient do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      {:ok,
       %{
         model_id: opts[:model_id] || "test-model",
         logprobs_data: opts[:logprobs_data] || [-1.0, -2.0, -3.0]
       }}
    end

    def handle_call({:forward_backward_custom, data, base_loss_fn, opts}, from, state) do
      # Spawn background task like real TrainingClient
      Task.start(fn ->
        reply =
          try do
            # Simulate forward pass by creating logprobs from state
            logprobs = Nx.tensor(state.logprobs_data)

            # Run pipeline
            alias Tinkex.Regularizer.Pipeline

            case Pipeline.compute(data, logprobs, base_loss_fn, opts) do
              {:ok, output} -> {:ok, output}
              {:error, _} = error -> error
            end
          rescue
            e ->
              {:error,
               %Tinkex.Error{
                 message: "Custom loss failed: #{Exception.message(e)}",
                 type: :request_failed,
                 data: %{exception: e}
               }}
          end

        try do
          GenServer.reply(from, reply)
        rescue
          ArgumentError -> :ok
        end
      end)

      {:noreply, state}
    end
  end

  describe "forward_backward_custom/4" do
    setup do
      {:ok, client} = MockTrainingClient.start_link(logprobs_data: [-1.0, -2.0, -3.0])
      %{client: client}
    end

    test "returns task that resolves to CustomLossOutput", %{client: client} do
      base_loss_fn = fn _data, logprobs ->
        {Nx.negate(Nx.mean(logprobs)), %{"nll" => Nx.to_number(Nx.negate(Nx.mean(logprobs)))}}
      end

      {:ok, task} = forward_backward_custom_mock(client, [], base_loss_fn)
      {:ok, output} = Task.await(task, 5000)

      assert %CustomLossOutput{} = output
      # -mean([-1, -2, -3]) = 2.0
      assert output.loss_total == 2.0
      assert output.base_loss.value == 2.0
    end

    test "handles regularizers", %{client: client} do
      base_loss_fn = fn _data, _lp -> {Nx.tensor(1.0), %{}} end

      regularizers = [
        %RegularizerSpec{
          fn: fn _d, _l -> {Nx.tensor(10.0), %{"test" => true}} end,
          weight: 0.1,
          name: "test_reg"
        }
      ]

      {:ok, task} =
        forward_backward_custom_mock(client, [], base_loss_fn, regularizers: regularizers)

      {:ok, output} = Task.await(task, 5000)

      # base: 1.0, reg: 0.1 * 10 = 1.0, total: 2.0
      assert output.loss_total == 2.0
      assert output.regularizer_total == 1.0
      assert Map.has_key?(output.regularizers, "test_reg")
    end

    test "handles gradient tracking", %{client: client} do
      base_loss_fn = fn _data, logprobs ->
        {Nx.sum(logprobs), %{}}
      end

      {:ok, task} =
        forward_backward_custom_mock(client, [], base_loss_fn, track_grad_norms: true)

      {:ok, output} = Task.await(task, 5000)

      assert output.base_loss.grad_norm != nil
    end

    test "handles errors gracefully", %{client: client} do
      bad_loss_fn = fn _data, _logprobs ->
        raise "Intentional error"
      end

      {:ok, task} = forward_backward_custom_mock(client, [], bad_loss_fn)
      result = Task.await(task, 5000)

      # Pipeline returns {:error, {:pipeline_failed, exception}} for errors
      assert {:error, {:pipeline_failed, %RuntimeError{}}} = result
    end
  end

  # Helper to call our mock client
  defp forward_backward_custom_mock(client, data, loss_fn, opts \\ []) do
    {:ok,
     Task.async(fn ->
       GenServer.call(client, {:forward_backward_custom, data, loss_fn, opts}, :infinity)
     end)}
  end
end
