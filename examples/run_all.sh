#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

EXAMPLES=(
  "sampling_basic.exs"
  "training_loop.exs"
  "sessions_management.exs"
  "checkpoints_management.exs"
  "checkpoint_download.exs"
  "async_client_creation.exs"
  "cli_run_text.exs"
  "cli_run_prompt_file.exs"
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

  printf '\n==> Running %s\n' "$script_path"
  mix run "$script_path"
done
