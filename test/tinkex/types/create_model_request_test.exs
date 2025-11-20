defmodule Tinkex.Types.CreateModelRequestTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  alias Tinkex.Types.{CreateModelRequest, LoraConfig}

  test "defaults lora_config to a struct with SDK defaults" do
    request =
      struct(CreateModelRequest,
        session_id: "session",
        model_seq_id: 1,
        base_model: "model"
      )

    assert request.lora_config == %LoraConfig{}
  end
end
