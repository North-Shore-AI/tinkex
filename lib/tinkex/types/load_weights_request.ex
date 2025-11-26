defmodule Tinkex.Types.LoadWeightsRequest do
  @moduledoc """
  Request to load model weights from a checkpoint.

  Mirrors Python `tinker.types.LoadWeightsRequest`.

  ## Fields

  - `model_id` - The model/training run ID
  - `path` - Tinker URI for model weights (e.g., "tinker://run-id/weights/checkpoint-001")
  - `seq_id` - Sequence ID for request ordering (optional)
  - `load_optimizer_state` - Whether to also load optimizer state (default: false)
  - `type` - Request type, always "load_weights"

  ## Load Optimizer State

  When `load_optimizer_state` is true, the optimizer state (Adam moments, etc.) will be
  restored along with the model weights. This is useful when resuming training from a
  checkpoint to maintain training continuity.

  ## Wire Format

  ```json
  {
    "model_id": "run-123",
    "path": "tinker://run-123/weights/checkpoint-001",
    "seq_id": 1,
    "load_optimizer_state": true,
    "type": "load_weights"
  }
  ```
  """

  @enforce_keys [:model_id, :path]
  @derive {Jason.Encoder, only: [:model_id, :path, :seq_id, :load_optimizer_state, :type]}
  defstruct [:model_id, :path, :seq_id, load_optimizer_state: false, type: "load_weights"]

  @type t :: %__MODULE__{
          model_id: String.t(),
          path: String.t(),
          seq_id: integer() | nil,
          load_optimizer_state: boolean(),
          type: String.t()
        }

  @doc """
  Create a new LoadWeightsRequest.

  ## Parameters

  - `model_id` - The model/training run ID
  - `path` - Tinker URI for model weights
  - `opts` - Optional keyword list:
    - `:seq_id` - Sequence ID for request ordering
    - `:load_optimizer_state` - Whether to load optimizer state (default: false)

  ## Examples

      iex> LoadWeightsRequest.new("run-123", "tinker://run-123/weights/001")
      %LoadWeightsRequest{model_id: "run-123", path: "tinker://run-123/weights/001", load_optimizer_state: false}

      iex> LoadWeightsRequest.new("run-123", "tinker://run-123/weights/001", load_optimizer_state: true)
      %LoadWeightsRequest{model_id: "run-123", path: "tinker://run-123/weights/001", load_optimizer_state: true}
  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(model_id, path, opts \\ []) do
    %__MODULE__{
      model_id: model_id,
      path: path,
      seq_id: Keyword.get(opts, :seq_id),
      load_optimizer_state: Keyword.get(opts, :load_optimizer_state, false),
      type: "load_weights"
    }
  end
end
