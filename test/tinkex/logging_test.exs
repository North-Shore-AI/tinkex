defmodule Tinkex.LoggingTest do
  use Supertester.ExUnitFoundation,
    isolation: :full_isolation,
    logger_isolation: true

  alias Tinkex.Logging

  test "maybe_set_level updates logger when provided" do
    Logging.maybe_set_level(:warn)
    assert Logger.get_process_level(self()) == :warning

    Logging.maybe_set_level(nil)
    assert Logger.get_process_level(self()) == :warning
  end
end
