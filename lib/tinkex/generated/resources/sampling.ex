defmodule Tinkex.Generated.Sampling do
  @moduledoc """
  Sampling resource endpoints.

  This module provides functions for interacting with sampling resources.
  """

  defstruct [:context]

  @type t :: %__MODULE__{context: Pristine.Core.Context.t()}

  @doc "Create a resource module instance with the given client."
  @spec with_client(Tinkex.Generated.Client.t()) :: t()
  def with_client(%{context: context}) do
    %__MODULE__{context: context}
  end

  @doc """
  ## Parameters
    * `sampler_id` - Required parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.get_sampler(sampler_id, [])
  """
  @spec get_sampler(t(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.GetSamplerResponse.t()} | {:error, Pristine.Error.t()}
  def get_sampler(%__MODULE__{context: context}, sampler_id, opts \\ []) do
    payload =
      %{}

    path_params = %{
      "sampler_id" => sampler_id
    }

    opts = merge_path_params(opts, path_params)

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "get_sampler",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `prompt` - Required parameter.
    * `sampling_params` - Required parameter.
    * `opts` - Optional parameters:
      * `:base_model` - Optional parameter.
      * `:model_path` - Optional parameter.
      * `:num_samples` - Optional parameter.
      * `:prompt_logprobs` - Optional parameter.
      * `:sampling_session_id` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:topk_prompt_logprobs` - Optional parameter.
      * `:type` - Optional parameter.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.stream_sample(prompt, sampling_params, [])
  """
  @spec stream_sample(t(), term(), term(), keyword()) ::
          {:ok, term()} | {:error, Pristine.Error.t()}
  def stream_sample(%__MODULE__{context: context}, prompt, sampling_params, opts \\ []) do
    payload =
      %{
        "prompt" => prompt,
        "sampling_params" => sampling_params
      }
      |> maybe_put("base_model", Keyword.get(opts, :base_model))
      |> maybe_put("model_path", Keyword.get(opts, :model_path))
      |> maybe_put("num_samples", Keyword.get(opts, :num_samples))
      |> maybe_put("prompt_logprobs", Keyword.get(opts, :prompt_logprobs))
      |> maybe_put("sampling_session_id", Keyword.get(opts, :sampling_session_id))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("topk_prompt_logprobs", Keyword.get(opts, :topk_prompt_logprobs))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "stream_sample",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `prompt` - Required parameter.
    * `sampling_params` - Required parameter.
    * `opts` - Optional parameters:
      * `:base_model` - Optional parameter.
      * `:model_path` - Optional parameter.
      * `:num_samples` - Optional parameter.
      * `:prompt_logprobs` - Optional parameter.
      * `:sampling_session_id` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:topk_prompt_logprobs` - Optional parameter.
      * `:type` - Optional parameter.
  ## Returns
    * `{:ok, Pristine.Core.StreamResponse.t()} | {:error, Pristine.Error.t()}`
  ## Example
      resource.stream_sample_stream(prompt, sampling_params, [])
  """
  @spec stream_sample_stream(t(), term(), term(), keyword()) ::
          {:ok, Pristine.Core.StreamResponse.t()} | {:error, Pristine.Error.t()}
  def stream_sample_stream(%__MODULE__{context: context}, prompt, sampling_params, opts \\ []) do
    payload =
      %{
        "prompt" => prompt,
        "sampling_params" => sampling_params
      }
      |> maybe_put("base_model", Keyword.get(opts, :base_model))
      |> maybe_put("model_path", Keyword.get(opts, :model_path))
      |> maybe_put("num_samples", Keyword.get(opts, :num_samples))
      |> maybe_put("prompt_logprobs", Keyword.get(opts, :prompt_logprobs))
      |> maybe_put("sampling_session_id", Keyword.get(opts, :sampling_session_id))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("topk_prompt_logprobs", Keyword.get(opts, :topk_prompt_logprobs))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute_stream(
      Tinkex.Generated.Client.manifest(),
      "stream_sample",
      payload,
      context,
      opts
    )
  end

  @doc """
  ## Parameters
    * `prompt` - Required parameter.
    * `sampling_params` - Required parameter.
    * `opts` - Optional parameters:
      * `:base_model` - Optional parameter.
      * `:model_path` - Optional parameter.
      * `:num_samples` - Optional parameter.
      * `:prompt_logprobs` - Optional parameter.
      * `:sampling_session_id` - Optional parameter.
      * `:seq_id` - Optional parameter.
      * `:topk_prompt_logprobs` - Optional parameter.
      * `:type` - Optional parameter.
      * `:idempotency_key` - Idempotency key override.
  ## Returns
    * `{:ok, response} | {:error, Pristine.Error.t()}`
  ## Example
      resource.asample(prompt, sampling_params, [])
  """
  @spec asample(t(), term(), term(), keyword()) ::
          {:ok, Tinkex.Generated.Types.SampleResponse.t()} | {:error, Pristine.Error.t()}
  def asample(%__MODULE__{context: context}, prompt, sampling_params, opts \\ []) do
    payload =
      %{
        "prompt" => prompt,
        "sampling_params" => sampling_params
      }
      |> maybe_put("base_model", Keyword.get(opts, :base_model))
      |> maybe_put("model_path", Keyword.get(opts, :model_path))
      |> maybe_put("num_samples", Keyword.get(opts, :num_samples))
      |> maybe_put("prompt_logprobs", Keyword.get(opts, :prompt_logprobs))
      |> maybe_put("sampling_session_id", Keyword.get(opts, :sampling_session_id))
      |> maybe_put("seq_id", Keyword.get(opts, :seq_id))
      |> maybe_put("topk_prompt_logprobs", Keyword.get(opts, :topk_prompt_logprobs))
      |> maybe_put("type", Keyword.get(opts, :type))

    Pristine.Runtime.execute(
      Tinkex.Generated.Client.manifest(),
      "asample",
      payload,
      context,
      opts
    )
  end

  defp merge_path_params(opts, path_params) do
    existing = Keyword.get(opts, :path_params, %{})
    Keyword.put(opts, :path_params, Map.merge(existing, path_params))
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, Sinter.NotGiven), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)
end
