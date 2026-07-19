# SFT and DPO Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the repository from an SFT-only baseline to explicit, independently runnable SFT and DPO workflows.

**Architecture:** Keep the common LLaMA-Factory container and constrained training launcher. Add a dedicated DPO YAML whose trainable policy and frozen 4-bit reference both start from the SFT LoRA adapter, register a small ShareGPT ranking fixture, and expose separate Make targets while retaining `make train` as the backwards-compatible SFT default.

**Tech Stack:** LLaMA-Factory 0.9.6.dev0, Qwen2.5, QLoRA, DPO, YAML, JSONL, Bash, Make, jq.

---

### Task 1: Register a DPO preference fixture

**Files:**
- Create: `data/my_dpo.jsonl`
- Modify: `data/dataset_info.json`
- Modify: `.gitignore`

- [x] **Step 1: Add two JSONL preference pairs**

Each line must contain `system`, prompt-only `conversations`, one `chosen` assistant reply, and one `rejected` assistant reply.

- [x] **Step 2: Register the ranking dataset**

Add `my_dpo` with `file_name: my_dpo.jsonl`, `formatting: sharegpt`, `ranking: true`, and explicit `messages`, `chosen`, `rejected`, and `system` column mappings.

- [x] **Step 3: Validate the fixture**

Run:

```bash
jq -se 'length == 2 and all(.[]; has("conversations") and has("chosen") and has("rejected"))' data/my_dpo.jsonl
```

Expected: exit code 0.

### Task 2: Add an annotated DPO training configuration

**Files:**
- Create: `configs/dpo.yaml`

- [x] **Step 1: Configure SFT adapter initialization**

Use `model_name_or_path: Qwen/Qwen2.5-3B-Instruct` with `adapter_name_or_path: /workspace/output/qwen25-3b-sft-lora` for the trainable policy. Set `ref_model`, `ref_model_adapters`, and `ref_model_quantization_bit: 4` so the frozen reference is the same SFT policy rather than the bare base model.

- [x] **Step 2: Configure DPO and QLoRA**

Set `stage: dpo`, `pref_beta: 0.1`, `pref_loss: sigmoid`, 4-bit NF4 quantization, LoRA training, the `qwen` template, T4 FP16, and a separate `/workspace/output/qwen25-3b-dpo-lora` output directory. Comment every option.

- [x] **Step 3: Parse the YAML**

Run:

```bash
ruby -e 'require "yaml"; raise unless YAML.load_file("configs/dpo.yaml").is_a?(Hash)'
```

Expected: exit code 0.

### Task 3: Expose and document both workflows

**Files:**
- Modify: `Makefile`
- Modify: `scripts/validate.sh`
- Modify: `README.md`
- Modify: `data/README.md`

- [x] **Step 1: Add explicit training commands**

Add `train-sft` and `train-dpo` targets. Preserve `train` as the configurable backwards-compatible entry whose default remains `configs/sft.yaml`.

- [x] **Step 2: Extend static validation**

Parse `configs/dpo.yaml`; verify its stage, SFT adapter path, DPO dataset registration, ranking flag, and JSONL preference-pair structure.

- [x] **Step 3: Document the two-stage workflow**

Explain that SFT teaches desired behavior first, DPO then optimizes pairwise preferences from the SFT adapter; document data schemas, commands, output isolation, and the requirement that formal preference pairs be reviewed for quality.

- [x] **Step 4: Run repository checks**

Run targeted YAML, JSON, Bash, Make dry-run, stale-reference, and whitespace checks. Remove stale smoke-command references because `configs/sft-smoke.yaml` is no longer part of the repository. Expected: all checks pass.
