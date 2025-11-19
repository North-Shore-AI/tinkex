defmodule Tinkex.Types.LossFnType do
  @moduledoc """
  Loss function type.

  Mirrors Python tinker.types.LossFnType.
  Wire format: `"cross_entropy"` | `"importance_sampling"` | `"ppo"`
  """

  @type t :: :cross_entropy | :importance_sampling | :ppo

  @doc """
  Parse wire format string to atom.
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("cross_entropy"), do: :cross_entropy
  def parse("importance_sampling"), do: :importance_sampling
  def parse("ppo"), do: :ppo
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(:cross_entropy), do: "cross_entropy"
  def to_string(:importance_sampling), do: "importance_sampling"
  def to_string(:ppo), do: "ppo"
end
