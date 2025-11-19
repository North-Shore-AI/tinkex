defmodule Tinkex.Types.RequestErrorCategory do
  @moduledoc """
  Request error category.

  Mirrors Python tinker.types.request_error_category.RequestErrorCategory.
  Wire format uses lowercase strings: `"unknown"` | `"server"` | `"user"`
  (Python StrEnum.auto() returns lowercase in Python 3.11+)

  Parser is case-insensitive for defensive robustness.
  """

  @type t :: :unknown | :server | :user

  @doc """
  Parse wire format string to atom (case-insensitive).

  Defaults to :unknown for unrecognized values.
  """
  @spec parse(String.t() | nil) :: t()
  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "server" -> :server
      "user" -> :user
      "unknown" -> :unknown
      _ -> :unknown
    end
  end

  def parse(_), do: :unknown

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(:unknown), do: "unknown"
  def to_string(:server), do: "server"
  def to_string(:user), do: "user"

  @doc """
  Check if error category is retryable.

  User errors are not retryable; server and unknown errors are.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(:user), do: false
  def retryable?(:server), do: true
  def retryable?(:unknown), do: true
end
