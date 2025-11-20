defmodule TinkexTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation
  doctest Tinkex

  test "greets the world" do
    assert Tinkex.hello() == :world
  end
end
