defmodule Tinkex.Types.ParsedCheckpointTinkerPath do
  @moduledoc """
  Parsed representation of a checkpoint tinker path.

  Provides a reusable parser with consistent validation for CLI and REST helpers.
  """

  alias Tinkex.Error

  @type checkpoint_type :: String.t()

  @type t :: %__MODULE__{
          tinker_path: String.t(),
          training_run_id: String.t(),
          checkpoint_type: checkpoint_type(),
          checkpoint_id: String.t()
        }

  @enforce_keys [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]
  defstruct [:tinker_path, :training_run_id, :checkpoint_type, :checkpoint_id]

  @doc """
  Parse a tinker path into its components.
  """
  @spec from_tinker_path(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def from_tinker_path("tinker://" <> rest = tinker_path) do
    case String.split(rest, "/") do
      [run_id, raw_type, checkpoint_id] when run_id != "" and checkpoint_id != "" ->
        with {:ok, checkpoint_type} <- parse_checkpoint_type(raw_type) do
          {:ok,
           %__MODULE__{
             tinker_path: tinker_path,
             training_run_id: run_id,
             checkpoint_type: checkpoint_type,
             checkpoint_id: checkpoint_id
           }}
        end

      _ ->
        {:error, invalid_path_error(tinker_path)}
    end
  end

  def from_tinker_path(other) do
    {:error,
     Error.new(:validation, "Checkpoint path must start with tinker://, got: #{other}",
       category: :user
     )}
  end

  @doc """
  Convert the parsed checkpoint to the REST path segment (`weights/<id>` etc.).
  """
  @spec checkpoint_segment(t()) :: String.t()
  def checkpoint_segment(%__MODULE__{} = parsed) do
    type_segment =
      case parsed.checkpoint_type do
        "training" -> "weights"
        "sampler" -> "sampler_weights"
      end

    Path.join(type_segment, parsed.checkpoint_id)
  end

  defp parse_checkpoint_type("weights"), do: {:ok, "training"}
  defp parse_checkpoint_type("sampler_weights"), do: {:ok, "sampler"}

  defp parse_checkpoint_type(other) do
    {:error, Error.new(:validation, "Invalid checkpoint type in path: #{other}", category: :user)}
  end

  defp invalid_path_error(tinker_path) do
    Error.new(:validation, "Invalid checkpoint path: #{tinker_path}", category: :user)
  end
end
