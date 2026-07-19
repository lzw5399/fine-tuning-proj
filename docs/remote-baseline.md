# 远端训练基线（2026-07-19）

本文记录建立仓库基准前对远端机器进行的只读审计。它用于说明文件来源和迁移边界，不包含主机地址、密码、Token 或其他凭据。

## 部署与路径

旧部署位于：

- `/opt/llamafactory-webui/Dockerfile`
- `/opt/llamafactory-webui/compose.yaml`
- `/opt/llm-training/configs/`
- `/opt/llm-training/data/`
- `/opt/llm-training/output/`

运行容器 `llamafactory-webui` 将：

- `/opt/vllm/hf-cache` 挂载到 `/root/.cache/huggingface`
- `/opt/llm-training` 挂载到 `/workspace`

因此旧的 `/workspace/configs/sft-smoke.yaml` 对应宿主机 `/opt/llm-training/configs/sft-smoke.yaml`。容器内外文件的 SHA256 已核对一致。

## 已同步源文件

| 远端文件 | SHA256 | 仓库对应文件 |
| --- | --- | --- |
| `/opt/llamafactory-webui/Dockerfile` | `e73a0e58406dfa0b193f79f5172fe3d241343187f50ac167a62606af39ae48b4` | `docker/llamafactory/Dockerfile`（增加版本固定） |
| `/opt/llamafactory-webui/compose.yaml` | `6c4d0d3e73631e57518cac5212f74cba6c30f2d119151bcd9d8781f2bdc66714` | `compose.yaml`（改为仓库挂载和安全默认值） |
| `/opt/llm-training/configs/sft-smoke.yaml` | `d9e4c6831ee78b7bd64f9da68fd710d48dd0ab804f0dee0fbcf57765b9d3f501` | `configs/sft-smoke.yaml`（改用官方 demo 并增加验证） |
| `/opt/llm-training/configs/sft.yaml` | `52cc036b2b0eac900c62a14c1bef47509fe653f38aedfeffcf0f1597c11238b6` | `configs/sft.yaml`（增加 10% 验证） |
| `/opt/llm-training/data/dataset_info.json` | `88dc7c4d87c2e6810db0d8a7b824e954f5452de6857d3490a17477dc9f4474f9` | `data/dataset_info.json`（移除缺失的 DPO 文件注册） |
| `/opt/llm-training/data/my_sft.json` | `998cfbc4cf4647f3658ee04c11bda2dc8c38926199704ef0aae8bd4d04e10302` | `data/my_sft.json` |

旧 Dockerfile 使用 `hiyouga/llamafactory:latest` 和 `bitsandbytes>=0.48.0`。审计时实际基础镜像 OCI digest 为 `sha256:cde9745570861693a8a0e7da6aa1a1fadde7c728b8ceeb189191ddc3a3a8d3f3`，bitsandbytes 为 `0.49.2`；仓库基线固定为这两个版本。

镜像内官方中文 demo `/app/data/alpaca_zh_demo.json` 共 1000 条、636,036 bytes，SHA256 为 `d5a4be46ae70d23a461ffc16048069324c0865ee9aa0c8730e21ac4b65ea0f08`。

## 软件与硬件状态

- GPU：Tesla T4，15,360 MiB
- 驱动：580.126.20
- 容器 Python：3.11.11
- PyTorch：2.6.0+cu124
- LLaMA-Factory：0.9.6.dev0
- Transformers：5.8.0
- PEFT：0.18.1
- bitsandbytes：0.49.2

审计时 GPU 没有训练任务，只有 WebUI 进程占用约 104 MiB。WebUI 主进程存在若干已退出但未回收的 Python 子进程，迁移部署时可通过重建旧容器一并清理。

## 历史 smoke test

旧输出目录 `/opt/llm-training/output/qwen25-3b-sft-smoke` 包含：

- 最终 LoRA Adapter
- `checkpoint-5`
- `checkpoint-6`
- Trainer 状态、优化器、调度器和随机数状态

该训练仅使用 2 条样例，运行 3 epoch、6 个 Trainer step，最终 `train_loss=3.149201`，耗时约 7.6 秒。前 3 步 FP16 梯度出现 NaN 并被 GradScaler 跳过，因此它只能证明训练链路能够结束，不能证明模型效果或数值稳定性。

历史输出约 266 MiB，属于运行产物，没有同步进 Git，也不应在迁移时删除。

## 尚未执行的远端变更

建立本基线时没有：

- 停止或重建现有容器
- 覆盖远端配置
- 启动训练或 benchmark
- 删除历史输出或模型缓存

后续远端变更应由本仓库审查后的文件驱动。
