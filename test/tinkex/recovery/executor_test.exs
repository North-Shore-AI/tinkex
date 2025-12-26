defmodule Tinkex.Recovery.ExecutorTest do
  use Supertester.ExUnitFoundation,
    isolation: :basic,
    telemetry_isolation: true

  alias Supertester.TelemetryHelpers
  alias Tinkex.Recovery.{Executor, Policy}
  alias Tinkex.TestSupport.Recovery.ServiceStub
  alias Tinkex.Types.Checkpoint
  require TelemetryHelpers

  setup do
    service_pid = make_ref()
    ServiceStub.set_test_pid(self(), service_pid)

    send_after = fn msg, _delay ->
      send(self(), msg)
      make_ref()
    end

    on_exit(fn ->
      ServiceStub.clear(service_pid)
    end)

    %{send_after: send_after, service_pid: service_pid}
  end

  test "selects latest checkpoint and restores optimizer", %{
    send_after: send_after,
    service_pid: service_pid
  } do
    test_pid = self()

    policy =
      %Policy{enabled: true, checkpoint_strategy: :latest, restore_optimizer: true}
      |> Map.put(:on_recovery, fn old_pid, new_pid, checkpoint ->
        send(test_pid, {:recovered, old_pid, new_pid, checkpoint})
        :ok
      end)

    {:ok, executor} =
      start_supervised(
        {Executor,
         service_client_module: ServiceStub, rest_module: Tinkex.API.Rest, send_after: send_after}
      )

    {:ok, _} =
      TelemetryHelpers.attach_isolated([
        [:tinkex, :recovery, :started],
        [:tinkex, :recovery, :completed]
      ])

    checkpoint = %Checkpoint{tinker_path: "tinker://run/checkpoint"}

    assert :ok =
             Executor.recover(executor, "run-123", service_pid, policy,
               last_checkpoint: checkpoint,
               metadata: TelemetryHelpers.current_test_metadata(%{training_pid: :old_training})
             )

    assert_receive {:client_created, ^service_pid, "tinker://run/checkpoint", []}
    assert_receive {:recovered, :old_training, :new_training_client, %Checkpoint{}}

    {:telemetry, _, _meas, meta} =
      TelemetryHelpers.assert_telemetry([:tinkex, :recovery, :completed])

    assert meta.run_id == "run-123"

    monitor = Process.monitor(executor)
    GenServer.stop(executor)
    assert_receive {:DOWN, ^monitor, :process, ^executor, _}
  end

  test "backs off and emits exhausted after max attempts", %{
    send_after: send_after,
    service_pid: service_pid
  } do
    ServiceStub.set_failures(3, service_pid)

    test_pid = self()

    policy =
      %Policy{
        enabled: true,
        checkpoint_strategy: :latest,
        restore_optimizer: false,
        max_attempts: 2,
        backoff_ms: 1,
        max_backoff_ms: 1
      }
      |> Map.put(:on_failure, fn run_id, reason ->
        send(test_pid, {:failure_callback, run_id, reason})
        :ok
      end)

    {:ok, executor} =
      start_supervised(
        {Executor,
         service_client_module: ServiceStub, rest_module: Tinkex.API.Rest, send_after: send_after}
      )

    {:ok, _} =
      TelemetryHelpers.attach_isolated([
        [:tinkex, :recovery, :failed],
        [:tinkex, :recovery, :exhausted]
      ])

    assert :ok =
             Executor.recover(executor, "run-exhausted", service_pid, policy,
               last_checkpoint: "tinker://run/checkpoint",
               metadata: TelemetryHelpers.current_test_metadata()
             )

    assert_receive {:failure_callback, "run-exhausted", :not_ready}

    {:telemetry, _, _meas, meta} =
      TelemetryHelpers.assert_telemetry([:tinkex, :recovery, :exhausted])

    assert meta.run_id == "run-exhausted"

    monitor = Process.monitor(executor)
    GenServer.stop(executor)
    assert_receive {:DOWN, ^monitor, :process, ^executor, _}
  end
end
