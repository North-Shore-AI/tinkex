defmodule Tinkex.Types.LossFnType do
  @moduledoc """
  Loss function type.

  Mirrors Python `tinker.types.LossFnType`.

  ## Supported Loss Functions

  - `:cross_entropy` - Standard cross-entropy loss
  - `:importance_sampling` - Importance-weighted sampling loss
  - `:ppo` - Proximal Policy Optimization loss
  - `:cispo` - Constrained Importance Sampling Policy Optimization loss
  - `:dro` - Distributionally Robust Optimization loss

  ## Wire Format

  String values: `"cross_entropy"` | `"importance_sampling"` | `"ppo"` | `"cispo"` | `"dro"`

  ## Examples

      iex> LossFnType.parse("cross_entropy")
      :cross_entropy

      iex> LossFnType.to_string(:ppo)
      "ppo"
  """

  @type t :: :cross_entropy | :importance_sampling | :ppo | :cispo | :dro

  @doc """
  List all valid loss function types.
  """
  @spec values() :: [t()]
  def values, do: [:cross_entropy, :importance_sampling, :ppo, :cispo, :dro]

  @doc """
  Parse wire format string to atom.

  ## Examples

      iex> LossFnType.parse("cross_entropy")
      :cross_entropy

      iex> LossFnType.parse("cispo")
      :cispo

      iex> LossFnType.parse("unknown")
      nil
  """
  @spec parse(String.t() | nil) :: t() | nil
  def parse("cross_entropy"), do: :cross_entropy
  def parse("importance_sampling"), do: :importance_sampling
  def parse("ppo"), do: :ppo
  def parse("cispo"), do: :cispo
  def parse("dro"), do: :dro
  def parse(_), do: nil

  @doc """
  Convert atom to wire format string.

  ## Examples

      iex> LossFnType.to_string(:cross_entropy)
      "cross_entropy"

      iex> LossFnType.to_string(:dro)
      "dro"
  """
  @spec to_string(t()) :: String.t()
  def to_string(:cross_entropy), do: "cross_entropy"
  def to_string(:importance_sampling), do: "importance_sampling"
  def to_string(:ppo), do: "ppo"
  def to_string(:cispo), do: "cispo"
  def to_string(:dro), do: "dro"
end
