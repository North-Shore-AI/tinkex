# Troubleshooting

Reference this guide when CLI or SDK calls fail or diverge from expectations. Most fixes involve configuration, backpressure handling, or local environment setup.

## Authentication or config errors

- **Missing API key/base URL**: `Tinkex.Config.new/1` raises or returns validation errors when `api_key`/`base_url` are absent. Set `TINKER_API_KEY` (and optionally `TINKER_BASE_URL`) or pass explicit options.
- **Non-default pool selection**: If you override `:base_url` without starting a matching Finch pool, requests fall back to Finch defaults. Use the same base URL configured in `Tinkex.Application` for production workloads, or provide a custom pool via `config :tinkex, :http_pool, MyPool`.
- **Session SDK version too old**: Some endpoints may reject requests (notably vision/image input) if the reported SDK version is too old. Tinkex reports the official Python Tinker SDK version configured in `mix.exs`; update to the latest Tinkex if you hit this.

## Vision and multimodal inputs

- **Asset is not a valid image**: The backend rejected the image bytes. Verify you are sending a real PNG/JPEG (and that `format` matches the file), try a different image, and avoid setting `expected_tokens` unless you know the correct value. The bundled example supports `TINKER_IMAGE_PATH` / `TINKER_IMAGE_EXPECTED_TOKENS`.

## Timeouts, queuing, or 429 responses

- **Long-running training steps**: Increase `:timeout` on `Tinkex.Config` or pass `:await_timeout` to client calls. Training requests are sent sequentially; enqueue fewer simultaneous batches to keep the GenServer responsive.
- **Queue backpressure**: Sampling and training futures emit telemetry `[:tinkex, :queue, :state_change]`. Attach `Tinkex.Telemetry.attach_logger/1` or a custom handler to watch for `:paused_rate_limit` / `:paused_capacity`.
- **HTTP 429**: The RateLimiter stores per-tenant backoff windows. You do not need to manually retry while a backoff is active—subsequent calls will sleep. When testing, lower concurrency or reuse the same `ServiceClient` to share limiter state.

## Tokenizer (NIF) issues

- **Compilation/ABI errors**: Ensure Rust toolchains and C toolchains are available; re-run `mix deps.compile tokenizers`.
- **Runtime crashes**: The ETS cache stores NIF handles; verify the same OS/CPU architecture used to build dependencies. If you suspect a bad cache entry, restart the BEAM and clear `_build`/`deps`.
- **Unexpected token IDs**: Confirm you are passing fully formatted text (chat templates are not inserted) and the correct model name. For Llama-3 variants, the SDK automatically swaps to `"thinkingmachineslabinc/meta-llama-3-tokenizer"`.
- **Kimi K2 tokenizers**: Kimi uses `tiktoken.model` + `tokenizer_config.json` (via `tiktoken_ex`), not a HuggingFace `tokenizer.json`. Ensure those files can be downloaded from HuggingFace or pass `tiktoken_model_path`/`tokenizer_config_path`.

## CLI failures

- **`--output` missing**: `tinkex checkpoint` requires `--output` to write metadata. Provide a path with write permissions.
- **Missing base model**: Both `run` and `checkpoint` expect `--base-model` (or `--model-path` for `run`). Validate the option spelling and casing.
- **Prompt file errors**: `--prompt-file` accepts plain text or a JSON array of token IDs. Confirm the file is readable and valid UTF-8/JSON.
- **EXLA errors**: EXLA is optional and is not started automatically. If you need EXLA-backed Nx operations, run via `mix run` / an OTP release and start `:exla` before calling `Nx.default_backend/1`.
- **Stuck or slow runs**: Pass `--http-timeout` / `--timeout` and monitor telemetry logs. Use `--json` to inspect raw server payloads when diagnosing errors.

## Comparing with the Python SDK

- Use the same base model, prompt text, sampling params (temperature, top_p, max_tokens), and seed (if supported) on both clients.
- Request logprobs (`prompt_logprobs` / `topk_prompt_logprobs`) to compare token-level probabilities. Expect similar, not identical, text output.
- If results diverge, verify tokenizer IDs match (`TrainingClient.get_info/1` when available) and that both clients point to the same `base_url`.

## Documentation build issues

`mix docs` relies on dev-only deps. Run it in a dev environment (not production releases) and ensure `ex_doc` is installed. If assets are missing, rebuild the escript or fetch deps again with `mix deps.get`.
