defmodule Tinkex.Generated.Types.GenericMap do
  @moduledoc """
  GenericMap type.
  """

  @type t :: map()

  @doc "Returns the Sinter type spec for this alias."
  @spec schema() :: Sinter.Types.type_spec()
  def schema do
    :map
  end

  @doc "Decode a value for this alias type."
  @spec decode(term()) :: {:ok, t()} | {:error, term()}
  def decode(value) do
    Sinter.Types.validate(schema(), value)
  end

  @doc "Encode a value for this alias type."
  @spec encode(t()) :: term()
  def encode(value), do: value
end
