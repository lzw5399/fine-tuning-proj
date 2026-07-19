#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
ACTION="${1:-up}"

read_env_value() {
  local key="$1"
  local fallback="$2"
  local current_value="${!key:-}"
  local file_value=""

  if [[ -n "$current_value" ]]; then
    printf '%s' "$current_value"
    return
  fi

  if [[ -f "$ENV_FILE" ]]; then
    file_value="$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE")"
    file_value="${file_value%$'\r'}"
    if [[ "$file_value" == \"*\" || "$file_value" == \'*\' ]]; then
      file_value="${file_value:1:${#file_value}-2}"
    fi
  fi

  printf '%s' "${file_value:-$fallback}"
}

compose_args=(-p qwen-vllm -f compose.vllm.yaml)
if [[ -f "$ENV_FILE" ]]; then
  compose_args=(--env-file "$ENV_FILE" "${compose_args[@]}")
fi

require_compose() {
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    printf 'Docker Compose is required.\n' >&2
    exit 127
  fi
}

validate_adapter() {
  local output_dir
  local lora_dir
  local adapter_dir
  local adapter_config
  local adapter_base_model
  local adapter_rank
  local base_model
  local max_lora_rank

  output_dir="$(read_env_value OUTPUT_DIR "${REPO_ROOT}/output")"
  lora_dir="$(read_env_value VLLM_LORA_DIR qwen25-3b-dpo-lora)"

  case "$lora_dir" in
    /*|..|../*|*/..|*/../*)
      printf 'VLLM_LORA_DIR must be a relative directory inside OUTPUT_DIR: %s\n' "$lora_dir" >&2
      exit 2
      ;;
  esac

  if [[ "$output_dir" != /* ]]; then
    output_dir="${REPO_ROOT}/${output_dir#./}"
  fi
  adapter_dir="${output_dir%/}/${lora_dir}"

  for required_file in adapter_config.json adapter_model.safetensors; do
    if [[ ! -f "${adapter_dir}/${required_file}" ]]; then
      printf 'Required LoRA file is missing: %s\n' "${adapter_dir}/${required_file}" >&2
      printf 'Complete DPO training or point VLLM_LORA_DIR at a valid Adapter before serving.\n' >&2
      exit 2
    fi
  done

  if ! command -v jq >/dev/null 2>&1; then
    printf 'jq is required to validate the LoRA Adapter.\n' >&2
    exit 127
  fi

  adapter_config="${adapter_dir}/adapter_config.json"
  if ! jq -e '.peft_type == "LORA"' "$adapter_config" >/dev/null; then
    printf 'Adapter is not declared as PEFT LoRA: %s\n' "$adapter_config" >&2
    exit 2
  fi

  adapter_base_model="$(jq -er '.base_model_name_or_path | select(type == "string" and length > 0)' "$adapter_config")"
  adapter_rank="$(jq -er '.r | select(type == "number")' "$adapter_config")"
  base_model="$(read_env_value VLLM_BASE_MODEL Qwen/Qwen2.5-3B-Instruct)"
  max_lora_rank="$(read_env_value VLLM_MAX_LORA_RANK 8)"

  if [[ "$adapter_base_model" != "$base_model" ]]; then
    printf 'Adapter base model (%s) does not match VLLM_BASE_MODEL (%s).\n' \
      "$adapter_base_model" "$base_model" >&2
    exit 2
  fi

  if [[ ! "$adapter_rank" =~ ^[0-9]+$ ]] || [[ ! "$max_lora_rank" =~ ^[0-9]+$ ]] || \
    ((adapter_rank > max_lora_rank)); then
    printf 'Adapter rank %s exceeds VLLM_MAX_LORA_RANK %s.\n' \
      "$adapter_rank" "$max_lora_rank" >&2
    exit 2
  fi
}

ensure_training_stopped() {
  local running_training_containers
  local training_compose_args=(-p qwen-sft -f compose.train.yaml)

  if [[ -f "$ENV_FILE" ]]; then
    training_compose_args=(--env-file "$ENV_FILE" "${training_compose_args[@]}")
  fi

  running_training_containers="$(docker compose "${training_compose_args[@]}" ps --all --status running -q)"
  if [[ -n "$running_training_containers" ]]; then
    printf 'Training containers are still running; stop them before starting vLLM.\n' >&2
    printf 'Use make webui-down and confirm no make train-sft/train-dpo job is active.\n' >&2
    exit 2
  fi
}

cd "$REPO_ROOT"

case "$ACTION" in
  up)
    require_compose
    validate_adapter
    ensure_training_stopped
    exec docker compose "${compose_args[@]}" up -d vllm
    ;;
  check)
    validate_adapter
    printf 'LoRA Adapter validation passed.\n'
    ;;
  down)
    require_compose
    exec docker compose "${compose_args[@]}" stop vllm
    ;;
  logs)
    require_compose
    exec docker compose "${compose_args[@]}" logs -f vllm
    ;;
  ps)
    require_compose
    exec docker compose "${compose_args[@]}" ps vllm
    ;;
  models)
    vllm_bind_address="$(read_env_value VLLM_BIND_ADDRESS 127.0.0.1)"
    vllm_port="$(read_env_value VLLM_PORT 8000)"
    if [[ "$vllm_bind_address" == "0.0.0.0" ]]; then
      vllm_bind_address="127.0.0.1"
    fi
    exec curl --fail --silent --show-error \
      "http://${vllm_bind_address}:${vllm_port}/v1/models"
    ;;
  *)
    printf 'Usage: %s {check|up|down|logs|ps|models}\n' "$0" >&2
    exit 2
    ;;
esac
