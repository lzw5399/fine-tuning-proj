# Qwen SFT 训练仓库

本仓库是后续 LLaMA-Factory 部署、数据注册、训练配置和执行命令的唯一基准。远端只保存模型缓存、真实数据和训练输出等运行状态；需要调整配置时，应先修改并审查本仓库，再部署到远端。

## 当前基线

- 模型：`Qwen/Qwen2.5-3B-Instruct`
- 方法：bitsandbytes 4-bit NF4 QLoRA
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
│   ├── sft-smoke.yaml              # 官方中文 demo 的短程验证
│   └── sft.yaml                    # 项目数据的正式 SFT 配置
├── data/
│   ├── dataset_info.json           # 项目数据集注册表
│   └── my_sft.json                 # 两条格式样例，不是正式数据
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

## 官方 smoke 数据集与 10% 验证集

固定镜像内有 LLaMA-Factory 官方 demo 数据：

- `identity`：91 条，含身份占位符，不作为通用 smoke 首选
- `alpaca_en_demo`：999 条英文 Alpaca 示例
- `alpaca_zh_demo`：1000 条中文 Alpaca 示例

[`configs/sft-smoke.yaml`](configs/sft-smoke.yaml) 使用 `alpaca_zh_demo`。为了让 smoke 足够短，配置先通过 `max_samples: 100` 取 100 条，再通过 `val_size: 0.1` 按固定随机种子切分，约得到 90 条训练数据和 10 条验证数据。每 10 步执行一次 evaluation，并在训练结束后恢复 `eval_loss` 最优的 Checkpoint。

固定镜像中该文件大小为 636,036 bytes，SHA256 为 `d5a4be46ae70d23a461ffc16048069324c0865ee9aa0c8730e21ac4b65ea0f08`。

当前 LLaMA-Factory/Transformers 版本必须使用：

```yaml
val_size: 0.1
per_device_eval_batch_size: 1
eval_strategy: steps
eval_steps: 10
```

不要改成旧键 `evaluation_strategy`，该版本不会接受它。官方 demo 的具体上游许可未在镜像注册表中声明，正式分发或商用前需要单独核对数据来源许可。

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

## 执行训练

运行官方中文数据 smoke test：

```bash
make smoke
```

运行项目正式配置：

```bash
make train
```

运行仓库内其他配置：

```bash
make train CONFIG=configs/example.yaml
```

训练通过 `docker compose run --rm --no-deps` 启动独立的一次性容器，不依赖 WebUI 是否正在运行。该命令会使用真实 GPU；执行前先用 `nvidia-smi` 确认机器没有其他训练任务。

## 接入真实数据

当前 `data/my_sft.json` 只有两条结构样例，不能用于正式微调。接入真实数据时：

1. 将数据放入远端 `${DATA_DIR}`，不要把敏感或大型语料提交到 Git。
2. 在 `data/dataset_info.json` 注册数据文件与字段映射。
3. 在 `configs/sft.yaml` 更新 `dataset`。
4. 保留 `val_size: 0.1`，确保 10% 数据用于验证。
5. 根据训练集大小同步调整 `eval_steps` 与 `save_steps`，两者保持一致。
6. 先跑短程稳定性验证，确认没有 NaN、显存溢出和数据模板错误，再进行完整训练。

## 迁移远端旧部署

本次只建立了本地仓库基线，没有停止或修改远端容器。正式切换时建议：

1. 将本仓库 clone/pull 到远端固定目录。
2. 从 `.env.example` 创建远端 `.env`，保留现有 `/opt/vllm/hf-cache` 与 `/opt/llm-training/output`。
3. 确认没有训练任务后，在旧 `/opt/llamafactory-webui` Compose 项目中停止旧 WebUI。
4. 在本仓库执行 `make validate && make build && make up`。
5. 用 `make ps`、`make logs` 和 `nvidia-smi` 验证新部署，再移除旧配置目录。

切换前不要删除 `/opt/llm-training/output/qwen25-3b-sft-smoke`；其中保留了之前 smoke test 的 Adapter 与 Checkpoint。
