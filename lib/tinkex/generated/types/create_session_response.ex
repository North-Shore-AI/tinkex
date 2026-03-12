defmodule Tinkex.Generated.Types.CreateSessionResponse do
  @moduledoc """
  CreateSessionResponse type.
  """

  defstruct [:error_message, :info_message, :session_id, :warning_message]

  @type t :: %__MODULE__{
          error_message: term() | nil,
          info_message: term() | nil,
          session_id: term(),
          warning_message: term() | nil
        }

  @doc "Returns the Sinter schema for this type."
  @spec schema() :: Sinter.Schema.t()
  def schema do
    Sinter.Schema.define([
      {:error_message, :any, [optional: true]},
      {:info_message, :any, [optional: true]},
      {:session_id, :any, [required: true]},
      {:warning_message, :any, [optional: true]}
    ])
  end

  @doc "Decode a map into a Tinkex.Generated.Types.CreateSessionResponse struct."
  @spec decode(map()) :: {:ok, t()} | {:error, term()}
  def decode(data) when is_map(data) do
    with {:ok, validated} <- Sinter.Validator.validate(schema(), data) do
      {:ok,
       %__MODULE__{
         error_message: validated["error_message"],
         info_message: validated["info_message"],
         session_id: validated["session_id"],
         warning_message: validated["warning_message"]
       }}
    end
  end

  def decode(_), do: {:error, :invalid_input}

  @doc "Encode a Tinkex.Generated.Types.CreateSessionResponse struct into a map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = struct) do
    %{
      "error_message" => struct.error_message,
      "info_message" => struct.info_message,
      "session_id" => struct.session_id,
      "warning_message" => struct.warning_message
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.CreateSessionResponse from a map."
  @spec from_map(map()) :: t()
  def from_map(data) when is_map(data) do
    struct(__MODULE__, atomize_keys(data))
  end

  @doc "Convert to a map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "Create a new Tinkex.Generated.Types.CreateSessionResponse."
  @spec new(keyword() | map()) :: t()
  def new(attrs \\ [])
  def new(attrs) when is_list(attrs), do: struct(__MODULE__, attrs)
  def new(attrs) when is_map(attrs), do: from_map(attrs)

  defp atomize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end
end
