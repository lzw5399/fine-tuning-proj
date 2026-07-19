# Qwen SFT / DPO 训练与 vLLM 部署仓库

本仓库是后续 LLaMA-Factory SFT/DPO 训练与 vLLM 部署的唯一基准。训练和推理使用相互独立的 Compose 项目；远端只保存模型缓存、真实数据、LoRA Adapter 和其他运行状态。

## 当前基线

- 模型：`Qwen/Qwen2.5-3B-Instruct`
- 方法：先进行 QLoRA SFT，再从 SFT Adapter 继续进行 QLoRA DPO
- 训练机器：单卡 Tesla T4 15 GB，使用 FP16，不使用 BF16
- LLaMA-Factory：远端审计版本 `0.9.6.dev0`
- PyTorch/CUDA：`2.6.0+cu124` / CUDA runtime 12.4
- Attention：明确使用 PyTorch SDPA；T4 不启用 FlashAttention 2
- 数值稳定性：量化训练启用 `upcast_layernorm: true`
- 基础镜像：通过 OCI digest 固定，不再跟随 `latest` 漂移
- bitsandbytes：固定为 `0.49.2`

远端旧部署与历史 smoke test 的证据记录在 [`docs/remote-baseline.md`](docs/remote-baseline.md)。

## 仓库结构

```text
.
├── compose.train.yaml              # LLaMA-Factory WebUI 与训练环境
├── compose.vllm.yaml               # 独立的 vLLM LoRA 推理服务
├── .dockerignore                   # 构建上下文仅允许 Dockerfile
├── docker/llamafactory/Dockerfile  # 固定训练镜像与依赖
├── configs/
│   ├── sft.yaml                    # 项目数据的正式 SFT 配置
│   └── dpo.yaml                    # 从 SFT Adapter 继续训练的 DPO 配置
├── data/
│   ├── dataset_info.json           # 项目数据集注册表
│   ├── my_sft.jsonl                # JSONL 格式的两条 SFT 样例
│   └── my_dpo.jsonl                # JSONL 格式的两条偏好对样例
├── scripts/
│   ├── train.sh                    # 受约束的训练入口
│   ├── serve-vllm.sh               # 校验 Adapter 后管理 vLLM
│   └── validate.sh                 # 非训练静态检查
└── Makefile                        # 稳定的日常命令
```

容器内路径保持稳定：

| 仓库或运行目录 | 容器路径 | 管理方式 |
| --- | --- | --- |
| `./configs` | `/workspace/configs` | Git 管理，只读挂载 |
| `${DATA_DIR}` | `/workspace/data` | 注册表进 Git，真实数据通常外置 |
| `${OUTPUT_DIR}` | `/workspace/output` | 训练时读写，vLLM 中只读 |
| `${HF_CACHE_DIR}` | `/root/.cache/huggingface` | 模型缓存，不进 Git |

## 初始化和检查

```bash
cp .env.example .env
make validate
```

`.env` 只保存非提交的本机/远端路径配置。默认 WebUI 只绑定 `127.0.0.1`；如果确实需要远程访问，应优先使用 SSH 隧道或带认证的反向代理，不要直接暴露到公网。

`.dockerignore` 将构建上下文限制为 Dockerfile，SSH 配置、数据、模型和输出不会发送到 Docker daemon。

## 训练阶段：LLaMA-Factory

```bash
make training-build
make webui-up
make webui-ps
make webui-logs
```

停止训练 WebUI：

```bash
make webui-down
```

旧命令 `make build/up/down/logs/ps` 仍映射到训练 Compose，便于兼容已有操作习惯。仓库命令显式使用训练项目名 `qwen-sft` 和推理项目名 `qwen-vllm`，即使旧 `.env` 仍包含 `COMPOSE_PROJECT_NAME` 也不会把两个阶段合并。

## SFT 与 DPO 训练流程

SFT 和 DPO 是两个顺序执行、输出隔离的阶段：

1. SFT 使用标准答案数据训练 LoRA Adapter，输出到 `/workspace/output/qwen25-3b-sft-lora`。
2. DPO 从该 SFT Adapter 加载可训练策略，并用加载同一 Adapter 的冻结 4-bit 模型作为 reference；随后使用 chosen/rejected 偏好对继续优化，输出到 `/workspace/output/qwen25-3b-dpo-lora`。

DPO 不是 SFT 的替代品。推荐先用高质量指令数据建立稳定的 SFT 能力，再用人工或可靠规则审核过的偏好对调整回答倾向。不要让 DPO 的 rejected 回答只包含明显无关或破坏性内容，否则模型可能学到表面特征而不是真实偏好。

DPO 会同时持有 policy 和 reference 两个 4-bit 3B 模型，并对 chosen/rejected 分支计算概率，显存和耗时均明显高于 SFT。Tesla T4 应从当前 batch size 1、1024 tokens 起步；若仍 OOM，应优先降低 `cutoff_len`，不要通过关闭 reference 来规避。

