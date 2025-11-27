# Model Info & Unload

Fetch active model metadata (tokenizer id, arch, LoRA flags) and explicitly unload a model to release resources.

> Note: As of this writing the production endpoint `POST /api/v1/unload_model` responds with HTTP 404. Client wiring is in place; server support is required.

## Why it matters
- `get_info` returns `model_data.tokenizer_id`, allowing server-driven tokenizer selection instead of heuristics.
- `unload_model` ends the session and frees GPU memory when you’re done training.

## Endpoints
- `POST /api/v1/get_info` – body `{model_id, type: "get_info"}`
- `POST /api/v1/unload_model` – body `{model_id, type: "unload_model"}` (currently 404 on prod)

## Quickstart (TrainingClient)

```elixir
config = Tinkex.Config.new(api_key: System.fetch_env!("TINKER_API_KEY"))
base_model = "meta-llama/Llama-3.1-8B"

{:ok, service} = Tinkex.ServiceClient.start_link(config: config)
{:ok, training} = Tinkex.ServiceClient.create_lora_training_client(service, base_model: base_model)

{:ok, info} = Tinkex.TrainingClient.get_info(training)
IO.inspect(info.model_data.tokenizer_id, label: "tokenizer_id")

# Server currently returns 404 here on prod; call succeeds once backend exposes the route
case Tinkex.TrainingClient.unload_model(training) do
  {:ok, resp} -> IO.inspect(resp, label: "unload response")
  {:error, err} -> IO.inspect(err, label: "unload error")
end
```

## Direct API usage (mirrors Python flow)

```elixir
config = Tinkex.Config.new(api_key: System.fetch_env!("TINKER_API_KEY"))

# 1) create session
{:ok, session} =
  Tinkex.API.Session.create_typed(
    %Tinkex.Types.CreateSessionRequest{tags: [], user_metadata: nil, sdk_version: "tinkex"},
    config: config
  )

# 2) create model (LoRA config required by server)
{:ok, create_future} =
  Tinkex.API.Service.create_model(
    %Tinkex.Types.CreateModelRequest{
      session_id: session.session_id,
      model_seq_id: 0,
      base_model: "meta-llama/Llama-3.1-8B",
      lora_config: %Tinkex.Types.LoraConfig{}
    },
    config: config
  )

# 3) poll future until model_id
{:ok, model_id} =
  case create_future do
    %{"request_id" => req} -> poll_model(req, config)
    %{request_id: req} -> poll_model(req, config)
    %{"model_id" => id} -> {:ok, id}
    %{model_id: id} -> {:ok, id}
  end

# 4) get_info
{:ok, info} =
  Tinkex.API.Models.get_info(%Tinkex.Types.GetInfoRequest{model_id: model_id},
    config: config
  )

IO.inspect(info.model_data, label: "model_data")

# 5) unload (currently 404 on prod)
Tinkex.API.Models.unload_model(%Tinkex.Types.UnloadModelRequest{model_id: model_id},
  config: config
)

defp poll_model(request_id, config) do
  case Tinkex.API.Futures.retrieve(%{request_id: request_id}, config: config) do
    {:ok, %{"status" => "completed", "result" => %{"model_id" => id}}} -> {:ok, id}
    {:ok, %{"status" => "pending"}} ->
      Process.sleep(1_000)
      poll_model(request_id, config)
    other -> {:error, other}
  end
end
```

## Runnable examples
- Elixir: `examples/model_info_and_unload.exs` (mirrors the Python flow; logs each step).
- Python: `tinker/repro_404_like_elixir.py` and `tinker/repro_404.py` (use `tinker==0.5.1`).

## Current status
- `get_info` works on prod and returns tokenizer_id and LoRA flags.
- `unload_model` is wired client-side but returns HTTP 404 on prod; backend change required. Use these repro scripts/logs to validate once the server exposes the route.
