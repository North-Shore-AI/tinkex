defmodule Tinkex.Types.TensorDtype do
  @moduledoc """
  Tensor data type.

  Mirrors Python `tinker.types.TensorDtype`.
  Wire format: `"int64"` | `"float32"`

  ## Backend Limitations

  IMPORTANT: The Tinker backend only supports 2 dtypes:
  - `int64` - 64-bit signed integers
  - `float32` - 32-bit floating point

  Other types (float64, int32, unsigned) are NOT directly supported.

  ## Automatic Type Conversion

  When using `from_nx_type/1`, Nx tensor types are automatically converted
  to the supported backend types. This may cause precision loss or overflow:

  | Nx Type | Backend Type | Notes |
  |---------|--------------|-------|
  | `{:f, 32}` | float32 | Direct mapping |
  | `{:f, 64}` | float32 | **WARNING: Precision loss** - float64 downcast to float32 |
  | `{:s, 64}` | int64 | Direct mapping |
  | `{:s, 32}` | int64 | Safe upcast |
  | `{:u, N}` | int64 | Safe upcast for N <= 63, may overflow for large u64 values |

  ## Python SDK Parity

  This behavior matches the Python SDK, which also only supports int64 and float32.
  """

  require Logger

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

  Performs automatic type conversion to match backend-supported types.
  Emits warnings when precision loss may occur (e.g., float64 -> float32).

  ## Supported Conversions

  - `{:f, 32}` -> `:float32` (direct)
  - `{:f, 64}` -> `:float32` (downcast, **WARNING** emitted)
  - `{:s, 64}` -> `:int64` (direct)
  - `{:s, 32}` -> `:int64` (upcast)
  - `{:u, _}` -> `:int64` (upcast)

  ## Examples

      iex> TensorDtype.from_nx_type({:f, 32})
      :float32

      # Downcast with warning
      iex> TensorDtype.from_nx_type({:f, 64})
      :float32
      # WARNING: Downcasting float64 to float32 - precision loss may occur

  """
  @spec from_nx_type(tuple()) :: t()
  def from_nx_type({:f, 32}), do: :float32

  def from_nx_type({:f, 64}) do
    Logger.warning(
      "[Tinkex] Downcasting float64 to float32 - precision loss may occur. " <>
        "Backend only supports float32."
    )

    :float32
  end

  def from_nx_type({:s, 64}), do: :int64
  def from_nx_type({:s, 32}), do: :int64

  def from_nx_type({:u, bits}) when bits > 63 do
    Logger.warning(
      "[Tinkex] Converting u#{bits} to int64 - large values may overflow. " <>
        "Backend only supports int64."
    )

    :int64
  end

  def from_nx_type({:u, _}), do: :int64

  @doc """
  Convert Nx tensor type to TensorDtype without emitting warnings.

  Use this when you want to check the conversion without side effects.
  """
  @spec from_nx_type_quiet(tuple()) :: t()
  def from_nx_type_quiet({:f, 32}), do: :float32
  def from_nx_type_quiet({:f, 64}), do: :float32
  def from_nx_type_quiet({:s, 64}), do: :int64
  def from_nx_type_quiet({:s, 32}), do: :int64
  def from_nx_type_quiet({:u, _}), do: :int64

  @doc """
  Check if an Nx type requires conversion that may lose precision.

  Returns `{:downcast, reason}` if precision loss may occur,
  otherwise `:ok`.

  ## Examples

      iex> TensorDtype.check_precision_loss({:f, 32})
      :ok

      iex> TensorDtype.check_precision_loss({:f, 64})
      {:downcast, "float64 to float32 - precision loss may occur"}

  """
  @spec check_precision_loss(tuple()) :: :ok | {:downcast, String.t()}
  def check_precision_loss({:f, 32}), do: :ok

  def check_precision_loss({:f, 64}),
    do: {:downcast, "float64 to float32 - precision loss may occur"}

  def check_precision_loss({:s, 64}), do: :ok
  def check_precision_loss({:s, 32}), do: :ok

  def check_precision_loss({:u, bits}) when bits > 63 do
    {:downcast, "u#{bits} to int64 - large values may overflow"}
  end

  def check_precision_loss({:u, _}), do: :ok

  @doc """
  Convert TensorDtype to Nx tensor type.
  """
  @spec to_nx_type(t()) :: tuple()
  def to_nx_type(:float32), do: {:f, 32}
  def to_nx_type(:int64), do: {:s, 64}
end
