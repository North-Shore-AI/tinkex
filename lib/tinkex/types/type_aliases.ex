defmodule Tinkex.Types.TypeAliases do
  @moduledoc """
  Type aliases for Python SDK parity.

  These type aliases mirror Python's TypeAlias definitions for
  union types and dictionary types.

  ## ModelInputChunk

  Union of input chunk types that can appear in model input:
  - `EncodedTextChunk` - tokenized text
  - `ImageAssetPointerChunk` - reference to image asset
  - `ImageChunk` - inline image data

  Mirrors Python `tinker.types.ModelInputChunk`.

  ## LossFnInputs / LossFnOutput

  Dictionary mapping string keys to TensorData values.
  Used for loss function inputs and outputs.

  Mirrors Python `tinker.types.LossFnInputs` and `tinker.types.LossFnOutput`.
  """

  alias Tinkex.Types.{EncodedTextChunk, ImageAssetPointerChunk, ImageChunk, TensorData}

  @typedoc """
  Union of model input chunk types.

  Mirrors Python `ModelInputChunk = Union[EncodedTextChunk, ImageAssetPointerChunk, ImageChunk]`.
  """
  @type model_input_chunk ::
          EncodedTextChunk.t()
          | ImageAssetPointerChunk.t()
          | ImageChunk.t()

  @typedoc """
  Dictionary mapping string keys to TensorData.

  Mirrors Python `LossFnInputs = Dict[str, TensorData]`.
  """
  @type loss_fn_inputs :: %{optional(String.t()) => TensorData.t()}

  @typedoc """
  Dictionary mapping string keys to TensorData.

  Mirrors Python `LossFnOutput = Dict[str, TensorData]`.
  """
  @type loss_fn_output :: %{optional(String.t()) => TensorData.t()}
end