明确运行 SFT：

```bash
make train-sft
```

SFT 完成且 Adapter 目录存在后运行 DPO：

```bash
make train-dpo
```

`make train` 保持向后兼容，默认仍运行 `configs/sft.yaml`。

运行仓库内其他配置：

```bash
make train CONFIG=configs/example.yaml
```

训练通过 `docker compose run --rm --no-deps` 启动独立的一次性容器，不依赖 WebUI 是否正在运行。该命令会使用真实 GPU；执行前先用 `nvidia-smi` 确认机器没有其他训练任务。

## 部署阶段：vLLM

vLLM 使用独立的 [`compose.vllm.yaml`](compose.vllm.yaml)，不会自动启动 LLaMA-Factory。默认部署最终 DPO Adapter：

```text
Qwen/Qwen2.5-3B-Instruct
  + /opt/llm-training/output/qwen25-3b-dpo-lora
  = API 模型名 qwen-dpo
```

启动前必须确认 Adapter 目录至少包含：

```text
qwen25-3b-dpo-lora/
├── adapter_config.json
└── adapter_model.safetensors
```

启动服务：

```bash
make webui-down   # 单卡 T4 上先释放训练服务占用的 GPU
make serve-check  # 核对文件、LoRA 类型、基座模型和 rank
make serve-up
make serve-ps
make serve-logs
```

`make serve-up` 会重复执行 Adapter 预检，并在发现训练 Compose 仍有运行容器时拒绝启动。推理服务默认只监听 `127.0.0.1:8000`；远程访问应使用 SSH 隧道或带认证的反向代理，不要直接将无认证 API 暴露到公网。

查看 vLLM 暴露的模型：

```bash
make serve-models
```

调用 OpenAI 兼容接口：

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "qwen-dpo",
    "messages": [
      {"role": "user", "content": "如何检查 Linux 磁盘空间？"}
    ]
  }'
```

停止 vLLM，不影响训练 Compose：

```bash
make serve-down
```

如需临时部署 SFT Adapter，可在 `.env` 中改为：

```dotenv
VLLM_LORA_NAME=qwen-sft
VLLM_LORA_DIR=qwen25-3b-sft-lora
```

修改后模型 API 名称相应使用 `qwen-sft`。`VLLM_MAX_LORA_RANK` 必须不小于 Adapter 的 `r`；当前 SFT/DPO 均为 rank 8。vLLM 使用完整基座权重进行推理，训练时的 bitsandbytes 4-bit 加载设置不会自动继承到部署阶段。

## 接入真实数据

当前 `data/my_sft.jsonl` 只有两条结构样例，不能用于正式微调。接入真实数据时：

1. 将数据放入远端 `${DATA_DIR}`，不要把敏感或大型语料提交到 Git。
2. 在 `data/dataset_info.json` 注册数据文件与字段映射。
3. 在 `configs/sft.yaml` 更新 `dataset`。
4. 保留 `val_size: 0.1`，确保 10% 数据用于验证。
5. 根据训练集大小同步调整 `eval_steps` 与 `save_steps`，两者保持一致。
6. 先跑短程稳定性验证，确认没有 NaN、显存溢出和数据模板错误，再进行完整训练。

DPO 数据使用 `data/my_dpo.jsonl` 展示的 ShareGPT ranking 格式。每行是一组独立偏好数据：

```json
{"system":"系统提示","conversations":[{"from":"human","value":"用户问题"}],"chosen":{"from":"gpt","value":"偏好回答"},"rejected":{"from":"gpt","value":"较差回答"}}
```

在 `data/dataset_info.json` 中，DPO 数据集必须设置 `ranking: true` 并映射 `messages`、`chosen` 和 `rejected`。正式训练前应检查偏好方向是否一致、chosen/rejected 是否回答同一 prompt、是否存在重复或相互矛盾的偏好对，并为验证集按 prompt 去重，避免数据泄漏。

## 迁移远端旧部署

本次只建立了本地仓库基线，没有停止或修改远端容器。正式切换时建议：

1. 将本仓库 clone/pull 到远端固定目录。
2. 从 `.env.example` 创建远端 `.env`，保留现有 `/opt/vllm/hf-cache` 与 `/opt/llm-training/output`。
3. 确认没有训练任务后，在旧 `/opt/llamafactory-webui` Compose 项目中停止旧 WebUI。
4. 在本仓库执行 `make validate && make training-build && make webui-up`。
5. 用 `make webui-ps`、`make webui-logs` 和 `nvidia-smi` 验证训练环境。
6. 完成训练后停止训练 WebUI，执行 `make serve-up`，再用 `make serve-models` 和 `/v1/chat/completions` 验证推理服务。

切换前不要删除 `/opt/llm-training/output/qwen25-3b-sft-smoke`；其中保留了之前 smoke test 的 Adapter 与 Checkpoint。
