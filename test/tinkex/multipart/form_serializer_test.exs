defmodule Tinkex.Multipart.FormSerializerTest do
  use ExUnit.Case, async: true

  alias Multipart.Form

  @form_opts [strategy: :bracket, list_format: :repeat, nil: :empty]

  defp group(values) do
    Enum.group_by(values, &elem(&1, 0), &elem(&1, 1))
  end

  describe "serialize/2" do
    test "flattens simple map" do
      assert [{"name", "value"}] = Form.serialize(%{name: "value"}, @form_opts)
    end

    test "uses bracket notation for nested maps" do
      result = Form.serialize(%{user: %{name: "Alice", age: 30}}, @form_opts) |> group()

      assert result["user[name]"] == ["Alice"]
      assert result["user[age]"] == [30]
    end

    test "uses bracket notation for arrays" do
      result = Form.serialize(%{tags: ["a", "b", "c"]}, @form_opts) |> group()

      assert result["tags[]"] == ["a", "b", "c"]
    end

    test "handles deeply nested structures" do
      result =
        Form.serialize(
          %{
            config: %{
              nested: %{
                deep: "value"
              }
            }
          },
          @form_opts
        )
        |> group()

      assert result["config[nested][deep]"] == ["value"]
    end

    test "handles arrays of maps" do
      result =
        Form.serialize(
          %{
            documents: [
              %{type: "pdf", name: "doc1"},
              %{type: "docx", name: "doc2"}
            ]
          },
          @form_opts
        )
        |> group()

      assert Enum.sort(result["documents[][type]"]) == ["docx", "pdf"]
      assert Enum.sort(result["documents[][name]"]) == ["doc1", "doc2"]
    end

    test "serializes nil as empty string when configured" do
      result = Form.serialize(%{note: nil}, @form_opts) |> group()

      assert result["note"] == [""]
    end
  end
end
