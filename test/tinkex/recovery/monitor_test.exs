defmodule Tinkex.Recovery.MonitorTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Recovery.{Executor, Monitor, Policy}
  alias Tinkex.Types.TrainingRun
  alias Tinkex.TestSupport.Recovery.ServiceStub

  defmodule RestStub do
    def set_run(run_id, map), do: :persistent_term.put({__MODULE__, run_id}, map)
    def clear, do: :persistent_term.erase({__MODULE__, :all})

    def get_training_run(_config, run_id) do
      case :persistent_term.get({__MODULE__, run_id}, nil) do
        nil -> {:error, :not_found}
        map -> {:ok, TrainingRun.from_map(map)}
      end
    end
  end

  setup do
    :persistent_term.put({RestStub, :all}, :ok)
    service_pid = make_ref()
    ServiceStub.set_test_pid(self(), service_pid)

    on_exit(fn ->
      :persistent_term.erase({RestStub, :all})
      :persistent_term.erase({RestStub, "run-1"})
      :persistent_term.erase({RestStub, "run-healthy"})
      ServiceStub.clear(service_pid)
    end)

    send_after = fn msg, _delay ->
      send(self(), msg)
      make_ref()
    end

    %{send_after: send_after, service_pid: service_pid}
  end

  test "polls, detects corruption, and enqueues recovery", %{
    send_after: send_after,
    service_pid: service_pid
  } do
    RestStub.set_run("run-1", training_run_payload(corrupted: true))

    policy = %Policy{enabled: true, poll_interval_ms: 5}

    {:ok, executor} =
      start_supervised(
        {Executor,
         service_client_module: ServiceStub, rest_module: RestStub, send_after: send_after}
      )

    {:ok, monitor} =
      start_supervised(
        {Monitor,
         executor: executor,
         policy: policy,
         rest_client_fun: fn _pid -> {:ok, %{config: :config}} end,
         send_after: send_after,
         rest_module: RestStub}
      )

    handler =
      Tinkex.HTTPCase.attach_telemetry([
        [:tinkex, :recovery, :detected],
        [:tinkex, :recovery, :started],
        [:tinkex, :recovery, :client_created]
      ])

    assert :ok = Monitor.monitor_run(monitor, "run-1", service_pid, %{training_pid: :old})

    send(monitor, :poll)

    assert_receive {:telemetry, [:tinkex, :recovery, :detected], _m, meta}
    assert meta.run_id == "run-1"

    assert_receive {:telemetry, [:tinkex, :recovery, :client_created], _m, cc_meta}, 500
    assert cc_meta.checkpoint.tinker_path == "tinker://run-1/weights/0001"

    assert_receive {:client_created, ^service_pid, "tinker://run-1/weights/0001", []}, 200

    state = :sys.get_state(monitor)
    refute Map.has_key?(state.runs, "run-1")

    :telemetry.detach(handler)
  end

  test "does nothing for healthy runs", %{send_after: send_after, service_pid: service_pid} do
    RestStub.set_run("run-healthy", training_run_payload(corrupted: false, run_id: "run-healthy"))

    {:ok, executor} =
      start_supervised(
        {Executor,
         service_client_module: ServiceStub, rest_module: RestStub, send_after: send_after}
      )

    {:ok, monitor} =
      start_supervised(
        {Monitor,
         executor: executor,
         policy: %Policy{enabled: true, poll_interval_ms: 5},
         rest_client_fun: fn _pid -> {:ok, %{config: :config}} end,
         send_after: send_after,
         rest_module: RestStub}
      )

    assert :ok = Monitor.monitor_run(monitor, "run-healthy", service_pid)

    send(monitor, :poll)

    refute_receive {:telemetry, [:tinkex, :recovery, :detected], _, _}
    state = :sys.get_state(monitor)
    assert Map.has_key?(state.runs, "run-healthy")
  end

  test "returns error when disabled", %{send_after: send_after, service_pid: service_pid} do
    {:ok, monitor} =
      start_supervised(
        {Monitor,
         executor: self(),
         policy: %Policy{enabled: false},
         rest_client_fun: fn _ -> {:ok, %{config: nil}} end,
         send_after: send_after,
         rest_module: RestStub}
      )

    assert {:error, :recovery_disabled} =
             Monitor.monitor_run(monitor, "run-disabled", service_pid)
  end

  defp training_run_payload(opts) do
    corrupted = Keyword.get(opts, :corrupted, true)
    run_id = Keyword.get(opts, :run_id, "run-1")

    %{
      "training_run_id" => run_id,
      "base_model" => "meta-llama/Llama-3-8B",
      "model_owner" => "owner",
      "is_lora" => true,
      "corrupted" => corrupted,
      "last_request_time" => "2025-11-26T00:00:00Z",
      "last_checkpoint" => %{
        "checkpoint_id" => "ckpt-1",
        "checkpoint_type" => "weights",
        "tinker_path" => "tinker://run-1/weights/0001",
        "time" => "2025-11-26T00:00:00Z"
      }
    }
  end
end
