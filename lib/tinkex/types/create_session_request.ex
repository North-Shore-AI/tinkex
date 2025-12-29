defmodule Tinkex.Types.CreateSessionRequest do
  @moduledoc """
  Request to create a new training session.

  Mirrors Python tinker.types.CreateSessionRequest.
  """

  alias Sinter.Schema

  @enforce_keys [:tags, :sdk_version]
  @derive {Jason.Encoder, only: [:tags, :user_metadata, :sdk_version, :type]}
  defstruct [:tags, :user_metadata, :sdk_version, type: "create_session"]

  @schema Schema.define([
            {:tags, {:array, :string}, [required: true]},
            {:user_metadata, :map, [optional: true]},
            {:sdk_version, :string, [required: true]},
            {:type, :string, [optional: true, default: "create_session"]}
          ])

  @doc """
  Returns the Sinter schema for validation.
  """
  @spec schema() :: Schema.t()
  def schema, do: @schema

  @type t :: %__MODULE__{
          tags: [String.t()],
          user_metadata: map() | nil,
          sdk_version: String.t(),
          type: String.t()
        }
end
