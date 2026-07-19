#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

bash -n scripts/train.sh scripts/validate.sh

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 -c 'import sys, yaml; values = [yaml.safe_load(open(path, encoding="utf-8")) for path in sys.argv[1:]]; assert all(isinstance(value, dict) for value in values)' \
    compose.yaml configs/sft-smoke.yaml configs/sft.yaml
elif command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; ARGV.each { |path| value = YAML.load_file(path); raise "#{path} must contain a mapping" unless value.is_a?(Hash) }' \
    compose.yaml configs/sft-smoke.yaml configs/sft.yaml
else
  printf 'Ruby or Python with PyYAML is required to validate YAML.\n' >&2
  exit 127
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required to validate dataset JSON.\n' >&2
  exit 127
fi

jq -e 'has("my_sft") and (.my_sft.file_name == "my_sft.jsonl")' data/dataset_info.json >/dev/null
jq -se 'length == 2 and all(.[]; has("system") and has("conversations"))' data/my_sft.jsonl >/dev/null

grep -Eq '^dataset: alpaca_zh_demo$' configs/sft-smoke.yaml
[[ "$(grep -hE '^val_size: 0\.1$' configs/sft-smoke.yaml configs/sft.yaml | wc -l | tr -d ' ')" -eq 2 ]]
[[ "$(grep -hE '^eval_strategy: steps$' configs/sft-smoke.yaml configs/sft.yaml | wc -l | tr -d ' ')" -eq 2 ]]
[[ "$(grep -hE '^flash_attn: sdpa$' configs/sft-smoke.yaml configs/sft.yaml | wc -l | tr -d ' ')" -eq 2 ]]
[[ "$(grep -hE '^upcast_layernorm: true$' configs/sft-smoke.yaml configs/sft.yaml | wc -l | tr -d ' ')" -eq 2 ]]

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config --quiet
else
  printf 'Docker Compose not found; skipped Compose semantic validation.\n' >&2
fi

printf 'Repository configuration validation passed.\n'
