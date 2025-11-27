defmodule Tinkex.TransformTest do
  use ExUnit.Case, async: true

  alias Tinkex.NotGiven
  alias Tinkex.Transform

  test "drops NotGiven/omit sentinels but preserves nil" do
    input = %{
      a: 1,
      b: NotGiven.value(),
      c: nil,
      nested: %{skip: NotGiven.omit(), keep: "ok"}
    }

    assert %{"a" => 1, "c" => nil, "nested" => %{"keep" => "ok"}} = Transform.transform(input)
  end

  test "applies aliases and formatting recursively" do
    timestamp = ~U[2025-11-26 10:00:00Z]

    input = %{
      timestamp: timestamp,
      inner: [
        %{token_id: 1, drop: NotGiven.value()},
        %{token_id: 2, note: "keep"}
      ]
    }

    result =
      Transform.transform(input,
        aliases: %{timestamp: "time", token_id: "tid"},
        formats: %{timestamp: :iso8601}
      )

    assert %{
             "time" => "2025-11-26T10:00:00Z",
             "inner" => [%{"tid" => 1}, %{"tid" => 2, "note" => "keep"}]
           } = result
  end

  test "NotGiven guard helpers detect sentinel values" do
    refute NotGiven.not_given?(nil)
    refute NotGiven.not_given?(false)
    assert NotGiven.not_given?(NotGiven.value())
    assert NotGiven.omit?(NotGiven.omit())
    refute NotGiven.omit?(NotGiven.value())
  end
end
