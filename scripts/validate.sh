#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

bash -n scripts/train.sh scripts/validate.sh

yaml_files=(compose.yaml configs/sft.yaml configs/dpo.yaml)

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 -c 'import sys, yaml; values = [yaml.safe_load(open(path, encoding="utf-8")) for path in sys.argv[1:]]; assert all(isinstance(value, dict) for value in values)' \
    "${yaml_files[@]}"
elif command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; ARGV.each { |path| value = YAML.load_file(path); raise "#{path} must contain a mapping" unless value.is_a?(Hash) }' \
    "${yaml_files[@]}"
else
  printf 'Ruby or Python with PyYAML is required to validate YAML.\n' >&2
  exit 127
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required to validate dataset JSON.\n' >&2
  exit 127
fi

jq -e '
  (.my_sft.file_name == "my_sft.jsonl") and
  (.my_dpo.file_name == "my_dpo.jsonl") and
  (.my_dpo.formatting == "sharegpt") and
  (.my_dpo.ranking == true) and
  (.my_dpo.columns.messages == "conversations") and
  (.my_dpo.columns.chosen == "chosen") and
  (.my_dpo.columns.rejected == "rejected")
' data/dataset_info.json >/dev/null
jq -se 'length == 2 and all(.[]; has("system") and has("conversations"))' data/my_sft.jsonl >/dev/null
jq -se '
  length == 2 and all(.[];
    has("system") and
    (.conversations | type == "array" and length > 0) and
    (.chosen.from == "gpt") and (.chosen.value | type == "string" and length > 0) and
    (.rejected.from == "gpt") and (.rejected.value | type == "string" and length > 0)
  )
' data/my_dpo.jsonl >/dev/null

grep -Eq '^stage: sft$' configs/sft.yaml
grep -Eq '^dataset: my_sft$' configs/sft.yaml
grep -Eq '^stage: dpo$' configs/dpo.yaml
grep -Eq '^dataset: my_dpo$' configs/dpo.yaml
grep -Eq '^adapter_name_or_path: /workspace/output/qwen25-3b-sft-lora$' configs/dpo.yaml
grep -Eq '^ref_model: Qwen/Qwen2.5-3B-Instruct$' configs/dpo.yaml
grep -Eq '^ref_model_adapters: /workspace/output/qwen25-3b-sft-lora$' configs/dpo.yaml
grep -Eq '^ref_model_quantization_bit: 4$' configs/dpo.yaml
for config_path in configs/sft.yaml configs/dpo.yaml; do
  grep -Eq '^val_size: 0\.1$' "$config_path"
  grep -Eq '^eval_strategy: steps$' "$config_path"
  grep -Eq '^flash_attn: sdpa$' "$config_path"
  grep -Eq '^upcast_layernorm: true$' "$config_path"
done

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose --env-file .env.example config --quiet
else
  printf 'Docker Compose not found; skipped Compose semantic validation.\n' >&2
fi

printf 'Repository configuration validation passed.\n'
