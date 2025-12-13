alias Tinkex.{Config, Error, ServiceClient, TrainingClient}
alias Tinkex.Types.{ImageChunk, ModelInput, SamplingParams}

config = Config.new()

preferred_vision_models = [
  "Qwen/Qwen3-VL-30B-A3B-Instruct",
  "Qwen/Qwen3-VL-235B-A22B-Instruct"
]

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

advertised_models =
  case caps do
    %{supported_models: models} when is_list(models) ->
      models
      |> Enum.map(&((&1 && &1.model_name) || &1))
      |> Enum.filter(&is_binary/1)

    _ ->
      []
  end

vision_model =
  Enum.find(preferred_vision_models, &(&1 in advertised_models)) ||
    Enum.find(advertised_models, fn name ->
      down = String.downcase(name)

      String.contains?(down, "vision") or String.contains?(down, "vl") or
        String.contains?(down, "image") or
        String.contains?(down, "omni")
    end)

base_model = System.get_env("TINKER_BASE_MODEL") || vision_model

image_path = System.get_env("TINKER_IMAGE_PATH") || "examples/assets/vision_sample.png"

image_format =
  case String.downcase(Path.extname(image_path)) do
    ".png" -> :png
    ".jpg" -> :jpeg
    ".jpeg" -> :jpeg
    other -> raise "Unsupported image extension #{inspect(other)} for #{image_path}"
  end

expected_tokens =
  case System.get_env("TINKER_IMAGE_EXPECTED_TOKENS") do
    nil ->
      nil

    raw ->
      case Integer.parse(String.trim(raw)) do
        {n, ""} when n >= 0 ->
          n

        _ ->
          raise "Invalid TINKER_IMAGE_EXPECTED_TOKENS=#{inspect(raw)} (expected a non-negative integer)"
      end
  end

image_chunk_opts =
  case expected_tokens do
    nil -> []
    n -> [expected_tokens: n]
  end

checkpoint_cache_path = Path.join(["tmp", "checkpoints", "default.path"])
File.mkdir_p!(Path.dirname(checkpoint_cache_path))

IO.puts("== Multimodal sampling (image + text)")

cond do
  base_model ->
    IO.puts("Using vision-capable model: #{base_model}")

    IO.puts(
      "Using image: #{image_path} (format=#{image_format} expected_tokens=#{inspect(expected_tokens)})"
    )

    image_bytes = File.read!(image_path)
    image_chunk = ImageChunk.new(image_bytes, image_format, image_chunk_opts)

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

            if is_binary(detail) and String.contains?(detail, "SDK version") do
              IO.puts(
                :stderr,
                "Tip: update Tinkex. This build reports Tinker SDK version #{Tinkex.Version.tinker_sdk()} to the backend."
              )
            end

            IO.puts(
              :stderr,
              "Server rejected the image input. Try a different PNG/JPEG via TINKER_IMAGE_PATH and (if set) unset TINKER_IMAGE_EXPECTED_TOKENS."
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
