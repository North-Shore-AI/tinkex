defmodule Tinkex.Generated.Types.TypeAliases do
  @moduledoc """
  TypeAliases type.
  """

  @type t :: term()

  @doc "Returns the Sinter type spec for this alias."
  @spec schema() :: Sinter.Types.type_spec()
  def schema do
    :any
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
