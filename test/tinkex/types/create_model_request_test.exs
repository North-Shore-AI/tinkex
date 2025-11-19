defmodule Tinkex.Types.CreateModelRequestTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{CreateModelRequest, LoraConfig}

  test "defaults lora_config to a struct with SDK defaults" do
    request = struct(CreateModelRequest)

    assert request.lora_config == %LoraConfig{}
  end
end
