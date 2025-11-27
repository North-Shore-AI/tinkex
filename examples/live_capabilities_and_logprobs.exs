alias Tinkex.API.Service
alias Tinkex.Config
alias Tinkex.Error
alias Tinkex.ServiceClient
alias Tinkex.SamplingClient
alias Tinkex.Types.ModelInput

api_key = System.fetch_env!("TINKER_API_KEY")
base_url = System.get_env("TINKER_BASE_URL")
base_model = System.get_env("TINKER_BASE_MODEL") || "meta-llama/Llama-3.1-8B"
prompt = System.get_env("TINKER_PROMPT") || "Hello from Tinkex!"

{:ok, _} = Application.ensure_all_started(:tinkex)

config_opts =
  [api_key: api_key]
  |> then(fn opts -> if base_url, do: Keyword.put(opts, :base_url, base_url), else: opts end)

config = Config.new(config_opts)

IO.puts("== Server capabilities ==")

case Service.get_server_capabilities(config: config) do
  {:ok, resp} ->
    models =
      case resp.supported_models do
        [] -> "[none reported]"
        models -> Enum.join(models, ", ")
      end

    IO.puts("Supported models: #{models}")

  {:error, %Error{} = error} ->
    IO.puts("Capabilities error: #{Error.format(error)}")
end

IO.puts("\n== Health check ==")

case Service.health_check(config: config) do
  {:ok, resp} ->
    IO.puts("Health: #{resp.status}")

  {:error, %Error{} = error} ->
    IO.puts("Health check failed: #{Error.format(error)}")
end

IO.puts("\n== Compute prompt logprobs ==")

with {:ok, service} <- ServiceClient.start_link(config: config),
     {:ok, sampler} <-
       ServiceClient.create_sampling_client(service,
         base_model: base_model,
         sampling_client_id: 0
       ),
     {:ok, model_input} <- ModelInput.from_text(prompt, model_name: base_model),
     {:ok, task} <- SamplingClient.compute_logprobs(sampler, model_input),
     {:ok, logprobs} <- Task.await(task, 30_000) do
  IO.puts("Prompt: #{prompt}")
  IO.puts("Logprobs: #{inspect(logprobs)}")
  GenServer.stop(sampler)
  GenServer.stop(service)
else
  {:error, {:invalid_prompt, _} = reason} ->
    IO.puts("Prompt encoding failed: #{inspect(reason)}")

  {:error, %Error{} = error} ->
    IO.puts("Logprobs failed: #{Error.format(error)}")

  other ->
    IO.puts("Unexpected error: #{inspect(other)}")
end
