defmodule Tinkex.Types.ForwardBackwardInput do
  @moduledoc """
  Input for forward-backward pass.

  Mirrors Python tinker.types.ForwardBackwardInput.
  """

  alias Tinkex.Types.Datum

  defstruct [:data, :loss_fn, :loss_fn_config]

  @type t :: %__MODULE__{
          data: [Datum.t()],
          loss_fn: String.t(),
          loss_fn_config: map() | nil
        }
end

defimpl Jason.Encoder, for: Tinkex.Types.ForwardBackwardInput do
  def encode(input, opts) do
    loss_fn_str =
      if is_atom(input.loss_fn) do
        Tinkex.Types.LossFnType.to_string(input.loss_fn)
      else
        input.loss_fn
      end

    %{
      data: input.data,
      loss_fn: loss_fn_str,
      loss_fn_config: input.loss_fn_config
    }
    |> Jason.Encode.map(opts)
  end
end
