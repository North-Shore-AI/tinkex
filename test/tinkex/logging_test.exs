defmodule Tinkex.LoggingTest do
  use ExUnit.Case, async: true

  alias Tinkex.Logging

  test "maybe_set_level updates logger when provided" do
    previous = Logger.level()

    on_exit(fn ->
      Logger.configure(level: previous)
    end)

    Logging.maybe_set_level(:warn)
    assert Logger.level() == :warning

    Logging.maybe_set_level(nil)
    assert Logger.level() == :warning
  end
end
