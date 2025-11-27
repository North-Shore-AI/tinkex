defmodule Tinkex.Telemetry.Capture do
  @moduledoc false

  alias Tinkex.Telemetry.Reporter

  @doc """
  Capture exceptions in a block and log them to the telemetry reporter.

  Options:
    * `:reporter` - Reporter pid or nil (no-op when nil)
    * `:fatal?` - When true, calls `log_fatal_exception/3` (default: false)
    * `:severity` - Severity level for the exception (default: :error)

  ## Examples

      capture_exceptions reporter: reporter do
        risky_operation()
      end

      capture_exceptions reporter: reporter, fatal?: true, severity: :critical do
        critical_operation()
      end
  """
  defmacro capture_exceptions(opts, do: block) do
    reporter = Keyword.get(opts, :reporter)
    fatal? = Keyword.get(opts, :fatal?, false)
    severity = Keyword.get(opts, :severity, :error)

    quote do
      reporter_pid = unquote(reporter)
      fatal_flag = unquote(fatal?)
      severity_val = unquote(severity)

      try do
        unquote(block)
      rescue
        exception ->
          unquote(__MODULE__).__log_exception__(
            reporter_pid,
            exception,
            severity_val,
            fatal_flag
          )

          reraise exception, __STACKTRACE__
      catch
        kind, value ->
          exception = unquote(__MODULE__).__wrap_thrown__(kind, value)

          unquote(__MODULE__).__log_exception__(
            reporter_pid,
            exception,
            severity_val,
            fatal_flag
          )

          unquote(__MODULE__).__rethrow__(kind, value)
      end
    end
  end

  @doc """
  Alias for `capture_exceptions/2`.
  """
  defmacro with_telemetry(opts, do: block) do
    quote do
      unquote(__MODULE__).capture_exceptions(unquote(opts), do: unquote(block))
    end
  end

  @doc """
  Wrap `Task.async/1` with exception capture.

  Options:
    * `:reporter` - Reporter pid or nil (no-op when nil)
    * `:fatal?` - When true, calls `log_fatal_exception/3` (default: false)
    * `:severity` - Severity level for the exception (default: :error)

  ## Examples

      task = async_capture reporter: reporter do
        async_operation()
      end
      Task.await(task)
  """
  defmacro async_capture(opts, do: block) do
    reporter = Keyword.get(opts, :reporter)
    fatal? = Keyword.get(opts, :fatal?, false)
    severity = Keyword.get(opts, :severity, :error)

    quote do
      reporter_pid = unquote(reporter)
      fatal_flag = unquote(fatal?)
      severity_val = unquote(severity)

      Task.async(fn ->
        try do
          unquote(block)
        rescue
          exception ->
            unquote(__MODULE__).__log_exception__(
              reporter_pid,
              exception,
              severity_val,
              fatal_flag
            )

            reraise exception, __STACKTRACE__
        catch
          kind, value ->
            exception = unquote(__MODULE__).__wrap_thrown__(kind, value)

            unquote(__MODULE__).__log_exception__(
              reporter_pid,
              exception,
              severity_val,
              fatal_flag
            )

            unquote(__MODULE__).__rethrow__(kind, value)
        end
      end)
    end
  end

  @doc false
  def __log_exception__(nil, _exception, _severity, _fatal?), do: :ok

  def __log_exception__(reporter, exception, severity, true) do
    Reporter.log_fatal_exception(reporter, exception, severity)
  end

  def __log_exception__(reporter, exception, severity, false) do
    Reporter.log_exception(reporter, exception, severity)
  end

  @doc false
  def __wrap_thrown__(:throw, value) do
    %ErlangError{original: {:nocatch, value}}
  end

  def __wrap_thrown__(:exit, reason) do
    %ErlangError{original: {:exit, reason}}
  end

  @doc false
  def __rethrow__(:throw, value), do: throw(value)
  def __rethrow__(:exit, reason), do: exit(reason)
end
