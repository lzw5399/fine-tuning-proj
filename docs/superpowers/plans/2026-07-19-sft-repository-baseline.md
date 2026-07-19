# SFT Repository Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this repository into the source of truth for the tested LLaMA-Factory Docker deployment, SFT configurations, dataset registration, and repeatable training commands.

**Architecture:** Keep Git-managed deployment and training inputs in the repository while mounting model caches, large datasets, and outputs as runtime state. Pin the currently tested LLaMA-Factory base image and bitsandbytes version, preserve `/workspace` as the stable container contract, and use the image-bundled Chinese Alpaca demo only for a bounded smoke test. Formal training continues to use the project-owned `/workspace/data` catalog.

**Tech Stack:** Docker Compose, LLaMA-Factory 0.9.6.dev0, Qwen2.5-3B-Instruct, bitsandbytes QLoRA, Bash, Make, YAML, JSON.

---

### Task 1: Establish repository layout and runtime boundaries

**Files:**
- Modify: `.gitignore`
- Create: `.dockerignore`
- Create: `.env.example`
- Create: `data/README.md`

- [ ] **Step 1: Protect credentials and generated artifacts**

Extend `.gitignore` so local environment files, Hugging Face caches, model weights, checkpoints, logs, and output directories cannot be committed. Keep `.env.example`, `data/dataset_info.json`, and the small `data/my_sft.json` fixture trackable.

- [ ] **Step 2: Define non-secret deployment inputs**

Create `.env.example` with the tested base-image digest, bitsandbytes `0.49.2`, loopback WebUI binding, `/opt/vllm/hf-cache`, and configurable data/output directories. Do not add credentials.

- [ ] **Step 3: Restrict the Docker build context**

Create `.dockerignore` with a deny-by-default policy that allows only `docker/llamafactory/Dockerfile`. This prevents the ignored local SSH configuration, datasets, caches, and outputs from being sent to the Docker daemon.

- [ ] **Step 4: Document data ownership**

Explain that `data/my_sft.json` is only a two-record schema fixture, real datasets should be mounted or provisioned outside Git, and the smoke configuration uses the pinned image's `/app/data/alpaca_zh_demo.json`.

- [ ] **Step 5: Verify ignore behavior**

Run:

```bash
git check-ignore output/test.safetensors .env data/private.json
git check-ignore data/dataset_info.json data/my_sft.json || true
```

Expected: runtime files are ignored; the two project fixtures are not ignored.

### Task 2: Synchronize and pin the container deployment

**Files:**
- Create: `docker/llamafactory/Dockerfile`
- Create: `compose.yaml`

- [ ] **Step 1: Pin the tested training image**

Create a Dockerfile based on:

```dockerfile
ARG LLAMAFACTORY_BASE_IMAGE=hiyouga/llamafactory@sha256:cde9745570861693a8a0e7da6aa1a1fadde7c728b8ceeb189191ddc3a3a8d3f3
FROM ${LLAMAFACTORY_BASE_IMAGE}
ARG BITSANDBYTES_VERSION=0.49.2
RUN pip install --no-cache-dir "bitsandbytes==${BITSANDBYTES_VERSION}"
WORKDIR /app
CMD ["llamafactory-cli", "webui"]
```

- [ ] **Step 2: Make repository paths the container contract**

Create `compose.yaml` with a `llamafactory` service, NVIDIA device reservation, `ipc: host`, configurable cache/data/output mounts, read-only Git-managed configs, and `/workspace/configs`, `/workspace/data`, `/workspace/output` destinations. Bind Gradio to `127.0.0.1` by default instead of exposing it publicly.

- [ ] **Step 3: Validate Compose interpolation**

Run:

```bash
docker compose --env-file .env.example config --quiet
```

Expected: exit status 0 without starting a container.

### Task 3: Synchronize datasets and add 10% evaluation

**Files:**
- Move: `sft-smoke.yaml` to `configs/sft-smoke.yaml`
- Create: `configs/sft.yaml`
- Create: `data/dataset_info.json`
- Create: `data/my_sft.json`

