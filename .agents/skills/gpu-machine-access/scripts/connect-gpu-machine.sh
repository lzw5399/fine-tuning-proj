#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_ENV_FILE="${GPU_MACHINE_ENV_FILE:-${SCRIPT_DIR}/../.gpu-machine.env}"

usage() {
  cat <<'EOF'
Usage: connect-gpu-machine.sh [REMOTE_COMMAND [ARG ...]]

Configure GPU_MACHINE_SSH_TARGET in ../.gpu-machine.env or the environment.
With no command, open an interactive login shell on the remote machine.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -f "$LOCAL_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_ENV_FILE"
  set +a
fi

SSH_TARGET="${GPU_MACHINE_SSH_TARGET:-}"
SSH_PORT="${GPU_MACHINE_SSH_PORT:-}"
REMOTE_DIR="${GPU_MACHINE_REMOTE_DIR:-}"
SSH_BIN="${GPU_MACHINE_SSH_BIN:-ssh}"

if [[ -z "$SSH_TARGET" ]]; then
  printf '%s\n' \
    "GPU_MACHINE_SSH_TARGET is not configured." \
    "Set it in $LOCAL_ENV_FILE or export it in the environment." >&2
  exit 2
fi

if [[ -n "$SSH_PORT" ]]; then
  if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || ((SSH_PORT < 1 || SSH_PORT > 65535)); then
    printf 'GPU_MACHINE_SSH_PORT must be an integer from 1 to 65535.\n' >&2
    exit 2
  fi
fi

build_remote_command() {
  local prefix=""
  local quoted_args=""

  if [[ -n "$REMOTE_DIR" ]]; then
    printf -v prefix 'cd %q && ' "$REMOTE_DIR"
  fi

  if [[ "$#" -eq 0 ]]; then
    # Expand SHELL on the remote host, not on the local machine.
    # shellcheck disable=SC2016
    printf '%sexec ${SHELL:-/bin/bash} -l' "$prefix"
    return
  fi

  if [[ "$#" -eq 1 ]]; then
    printf '%s%s' "$prefix" "$1"
    return
  fi

  printf -v quoted_args '%q ' "$@"
  printf '%s%s' "$prefix" "$quoted_args"
}

remote_command="$(build_remote_command "$@")"
ssh_args=(-- "$SSH_TARGET" "$remote_command")

if [[ -n "$SSH_PORT" ]]; then
  ssh_args=(-p "$SSH_PORT" "${ssh_args[@]}")
fi

if [[ "$#" -eq 0 ]]; then
  ssh_args=(-t "${ssh_args[@]}")
fi

if [[ -n "${GPU_MACHINE_SSH_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1; then
  export SSHPASS="$GPU_MACHINE_SSH_PASSWORD"
  exec sshpass -e "$SSH_BIN" "${ssh_args[@]}"
fi

exec "$SSH_BIN" "${ssh_args[@]}"
