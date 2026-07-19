# Separate vLLM Serving Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a production-oriented vLLM LoRA deployment path that is operationally separate from SFT/DPO training.

**Architecture:** Rename the existing training stack to `compose.train.yaml`, where SFT and DPO remain separate sequential LLaMA-Factory configs. Add `compose.vllm.yaml` as an independent serving stack that mounts the shared Hugging Face cache and training output read-only, then serves the final DPO LoRA Adapter on top of the exact Qwen base model.

**Tech Stack:** Docker Compose, vLLM OpenAI-compatible server, Qwen2.5, PEFT LoRA, Bash, Make.

---

### Task 1: Separate training and serving Compose stacks

**Files:**
- Move: `compose.yaml` to `compose.train.yaml`
- Create: `compose.vllm.yaml`
- Modify: `.env.example`

- [x] **Step 1: Preserve the training stack under an explicit filename**

Keep the existing `llamafactory` build, WebUI, cache/data/output mounts, and GPU reservation unchanged in `compose.train.yaml`.

- [x] **Step 2: Define the independent vLLM stack**

Use the explicit Compose project name `qwen-vllm`, image `vllm/vllm-openai:v0.8.5`, bind `${VLLM_BIND_ADDRESS:-127.0.0.1}:${VLLM_PORT:-8000}`, mount `${HF_CACHE_DIR}` read-write and `${OUTPUT_DIR}` read-only, and launch the base model with `--enable-lora --lora-modules qwen-dpo=/workspace/output/qwen25-3b-dpo-lora --max-lora-rank 8 --dtype half --max-model-len 4096`. Keep training commands explicitly pinned to project `qwen-sft`.

- [x] **Step 3: Document environment controls**

Add explicit `VLLM_IMAGE`, `VLLM_BASE_MODEL`, `VLLM_LORA_NAME`, `VLLM_LORA_DIR`, rank, model length, memory utilization, bind address, and port variables to `.env.example`.

### Task 2: Add guarded serving operations

**Files:**
- Create: `scripts/serve-vllm.sh`
- Modify: `scripts/train.sh`
- Modify: `Makefile`

- [x] **Step 1: Validate the Adapter before startup**

The serving script must reject absolute/traversing `VLLM_LORA_DIR` values; require `adapter_config.json` and `adapter_model.safetensors`; verify PEFT type, base model, and rank; and refuse startup while training containers are running. Expose this independently as `make serve-check`.

- [x] **Step 2: Point training commands to the training stack**

Run LLaMA-Factory with `docker compose -f compose.train.yaml run --rm --no-deps llamafactory`.

- [x] **Step 3: Expose separate Make commands**

Provide `training-build`, `webui-up/down/logs/ps`, `train-sft`, `train-dpo`, and independent `serve-up/down/logs/ps/models` targets. Keep `build`, `up`, `down`, `logs`, and `ps` as backwards-compatible training aliases.

### Task 3: Validate and document deployment

**Files:**
- Modify: `scripts/validate.sh`
- Modify: `README.md`

- [x] **Step 1: Validate both stacks statically**

Parse both Compose files, run `docker compose -f <file> --env-file .env.example config --quiet`, ShellCheck both scripts, and assert that training mounts output read-write while serving mounts it read-only.

- [x] **Step 2: Document lifecycle and API use**

Explain the sequential SFT → DPO → vLLM flow, required Adapter files, GPU exclusivity, loopback binding, service commands, `/v1/models`, and `/v1/chat/completions` request using model name `qwen-dpo`.

- [x] **Step 3: Run final checks**

Run `make validate`, Make dry-runs, startup-script failure tests with a temporary incomplete Adapter, ShellCheck, and `git diff --check`. Expected: all checks pass without starting a GPU container.
