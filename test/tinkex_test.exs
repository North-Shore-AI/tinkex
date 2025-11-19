defmodule TinkexTest do
  use ExUnit.Case
  doctest Tinkex

  test "greets the world" do
    assert Tinkex.hello() == :world
  end
end