- [ ] **Step 1: Register the existing project fixture**

Copy the remote `my_sft` ShareGPT registration and two-record fixture into `data/`. Exclude the stale `my_dpo` registration because its referenced file does not exist.

- [ ] **Step 2: Configure the official Chinese smoke dataset**

Set the smoke dataset contract to:

```yaml
dataset_dir: /app/data
dataset: alpaca_zh_demo
max_samples: 100
val_size: 0.1
per_device_eval_batch_size: 1
eval_strategy: steps
eval_steps: 10
```

The pinned image contains 1000 official demo records; limiting to 100 keeps the smoke run bounded and yields approximately 90 training and 10 validation records.

- [ ] **Step 3: Align evaluation and checkpoint cadence**

Use `save_strategy: steps`, `save_steps: 10`, `load_best_model_at_end: true`, `metric_for_best_model: eval_loss`, and `greater_is_better: false`. Keep T4-safe FP16 QLoRA settings and run one smoke epoch.

- [ ] **Step 4: Add formal SFT configuration**

Synchronize the remote `sft.yaml`, retain `/workspace/data/my_sft`, add `val_size: 0.1`, evaluate and save every 100 steps, and keep its batch-1/gradient-accumulation-16 QLoRA setup. Document that the two-record fixture must be replaced before formal training.

- [ ] **Step 5: Parse YAML and JSON**

Run:

```bash
ruby -e 'require "yaml"; %w[configs/sft-smoke.yaml configs/sft.yaml compose.yaml].each { |f| YAML.load_file(f) }'
jq empty data/dataset_info.json data/my_sft.json
```

Expected: both commands exit 0.

### Task 4: Add repeatable deployment and training commands

**Files:**
- Create: `scripts/train.sh`
- Create: `scripts/validate.sh`
- Create: `Makefile`

- [ ] **Step 1: Add a guarded training entry point**

Create `scripts/train.sh` that accepts a repository-relative config, rejects absolute paths and `..`, confirms the file exists under `configs/`, maps it to `/workspace/configs/<name>`, and runs:

```bash
docker compose run --rm --no-deps llamafactory \
  llamafactory-cli train /workspace/configs/<name>
```

- [ ] **Step 2: Add static validation**

Create `scripts/validate.sh` to run Bash syntax checks, YAML parsing, JSON parsing, required-key assertions, and `docker compose config --quiet` when Docker Compose is available.

- [ ] **Step 3: Expose stable Make targets**

Add `help`, `validate`, `build`, `up`, `down`, `logs`, `ps`, `smoke`, and `train` targets. `smoke` uses `configs/sft-smoke.yaml`; `train` defaults to `configs/sft.yaml` but accepts `CONFIG=configs/<file>.yaml`.

- [ ] **Step 4: Validate scripts without training**

Run:

```bash
bash -n scripts/train.sh scripts/validate.sh
make help
make validate
```

Expected: syntax passes, help lists all targets, and validation does not start a training workload.

### Task 5: Document migration from the current remote layout

**Files:**
- Create: `README.md`
- Create: `docs/remote-baseline.md`

- [ ] **Step 1: Record the audited baseline**

Document the remote host-to-container mappings, source file hashes, tested package versions, existing smoke output, and the fact that runtime outputs are intentionally not synchronized into Git.

- [ ] **Step 2: Document the repository-first workflow**

Explain setup, `.env` creation, build/WebUI commands, smoke and formal training commands, 10% validation behavior, custom dataset registration, and how to migrate the remote deployment after reviewing local changes.

- [ ] **Step 3: Run the complete non-training verification**

Run:

```bash
./scripts/validate.sh
git status --short
git diff --check
```

Expected: validation succeeds, the intended repository files are visible, and there are no whitespace errors. Do not start a training job or change the remote deployment as part of this task.

- [ ] **Step 4: Commit after user review**

```bash
git add .gitignore .dockerignore .env.example Makefile README.md compose.yaml configs data docker docs scripts
git commit -m "feat: establish reproducible SFT workflow"
```

Expected: one reviewable baseline commit after the user explicitly approves committing.
