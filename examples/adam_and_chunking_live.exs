defmodule Tinkex.Examples.AdamAndChunkingLive do
  @moduledoc false

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"
  @await_timeout 60_000
  @default_preview_count 1_025
  @default_run_count 128

  alias Tinkex.Types.{AdamParams, Datum, ModelInput}

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)
    preview_count = env_int("TINKER_CHUNK_COUNT", @default_preview_count)
    run_count = env_int("TINKER_RUN_COUNT", @default_run_count)

    IO.puts("""
    ----------------------------------------
    Base URL: #{base_url}
    Base model: #{base_model}
    Preview count: #{preview_count} (max chunk len is 1024; >1024 shows multi-chunk)
    Run count: #{run_count} (trimmed subset sent to the API)
    ----------------------------------------
    """)

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, service} <- Tinkex.ServiceClient.start_link(config: config),
         {:ok, training} <-
           Tinkex.ServiceClient.create_lora_training_client(service, base_model,
             lora_config: %Tinkex.Types.LoraConfig{rank: 8}
           ) do
      data = build_dataset(preview_count)

      log_chunking_preview(data)

      run_data =
        data
        |> Enum.take(run_count)

      IO.puts(
        "[info] sending #{length(run_data)} datum(s) to the API (use TINKER_RUN_COUNT to adjust)"
      )

      fb_output =
        run_forward_backward(training, run_data)

      IO.puts(
        "[ok] forward_backward returned #{length(fb_output.loss_fn_outputs)} chunk result(s) for run data"
      )

      adam =
        AdamParams.new(
          learning_rate: 2.0e-4,
          weight_decay: 0.01,
          grad_clip_norm: 1.0
        )
        |> unwrap!()

      IO.puts("[step] running optim_step with weight_decay=0.01, grad_clip_norm=1.0...")
      {:ok, opt_task} = Tinkex.TrainingClient.optim_step(training, adam)
      {:ok, optim_output} = Task.await(opt_task, @await_timeout)
      IO.inspect(optim_output.metrics, label: "[ok] optim_step metrics")

      IO.puts("[done] AdamParams and byte-based chunking demo complete")
    end
  end

  defp build_dataset(count) do
    Enum.map(1..count, fn idx ->
      tokens = [idx]

      Datum.new(%{
        model_input: ModelInput.from_ints(tokens),
        loss_fn_inputs: %{
          target_tokens: tokens,
          weights: List.duplicate(1.0, length(tokens))
        }
      })
    end)
  end

  defp log_chunking_preview(data) do
    chunks = Tinkex.TrainingClient.DataProcessor.chunk_data(data)
    sizes = Enum.map(chunks, &length/1)
    IO.puts("[info] chunk preview (byte-based): #{inspect(sizes)}")
  end

  defp run_forward_backward(training, run_data) do
    task =
      start_task(
        Tinkex.TrainingClient.forward_backward(training, run_data, :cross_entropy),
        "forward_backward"
      )

    await_task(task, "forward_backward")
  end

  defp unwrap!({:ok, value}), do: value
  defp unwrap!(other), do: raise("expected {:ok, value}, got #{inspect(other)}")

  defp start_task({:ok, task}, _label), do: task

  defp await_task(task, label) do
    case Task.await(task, @await_timeout) do
      {:ok, result} ->
        result

      {:error, %Tinkex.Error{type: :api_connection} = error} ->
        IO.puts(
          :stderr,
          "[warn] #{label} hit a connection limit (often HTTP/2 window). Try lowering TINKER_RUN_COUNT (default #{@default_run_count}) or TINKER_CHUNK_COUNT."
        )

        halt("#{label} failed: #{inspect(error)}")

      {:error, error} ->
        halt("#{label} failed: #{inspect(error)}")
    end
  end

  defp fetch_env!(key) do
    System.get_env(key) || halt("Missing required env #{key}")
  end

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      str -> String.to_integer(str)
    end
  rescue
    _ -> default
  end

  defp halt(message) do
    IO.puts(:stderr, "[error] #{message}")
    System.halt(1)
  end
end

Tinkex.Examples.AdamAndChunkingLive.run()
