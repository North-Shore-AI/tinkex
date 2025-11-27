defmodule Tinkex.Telemetry.CaptureTest do
  use ExUnit.Case, async: true

  require Tinkex.Telemetry.Capture
  alias Tinkex.Telemetry.Capture
  import ExUnit.CaptureLog

  defmodule MockReporter do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: opts[:name])
    end

    def init(_opts) do
      {:ok, %{exceptions: [], fatal_exceptions: []}}
    end

    def get_exceptions(pid) do
      GenServer.call(pid, :get_exceptions)
    end

    def get_fatal_exceptions(pid) do
      GenServer.call(pid, :get_fatal_exceptions)
    end

    def handle_call(:get_exceptions, _from, state) do
      {:reply, state.exceptions, state}
    end

    def handle_call(:get_fatal_exceptions, _from, state) do
      {:reply, state.fatal_exceptions, state}
    end

    def handle_call({:log_exception, exception, severity, :nonfatal}, _from, state) do
      {:reply, true, %{state | exceptions: [{exception, severity} | state.exceptions]}}
    end

    def handle_call({:log_exception, exception, severity, :fatal}, _from, state) do
      {:reply, true,
       %{state | fatal_exceptions: [{exception, severity} | state.fatal_exceptions]}}
    end
  end

  describe "capture_exceptions/2" do
    test "logs nonfatal exception and re-raises" do
      {:ok, reporter} = MockReporter.start_link()

      assert_raise RuntimeError, "test error", fn ->
        Capture.capture_exceptions reporter: reporter do
          raise "test error"
        end
      end

      exceptions = MockReporter.get_exceptions(reporter)
      assert length(exceptions) == 1
      [{exception, severity}] = exceptions
      assert %RuntimeError{message: "test error"} = exception
      assert severity == :error
    end

    test "logs fatal exception when fatal?: true" do
      {:ok, reporter} = MockReporter.start_link()

      assert_raise RuntimeError, "fatal error", fn ->
        Capture.capture_exceptions reporter: reporter, fatal?: true do
          raise "fatal error"
        end
      end

      fatal_exceptions = MockReporter.get_fatal_exceptions(reporter)
      assert length(fatal_exceptions) == 1
      [{exception, severity}] = fatal_exceptions
      assert %RuntimeError{message: "fatal error"} = exception
      assert severity == :error
    end

    test "uses custom severity" do
      {:ok, reporter} = MockReporter.start_link()

      assert_raise RuntimeError, fn ->
        Capture.capture_exceptions reporter: reporter, severity: :critical do
          raise "critical error"
        end
      end

      exceptions = MockReporter.get_exceptions(reporter)
      assert length(exceptions) == 1
      [{_exception, severity}] = exceptions
      assert severity == :critical
    end

    test "returns block value when no exception" do
      {:ok, reporter} = MockReporter.start_link()

      result =
        Capture.capture_exceptions reporter: reporter do
          {:ok, 42}
        end

      assert result == {:ok, 42}
      assert MockReporter.get_exceptions(reporter) == []
    end

    test "nil reporter is no-op but still re-raises" do
      assert_raise RuntimeError, "noop error", fn ->
        Capture.capture_exceptions reporter: nil do
          raise "noop error"
        end
      end
    end

    test "nil reporter returns block value" do
      result =
        Capture.capture_exceptions reporter: nil do
          :success
        end

      assert result == :success
    end

    test "catches throws and re-raises" do
      {:ok, reporter} = MockReporter.start_link()

      assert catch_throw(
               Capture.capture_exceptions reporter: reporter do
                 throw(:test_throw)
               end
             ) == :test_throw

      exceptions = MockReporter.get_exceptions(reporter)
      assert length(exceptions) == 1
    end

    test "catches exits and re-raises" do
      {:ok, reporter} = MockReporter.start_link()

      assert catch_exit(
               Capture.capture_exceptions reporter: reporter do
                 exit(:test_exit)
               end
             ) == :test_exit

      exceptions = MockReporter.get_exceptions(reporter)
      assert length(exceptions) == 1
    end
  end

  describe "with_telemetry/2" do
    test "is an alias for capture_exceptions" do
      {:ok, reporter} = MockReporter.start_link()

      assert_raise RuntimeError, "telemetry error", fn ->
        Capture.with_telemetry reporter: reporter do
          raise "telemetry error"
        end
      end

      exceptions = MockReporter.get_exceptions(reporter)
      assert length(exceptions) == 1
    end
  end

  describe "async_capture/2" do
    test "wraps Task.async with exception capture" do
      {:ok, reporter} = MockReporter.start_link()

      task =
        Capture.async_capture reporter: reporter do
          {:ok, "async result"}
        end

      assert {:ok, "async result"} = Task.await(task)
    end

    test "logs exception in async task" do
      {:ok, reporter} = MockReporter.start_link()

      Process.flag(:trap_exit, true)

      capture_log(fn ->
        task =
          Capture.async_capture reporter: reporter do
            raise "async error"
          end

        ref = Process.monitor(task.pid)
        assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
      end)

      exceptions = MockReporter.get_exceptions(reporter)
      assert length(exceptions) == 1
    end

    test "nil reporter creates task without logging" do
      task =
        Capture.async_capture reporter: nil do
          :async_success
        end

      assert :async_success = Task.await(task)
    end
  end

  describe "macro expansion" do
    test "expands to try/rescue/catch block" do
      ast =
        quote do
          Capture.capture_exceptions reporter: pid do
            do_something()
          end
        end

      expanded = Macro.expand(ast, __ENV__)
      expanded_str = Macro.to_string(expanded)

      assert expanded_str =~ "try"
      assert expanded_str =~ "rescue"
      assert expanded_str =~ "catch"
    end
  end
end
