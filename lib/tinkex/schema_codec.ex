defmodule Tinkex.SchemaCodec do
  @moduledoc """
  Shared helpers for Sinter-backed validation and JSON shaping.
  """

  alias Sinter.{JSON, NotGiven, Schema, Transform, Validator}

  @type converter ::
          module()
          | (term() -> term())
          | {:list, converter()}
          | {:map, converter()}

  @spec validate(Schema.t(), map(), keyword()) ::
          {:ok, map()} | {:error, [Sinter.Error.t()]}
  def validate(%Schema{} = schema, data, opts \\ []) do
    Validator.validate(schema, data, opts)
  end

  @spec validate!(Schema.t(), map(), keyword()) :: map()
  def validate!(%Schema{} = schema, data, opts \\ []) do
    Validator.validate!(schema, data, opts)
  end

  @spec decode_struct(Schema.t(), map(), t, keyword()) :: t when t: struct()
  def decode_struct(%Schema{} = schema, data, %_{} = struct_template, opts \\ []) do
    validation_opts = Keyword.take(opts, [:coerce, :strict, :path])
    struct_opts = Keyword.take(opts, [:converters])

    case validate(schema, data, validation_opts) do
      {:ok, validated} ->
        to_struct(struct_template, validated, struct_opts)

      {:error, errors} ->
        raise Sinter.ValidationError, errors: errors
    end
  end

  @spec to_struct(t, map(), keyword()) :: t when t: struct()
  def to_struct(%_{} = struct_template, data, opts \\ []) when is_map(data) do
    converters = Keyword.get(opts, :converters, %{})

    fields =
      struct_template
      |> Map.keys()
      |> Enum.reject(&(&1 == :__struct__))

    mapped =
      Enum.reduce(fields, %{}, fn field, acc ->
        key = Atom.to_string(field)

        if Map.has_key?(data, key) do
          value = Map.get(data, key)
          value = apply_converter(value, Map.get(converters, field))
          Map.put(acc, field, value)
        else
          acc
        end
      end)

    struct(struct_template, mapped)
  end

  @spec encode_map(term(), keyword()) :: term()
  def encode_map(data, opts \\ []) do
    Transform.transform(data, opts)
  end

  @spec encode_json(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode_json(data, opts \\ []) do
    JSON.encode(data, opts)
  end

  @spec encode_json!(term(), keyword()) :: String.t()
  def encode_json!(data, opts \\ []) do
    JSON.encode!(data, opts)
  end

  @spec omit_nil_fields(term(), [atom()]) :: term()
  def omit_nil_fields(data, fields) when is_list(fields) do
    Enum.reduce(fields, data, fn field, acc ->
      if Map.has_key?(acc, field) and is_nil(Map.get(acc, field)) do
        Map.put(acc, field, NotGiven.value())
      else
        acc
      end
    end)
  end

  defp apply_converter(value, nil), do: value
  defp apply_converter(nil, _converter), do: nil
  defp apply_converter(value, fun) when is_function(fun, 1), do: fun.(value)

  defp apply_converter(value, {:list, converter}) when is_list(value) do
    Enum.map(value, &apply_converter(&1, converter))
  end

  defp apply_converter(value, {:map, converter}) when is_map(value) do
    Map.new(value, fn {key, inner} -> {key, apply_converter(inner, converter)} end)
  end

  defp apply_converter(value, module) when is_atom(module) do
    cond do
      function_exported?(module, :from_json, 1) ->
        module.from_json(value)

      function_exported?(module, :from_map, 1) ->
        module.from_map(value)

      true ->
        value
    end
  end
end
