alias Tinkex.{Config, Error, ServiceClient, TrainingClient}
alias Tinkex.Types.{ImageChunk, ModelInput, SamplingParams}

config = Config.new()

# Choose a vision-capable model dynamically; override via TINKER_BASE_MODEL if desired.
{:ok, service} = ServiceClient.start_link(config: config)

caps =
  case ServiceClient.get_server_capabilities(service) do
    {:ok, caps} ->
      caps

    {:error, reason} ->
      IO.puts(
        :stderr,
        "Warning: failed to fetch capabilities (#{inspect(reason)}); falling back."
      )

      nil
  end

vision_model =
  caps
  |> case do
    nil ->
      nil

    %{supported_models: models} when is_list(models) ->
      models
      |> Enum.map(&((&1 && &1.model_name) || &1))
      |> Enum.filter(&is_binary/1)
      |> Enum.find(fn name ->
        down = String.downcase(name)

        String.contains?(down, "vision") or String.contains?(down, "vl") or
          String.contains?(down, "image") or
          String.contains?(down, "omni")
      end)
  end

base_model = System.get_env("TINKER_BASE_MODEL") || vision_model

expected_tokens = 64
checkpoint_cache_path = Path.join(["tmp", "checkpoints", "default.path"])
File.mkdir_p!(Path.dirname(checkpoint_cache_path))

IO.puts("== Multimodal sampling with expected_tokens")

cond do
  base_model ->
    IO.puts("Using vision-capable model: #{base_model}")

    image_bytes = File.read!("examples/assets/tiny.png")
    image_chunk = ImageChunk.new(image_bytes, :png, expected_tokens: expected_tokens)

    {:ok, text_input} =
      case ModelInput.from_text("A one-pixel image:", model_name: base_model) do
        {:ok, mi} -> {:ok, mi}
        {:error, error} -> raise "Failed to encode text with #{base_model}: #{inspect(error)}"
      end

    text_chunk = hd(text_input.chunks)

    model_input = %ModelInput{chunks: [text_chunk, image_chunk]}

    {:ok, sampler} = ServiceClient.create_sampling_client(service, base_model: base_model)

    params = %SamplingParams{max_tokens: 8, temperature: 0.7}

    case Tinkex.SamplingClient.sample(sampler, model_input, params) do
      {:ok, task} ->
        case Task.await(task, 60_000) do
          {:ok, response} ->
            IO.puts("Sampled #{length(response.sequences)} sequence(s) with image + text.")
            Enum.each(response.sequences, fn s -> IO.puts("- tokens: #{inspect(s.tokens)}") end)

          {:error, %Error{status: 400, data: %{"detail" => detail}}} ->
            IO.puts(:stderr, "Sampling failed: #{detail}")

            IO.puts(
              :stderr,
              "Server did not accept image input. If a vision-capable model is available, set TINKER_BASE_MODEL accordingly and rerun."
            )

          {:error, error} ->
            IO.puts(:stderr, "Sampling failed: #{inspect(error)}")
        end

      {:error, error} ->
        IO.puts(:stderr, "Sampling failed: #{inspect(error)}")
    end

  true ->
    IO.puts(
      "No vision-capable model advertised; skipping multimodal sampling. Set TINKER_BASE_MODEL to a vision-capable model to exercise image input."
    )
end

IO.puts("\n== Optimizer resume via ServiceClient helper")

{:ok, rest_client} = ServiceClient.create_rest_client(service)

checkpoint_path =
  System.get_env("TINKER_CHECKPOINT_PATH") ||
    if File.exists?(checkpoint_cache_path) do
      String.trim(File.read!(checkpoint_cache_path))
    else
      with {:ok, resp} <-
             Tinkex.RestClient.list_user_checkpoints(rest_client, limit: 1, offset: 0),
           [first | _] <- resp.checkpoints do
        first.tinker_path
      else
        _ -> nil
      end
    end

checkpoint_path =
  case checkpoint_path do
    nil ->
      IO.puts("No checkpoint found to resume; skipping optimizer restore.")
      nil

    path ->
      File.write!(checkpoint_cache_path, path)
      path
  end

if checkpoint_path do
  IO.puts("Restoring weights + optimizer from #{checkpoint_path} ...")

  case ServiceClient.create_training_client_from_state_with_optimizer(service, checkpoint_path) do
    {:ok, training} ->
      IO.puts("Training client ready. Unloading...")
      _ = TrainingClient.unload_model(training)
      GenServer.stop(training)

    {:error, reason} ->
      IO.puts(:stderr, "Resume failed: #{inspect(reason)}")
  end
end

IO.puts("""

CLI multi-delete (single confirmation):
  tinkex checkpoint delete tinker://run-1/weights/0001 tinker://run-2/weights/0002 --yes
""")
