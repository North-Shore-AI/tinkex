defmodule Tinkex.Types.TensorDtype do
  @moduledoc """
  Tensor data type.

  Mirrors Python tinker.types.TensorDtype.
  Wire format: `"int64"` | `"float32"`

  IMPORTANT: Only 2 types are supported by the backend.
  float64 and int32 are NOT supported.
  """

  @type t :: :int64 | :float32

  @doc """
  Parse wire format string to atom.
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("int64"), do: :int64
  def parse("float32"), do: :float32
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(:int64), do: "int64"
  def to_string(:float32), do: "float32"

  @doc """
  Convert Nx tensor type to TensorDtype.

  Performs aggressive casting to match Python SDK behavior:
  - float64 → float32 (downcast)
  - int32 → int64 (upcast)
  - unsigned → int64 (upcast)
  """
  @spec from_nx_type(tuple()) :: t()
  def from_nx_type({:f, 32}), do: :float32
  def from_nx_type({:f, 64}), do: :float32
  def from_nx_type({:s, 64}), do: :int64
  def from_nx_type({:s, 32}), do: :int64
  def from_nx_type({:u, _}), do: :int64

  @doc """
  Convert TensorDtype to Nx tensor type.
  """
  @spec to_nx_type(t()) :: tuple()
  def to_nx_type(:float32), do: {:f, 32}
  def to_nx_type(:int64), do: {:s, 64}
end
