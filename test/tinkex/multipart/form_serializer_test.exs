defmodule Tinkex.Multipart.FormSerializerTest do
  use ExUnit.Case, async: true

  alias Tinkex.Multipart.FormSerializer

  describe "serialize_form_fields/1" do
    test "flattens simple map" do
      assert %{"name" => "value"} = FormSerializer.serialize_form_fields(%{name: "value"})
    end

    test "uses bracket notation for nested maps" do
      result = FormSerializer.serialize_form_fields(%{user: %{name: "Alice", age: 30}})

      assert result["user[name]"] == "Alice"
      assert result["user[age]"] == "30"
    end

    test "uses bracket notation for arrays" do
      result = FormSerializer.serialize_form_fields(%{tags: ["a", "b", "c"]})

      assert result["tags[]"] == ["a", "b", "c"]
    end

    test "handles deeply nested structures" do
      result =
        FormSerializer.serialize_form_fields(%{
          config: %{
            nested: %{
              deep: "value"
            }
          }
        })

      assert result["config[nested][deep]"] == "value"
    end

    test "handles arrays of maps" do
      result =
        FormSerializer.serialize_form_fields(%{
          documents: [
            %{type: "pdf", name: "doc1"},
            %{type: "docx", name: "doc2"}
          ]
        })

      assert is_list(result["documents[][type]"])
      assert "pdf" in result["documents[][type]"]
      assert "docx" in result["documents[][type]"]
    end
  end
end
