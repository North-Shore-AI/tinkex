defmodule Tinkex.Types.ForwardBackwardInput do
  @moduledoc """
  Input for forward-backward pass.

  Mirrors Python tinker.types.ForwardBackwardInput.
  """

  alias Sinter.Schema
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.{Datum, LossFnType}

  @enforce_keys [:data, :loss_fn]
  defstruct [:data, :loss_fn, :loss_fn_config]

  @schema Schema.define([
            {:data, {:array, {:object, Datum.schema()}}, [required: true]},
            {:loss_fn, :string, [required: true]},
            {:loss_fn_config, :map, [optional: true]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          data: [Datum.t()],
          loss_fn: LossFnType.t() | String.t(),
          loss_fn_config: map() | nil
        }
end

defimpl Jason.Encoder, for: Tinkex.Types.ForwardBackwardInput do
  alias Tinkex.SchemaCodec
  alias Tinkex.Types.LossFnType

  def encode(input, opts) do
    %{
      data: input.data,
      loss_fn: normalize_loss_fn(input.loss_fn),
      loss_fn_config: input.loss_fn_config
    }
    |> SchemaCodec.encode_map()
    |> Jason.Encode.map(opts)
  end

  defp normalize_loss_fn(loss_fn) when is_atom(loss_fn),
    do: LossFnType.to_string(loss_fn)

  defp normalize_loss_fn(loss_fn), do: loss_fn
end
