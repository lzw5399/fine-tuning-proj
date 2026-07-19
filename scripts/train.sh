#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="${1:-configs/sft.yaml}"
CONFIG_PATH="${CONFIG_PATH#./}"

case "$CONFIG_PATH" in
  /*|*../*|../*|*'/..')
    printf 'Config path must stay inside the repository: %s\n' "$CONFIG_PATH" >&2
    exit 2
    ;;
  configs/*.yaml|configs/*.yml)
    ;;
  *)
    printf 'Config path must be configs/<name>.yaml: %s\n' "$CONFIG_PATH" >&2
    exit 2
    ;;
esac

if [[ ! -f "${REPO_ROOT}/${CONFIG_PATH}" ]]; then
  printf 'Config file does not exist: %s\n' "$CONFIG_PATH" >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  printf 'Docker Compose is required.\n' >&2
  exit 127
fi

cd "$REPO_ROOT"
exec docker compose run --rm --no-deps llamafactory \
  llamafactory-cli train "/workspace/${CONFIG_PATH}"
