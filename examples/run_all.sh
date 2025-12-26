#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

timestamp() {
  date +"%Y-%m-%d %H:%M:%S %Z"
}

format_duration() {
  local total_seconds=$1
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if [[ $hours -gt 0 ]]; then
    printf '%02d:%02d:%02d' "$hours" "$minutes" "$seconds"
  else
    printf '%02d:%02d' "$minutes" "$seconds"
  fi
}

EXAMPLES=(
  "sampling_basic.exs"
  "training_loop.exs"
  "custom_loss_training.exs"
  "forward_inference.exs"
  "structured_regularizers.exs"
  "structured_regularizers_live.exs"
  "sessions_management.exs"
  "checkpoints_management.exs"
  "weights_inspection.exs"
  "checkpoint_download.exs"
  "async_client_creation.exs"
  "cli_run_text.exs"
  "cli_run_prompt_file.exs"
  "metrics_live.exs"
  "telemetry_live.exs"
  "telemetry_reporter_demo.exs"
  "retry_and_capture.exs"
  "live_capabilities_and_logprobs.exs"
  "file_upload_multipart.exs"
  "adam_and_chunking_live.exs"
  "llama3_tokenizer_override_live.exs"
  "queue_reasons_and_sampling_throttling.exs"
  "multimodal_resume_and_cleanup.exs"
  "training_persistence_live.exs"
  "checkpoint_multi_delete_live.exs"
  "save_weights_and_sample.exs"
  "queue_state_observer_demo.exs"
  "recovery_simulated.exs"
  "recovery_live_injected.exs"
  "kimi_k2_sampling_live.exs"
  "model_info_and_unload.exs"
)

if [[ -z "${TINKER_API_KEY:-}" ]]; then
  echo "Error: TINKER_API_KEY must be set before running the examples." >&2
  exit 1
fi

for example in "${EXAMPLES[@]}"; do
  script_path="examples/${example}"
  if [[ ! -f "$script_path" ]]; then
    echo "Skipping missing example: $example" >&2
    continue
  fi

  start_epoch=$(date +%s)
  printf '\n==> Running %s [%s]\n' "$script_path" "$(timestamp)"
  if mix run "$script_path"; then
    status=0
  else
    status=$?
  fi
  end_epoch=$(date +%s)
  duration=$(format_duration $((end_epoch - start_epoch)))

  if [[ $status -eq 0 ]]; then
    printf '==> Finished %s [%s | %s]\n' "$script_path" "$(timestamp)" "$duration"
  else
    printf '==> Failed %s [%s | %s]\n' "$script_path" "$(timestamp)" "$duration" >&2
    exit "$status"
  fi
done
