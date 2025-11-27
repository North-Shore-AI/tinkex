defmodule Tinkex.Examples.ModelInfoAndUnload do
  @moduledoc false

  @default_base_url "https://tinker.thinkingmachines.dev/services/tinker-prod"
  @default_model "meta-llama/Llama-3.1-8B"

  alias Tinkex.Error
  alias Tinkex.API.{Futures, Models, Service, Session}

  alias Tinkex.Types.{
    CreateModelRequest,
    CreateSessionRequest,
    FutureCompletedResponse,
    FutureFailedResponse,
    FuturePendingResponse,
    FutureRetrieveResponse,
    TryAgainResponse,
    GetInfoRequest,
    LoraConfig,
    UnloadModelRequest,
    UnloadModelResponse
  }

  def run do
    {:ok, _} = Application.ensure_all_started(:tinkex)

    api_key = fetch_env!("TINKER_API_KEY")
    base_url = System.get_env("TINKER_BASE_URL", @default_base_url)
    base_model = System.get_env("TINKER_BASE_MODEL", @default_model)

    IO.puts("[tinkex] base_url=#{base_url}")
    IO.puts("[tinkex] base_model=#{base_model}")

    config = Tinkex.Config.new(api_key: api_key, base_url: base_url)

    with {:ok, session_id} <- create_session(config),
         {:ok, model_id} <- create_model(session_id, base_model, config),
         {:ok, info} <- get_info(model_id, config),
         :ok <- print_info(info),
         :ok <- unload(model_id, config) do
      :ok
    else
      {:error, %Error{} = error} ->
        IO.puts(
          :stderr,
          "[tinkex] failed: #{Error.format(error)} status=#{inspect(error.status)}"
        )

        if error.data, do: IO.puts(:stderr, "[tinkex] error data: #{inspect(error.data)}")
        System.halt(1)

      {:error, other} ->
        IO.puts(:stderr, "[tinkex] unexpected error: #{inspect(other)}")
        System.halt(1)
    end
  end

  defp create_session(config) do
    case Session.create_typed(
           %CreateSessionRequest{tags: [], user_metadata: nil, sdk_version: "elixir-repro"},
           config: config
         ) do
      {:ok, session} ->
        IO.puts("[tinkex] created session_id=#{session.session_id}")
        {:ok, session.session_id}

      {:error, _} = error ->
        error
    end
  end

  defp create_model(session_id, base_model, config) do
    request = %CreateModelRequest{
      session_id: session_id,
      model_seq_id: 0,
      base_model: base_model,
      lora_config: %LoraConfig{}
    }

    case Service.create_model(request, config: config) do
      {:ok, %{"request_id" => request_id}} ->
        poll_create_model(request_id, config)

      {:ok, %{request_id: request_id}} ->
        poll_create_model(request_id, config)

      {:ok, %{"model_id" => model_id}} ->
        IO.puts("[tinkex] created model_id=#{model_id} (immediate)")
        {:ok, model_id}

      {:ok, %{model_id: model_id}} ->
        IO.puts("[tinkex] created model_id=#{model_id} (immediate)")
        {:ok, model_id}

      {:error, _} = error ->
        error
    end
  end

  defp poll_create_model(request_id, config),
    do: poll_loop(request_id, config, :create_model, 1, &Futures.retrieve/2)

  defp poll_loop(request_id, config, label, attempt, retrieve_fun) do
    IO.puts("[tinkex] poll ##{attempt} #{label} request_id=#{request_id}")

    case retrieve_fun.(%{request_id: request_id}, config: config) do
      {:ok, payload} ->
        payload
        |> FutureRetrieveResponse.from_json()
        |> handle_future_response(request_id, config, label, attempt, retrieve_fun)

      {:error, _} = error ->
        error
    end
  end

  defp get_info(model_id, config) do
    Models.get_info(%GetInfoRequest{model_id: model_id},
      config: config,
      telemetry_metadata: %{model_id: model_id}
    )
  end

  defp print_info(info) do
    IO.puts("[tinkex] model_id=#{info.model_id}")
    IO.puts("- model_name: #{info.model_data.model_name || "unknown"}")
    IO.puts("- arch: #{info.model_data.arch || "unknown"}")
    IO.puts("- tokenizer_id: #{info.model_data.tokenizer_id || "none"}")
    IO.puts("- is_lora: #{inspect(info.is_lora)}")
    IO.puts("- lora_rank: #{inspect(info.lora_rank)}")
    :ok
  end

  defp unload(model_id, config) do
    IO.puts("[tinkex] unload_model")

    case Models.unload_model(%UnloadModelRequest{model_id: model_id},
           config: config,
           telemetry_metadata: %{model_id: model_id}
         ) do
      {:ok, %{"request_id" => request_id}} ->
        poll_loop(request_id, config, :unload, 1, &Futures.retrieve/2)

      {:ok, %{request_id: request_id}} ->
        poll_loop(request_id, config, :unload, 1, &Futures.retrieve/2)

      {:ok, %UnloadModelResponse{} = unload} ->
        IO.puts("[tinkex] unload response: #{format_unload(unload)}")
        :ok

      {:ok, %{} = payload} ->
        IO.puts("[tinkex] unload response: #{format_unload(payload)}")
        :ok

      {:error, %Error{} = error} ->
        IO.puts(
          :stderr,
          "[tinkex] unload failed: #{Error.format(error)} status=#{inspect(error.status)}"
        )

        if error.data, do: IO.puts(:stderr, "[tinkex] error data: #{inspect(error.data)}")
        System.halt(1)
    end
  end

  defp handle_future_response(
         %FuturePendingResponse{},
         request_id,
         config,
         label,
         attempt,
         retrieve_fun
       ) do
    Process.sleep(1_000)
    poll_loop(request_id, config, label, attempt + 1, retrieve_fun)
  end

  defp handle_future_response(
         %FutureCompletedResponse{result: result},
         _request_id,
         _config,
         :create_model,
         _attempt,
         _retrieve_fun
       ) do
    case model_id_from_result(result) do
      nil ->
        {:error,
         Error.new(:validation, "unexpected future payload for create_model: #{inspect(result)}")}

      model_id ->
        IO.puts("[tinkex] created model_id=#{model_id}")
        {:ok, model_id}
    end
  end

  defp handle_future_response(
         %FutureCompletedResponse{result: result},
         _request_id,
         _config,
         :unload,
         _attempt,
         _retrieve_fun
       ) do
    IO.puts("[tinkex] unload response: #{format_unload(result)}")
    :ok
  end

  defp handle_future_response(
         %FutureFailedResponse{error: error},
         _request_id,
         _config,
         label,
         _attempt,
         _retrieve_fun
       ) do
    {:error, Error.new(:request_failed, "#{label} failed", data: error)}
  end

  defp handle_future_response(
         %TryAgainResponse{},
         request_id,
         config,
         label,
         attempt,
         retrieve_fun
       ) do
    Process.sleep(1_000)
    poll_loop(request_id, config, label, attempt + 1, retrieve_fun)
  end

  defp handle_future_response(other, _request_id, _config, label, _attempt, _retrieve_fun) do
    {:error, Error.new(:validation, "unexpected future payload for #{label}: #{inspect(other)}")}
  end

  defp model_id_from_result(%{"model_id" => model_id}), do: model_id
  defp model_id_from_result(%{model_id: model_id}), do: model_id
  defp model_id_from_result(%{"modelId" => model_id}), do: model_id
  defp model_id_from_result(%{modelId: model_id}), do: model_id
  defp model_id_from_result(_), do: nil

  defp format_unload(%UnloadModelResponse{} = response) do
    "#{response.model_id} (type: #{response.type || "unload_model"})"
  end

  defp format_unload(%{"model_id" => model_id} = response) do
    "#{model_id} (type: #{response["type"] || "unload_model"})"
  end

  defp format_unload(%{model_id: model_id} = response) do
    "#{model_id} (type: #{response[:type] || "unload_model"})"
  end

  defp fetch_env!(var) do
    case System.get_env(var) do
      nil ->
        IO.puts(:stderr, "Set #{var} to run this example")
        System.halt(1)

      value ->
        value
    end
  end

  @doc false
  def poll_loop_for_test(payload, label) do
    poll_loop("test-request", :test_config, label, 1, fn _, _ -> payload end)
  end
end

if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test do
  :ok
else
  Tinkex.Examples.ModelInfoAndUnload.run()
end
