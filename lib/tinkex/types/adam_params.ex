defmodule Tinkex.Types.AdamParams do
  @moduledoc """
  Adam optimizer parameters.

  Mirrors Python tinker.types.AdamParams.

  IMPORTANT: Defaults match Python SDK exactly:
  - learning_rate: 0.0001
  - beta1: 0.9
  - beta2: 0.95 (NOT 0.999!)
  - eps: 1.0e-12 (NOT 1e-8!)
  """

  @derive {Jason.Encoder, only: [:learning_rate, :beta1, :beta2, :eps]}
  defstruct learning_rate: 0.0001,
            beta1: 0.9,
            beta2: 0.95,
            eps: 1.0e-12

  @type t :: %__MODULE__{
          learning_rate: float(),
          beta1: float(),
          beta2: float(),
          eps: float()
        }

  @doc """
  Create AdamParams with validation.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts \\ []) do
    with {:ok, lr} <- validate_learning_rate(Keyword.get(opts, :learning_rate, 0.0001)),
         {:ok, b1} <- validate_beta(Keyword.get(opts, :beta1, 0.9), "beta1"),
         {:ok, b2} <- validate_beta(Keyword.get(opts, :beta2, 0.95), "beta2"),
         {:ok, eps} <- validate_epsilon(Keyword.get(opts, :eps, 1.0e-12)) do
      {:ok,
       %__MODULE__{
         learning_rate: lr,
         beta1: b1,
         beta2: b2,
         eps: eps
       }}
    end
  end

  defp validate_learning_rate(lr) when is_number(lr) and lr > 0, do: {:ok, lr / 1}
  defp validate_learning_rate(_), do: {:error, "learning_rate must be positive number"}

  defp validate_beta(b, _name) when is_number(b) and b >= 0 and b < 1, do: {:ok, b / 1}
  defp validate_beta(_, name), do: {:error, "#{name} must be in [0, 1)"}

  defp validate_epsilon(eps) when is_number(eps) and eps > 0, do: {:ok, eps / 1}
  defp validate_epsilon(_), do: {:error, "eps must be positive number"}
end
