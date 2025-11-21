# API Reference Overview

This guide summarizes the public modules that make up the Tinkex SDK. Full typespecs and function docs live in the generated ExDoc site.

## ServiceClient

- `start_link/1` – boots a session using `Tinkex.Config` (pulling API key/base URL from env if not supplied).
- `create_lora_training_client/2` – spawns a TrainingClient; pass `:base_model`, optional `:lora_config`, and user metadata.
- `create_sampling_client/2` – spawns a SamplingClient for a base model or an existing model path.
- `create_sampling_client_async/2` – async variant that returns a `Task.t()` for concurrent bootstrapping.
- `create_rest_client/1` – returns a `Tinkex.RestClient` for session/checkpoint REST calls.

Each ServiceClient maintains sequencing counters for per-model operations; Training/Sampling clients inherit the session/config so multi-tenant callers can keep pools isolated by config.

## RestClient

- `list_sessions/2` – paginate through active session IDs.
- `get_session/2` – fetch training run IDs and sampler IDs for a session.
- `list_user_checkpoints/2` – paginate through the caller's checkpoints (with cursor metadata).
- `list_checkpoints/2` – list checkpoints for a specific training run.
- `get_checkpoint_archive_url/2` – return a signed download URL for a checkpoint.
- `delete_checkpoint/2` – delete a checkpoint by `tinker://` path.

All methods return typed structs (`ListSessionsResponse`, `GetSessionResponse`, `CheckpointsListResponse`, `CheckpointArchiveUrlResponse`) to match the Python SDK wire format.

## TrainingClient

- Requests are sent sequentially inside the GenServer; polling futures runs in Tasks for concurrency.
- `forward_backward/4` – accepts a list of `Tinkex.Types.Datum` structs and a loss function (atom or string). Automatically chunks input (128 items or 500k tokens) and reduces metrics via `Tinkex.MetricsReduction`.
- `optim_step/3` – performs an optimizer step with `%Tinkex.Types.AdamParams{}`.
- `save_weights_for_sampler/2` – persists weights and optionally specifies `:path` and `:sampling_session_seq_id` for deterministic naming. Returns a Task whose result may include a polling future.
- `get_info/1` – stubbed until the info endpoint is wired; used by tokenizer resolution when available.
- `create_sampling_client_async/3` – create a SamplingClient from a checkpoint path in a Task for concurrent fan-out.

Training clients are stateful per model (`model_seq_id`) and reuse the HTTP pool configured in `Tinkex.Config`.

## SamplingClient

- `sample/4` – submits a sampling request and returns a Task. Accepts `num_samples`, `prompt_logprobs`, `topk_prompt_logprobs`, `:timeout`, and `:await_timeout` options.
- `create_async/2` – convenience wrapper over `ServiceClient.create_sampling_client_async/2` when you already have a service PID.
- Reads config and rate limiter state from ETS for lock-free concurrent sampling (fan out Tasks freely).
- Honors `Tinkex.RateLimiter` backoff; a 429 response sets a backoff window, while successful calls clear it.
- Accepts prompts as `%Tinkex.Types.ModelInput{}` (use `ModelInput.from_text/2` for plain text).

## CheckpointDownload

- `download/3` – fetch and extract a checkpoint archive for a given `tinker://` path.
- Supports `:output_dir`, `:force` overwrite, and `:progress` callbacks (`fn downloaded, total -> ... end`).
- Cleans up temporary archives and returns the extraction directory for downstream processing.

## Tokenizers and Types

- `Tinkex.Tokenizer.encode/3` / `decode/3` wrap the HuggingFace `tokenizers` NIF and cache handles in ETS. `encode_text/3` is an alias that matches Python naming.
- `Tinkex.Types.ModelInput.from_text/2` and `from_text!/2` turn formatted strings into model inputs; chat templates are intentionally out of scope.
- Common request/response structs (`SamplingParams`, `Datum`, `ForwardBackwardRequest`, etc.) are JSON-encodable to match the Python SDK wire format.

## Config and Telemetry

- `Tinkex.Config.new/1` builds a struct using runtime options with env/app fallbacks. Validate once and reuse to keep hot paths fast.
- `Tinkex.Telemetry.attach_logger/1` registers a quick console logger; attach your own handler to `[:tinkex, :http, :request, ...]` and `[:tinkex, :queue, :state_change]` for metrics/tracing.

## Behavioral parity with the Python SDK

Use the same base model, prompt, sampling params, and (if supported by the server) a seed to compare outputs. Expect **similar logprobs and structure**, not bit-identical text, because sampling is stochastic and floating-point math can diverge slightly.

```elixir
# Elixir (sampling)
model = "meta-llama/Llama-3.1-8B"
prompt = "Summarize: Tinkex ports the Python SDK."
params = %Tinkex.Types.SamplingParams{max_tokens: 64, temperature: 0.7, top_p: 0.9, seed: 123}

{:ok, service} = Tinkex.ServiceClient.start_link(config: Tinkex.Config.new(api_key: System.fetch_env!("TINKER_API_KEY")))
{:ok, sampler} = Tinkex.ServiceClient.create_sampling_client(service, base_model: model)
{:ok, prompt_input} = Tinkex.Types.ModelInput.from_text(prompt, model_name: model)
{:ok, task} = Tinkex.SamplingClient.sample(sampler, prompt_input, params, num_samples: 1, prompt_logprobs: true)
{:ok, elixir_resp} = Task.await(task)
```

```python
# Python (sampling)
from tinker import ServiceClient

client = ServiceClient(api_key=os.environ["TINKER_API_KEY"])
sampler = client.create_sampling_client(base_model=model)
resp = sampler.sample(
    prompt=prompt,
    sampling_params={"max_tokens": 64, "temperature": 0.7, "top_p": 0.9, "seed": 123},
    prompt_logprobs=True,
)
```

Compare per-token logprobs and stop reasons rather than raw text. If seeds are not honored by the backend, hold `temperature`, `top_p`, and `max_tokens` constant and look for similar response shapes (number of tokens, finishing reason, and approximate probabilities).
