# Qwen SFT / DPO 训练仓库

本仓库是后续 LLaMA-Factory 部署、SFT/DPO 数据注册、训练配置和执行命令的唯一基准。远端只保存模型缓存、真实数据和训练输出等运行状态；需要调整配置时，应先修改并审查本仓库，再部署到远端。

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
├── compose.yaml                    # WebUI 与训练容器定义
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
│   └── validate.sh                 # 非训练静态检查
└── Makefile                        # 稳定的日常命令
```

容器内路径保持稳定：

| 仓库或运行目录 | 容器路径 | 管理方式 |
| --- | --- | --- |
| `./configs` | `/workspace/configs` | Git 管理，只读挂载 |
| `${DATA_DIR}` | `/workspace/data` | 注册表进 Git，真实数据通常外置 |
| `${OUTPUT_DIR}` | `/workspace/output` | 运行产物，不进 Git |
| `${HF_CACHE_DIR}` | `/root/.cache/huggingface` | 模型缓存，不进 Git |

## 初始化和检查

```bash
cp .env.example .env
make validate
```

`.env` 只保存非提交的本机/远端路径配置。默认 WebUI 只绑定 `127.0.0.1`；如果确实需要远程访问，应优先使用 SSH 隧道或带认证的反向代理，不要直接暴露到公网。

`.dockerignore` 将构建上下文限制为 Dockerfile，SSH 配置、数据、模型和输出不会发送到 Docker daemon。

## 部署 WebUI

```bash
make build
make up
make ps
make logs
```

停止本仓库的 Compose 服务：

```bash
make down
```

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
4. 在本仓库执行 `make validate && make build && make up`。
5. 用 `make ps`、`make logs` 和 `nvidia-smi` 验证新部署，再移除旧配置目录。

切换前不要删除 `/opt/llm-training/output/qwen25-3b-sft-smoke`；其中保留了之前 smoke test 的 Adapter 与 Checkpoint。
