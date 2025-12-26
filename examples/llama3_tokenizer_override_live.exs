defmodule Tinkex.Examples.Llama3TokenizerOverrideLive do
  @moduledoc """
  Live Llama-3 tokenizer override demo: runs sampling, then encodes/decodes
  with the overridden tokenizer (`thinkingmachineslabinc/meta-llama-3-tokenizer`).
  Requires only `TINKER_API_KEY`.
  """

  @base_model "meta-llama/Llama-3.1-8B"
  @await_timeout :infinity

  alias Tinkex.{Config, Error, ServiceClient, Tokenizer}
  alias Tinkex.Types.{ModelInput, SamplingParams}

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    prompt_text = "Demonstrate Llama-3 tokenizer override in one sentence."

    with {:ok, config} <- build_config(),
         {:ok, service} <- ServiceClient.start_link(config: config),
         {:ok, sampler} <- ServiceClient.create_sampling_client(service, base_model: @base_model),
         {:ok, model_input} <- ModelInput.from_text(prompt_text, model_name: @base_model),
         {:ok, response} <- sample(sampler, model_input),
         {:ok, encode_ids} <- Tokenizer.encode(prompt_text, @base_model),
         {:ok, decode_text} <- decode_first_sequence(response, @base_model),
         :ok <- shutdown([sampler, service]) do
      IO.puts("Tokenizer ID: #{Tokenizer.get_tokenizer_id(@base_model)}")
      IO.puts("Encoded prompt token IDs (#{length(encode_ids)}): #{inspect(encode_ids)}")
      IO.puts("Decoded first sequence: #{decode_text}")
    else
      {:error, %Error{} = error} ->
        IO.puts(:stderr, "Error: #{Error.format(error)}")
        if error.data, do: IO.inspect(error.data, label: "data")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp build_config do
    {:ok, Config.new()}
  rescue
    e -> {:error, e}
  end

  defp sample(sampler, model_input) do
    params = %SamplingParams{max_tokens: 16, temperature: 0.7}

    case Tinkex.SamplingClient.sample(sampler, model_input, params) do
      {:ok, task} ->
        case Task.await(task, @await_timeout) do
          {:ok, response} -> {:ok, response}
          {:error, %Error{} = error} -> {:error, error}
          other -> {:error, other}
        end
    end
  end

  defp decode_first_sequence(response, model_name) do
    case response.sequences do
      [first | _] ->
        ids = first.tokens || []
        Tokenizer.decode(ids, model_name)

      _ ->
        {:error, Error.new(:validation, "No sequences returned from sampling")}
    end
  end

  defp shutdown(pids) do
    Enum.each(pids, fn pid ->
      if is_pid(pid), do: Process.exit(pid, :normal)
    end)

    :ok
  end
end

Tinkex.Examples.Llama3TokenizerOverrideLive.run()
