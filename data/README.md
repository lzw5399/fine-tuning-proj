# 数据集目录

`dataset_info.json` 是项目自己的 LLaMA-Factory 数据集注册表。`my_sft.json` 是从远端同步的两条 ShareGPT 格式样例，只用于验证字段结构，不能作为正式训练数据。

正式数据通常较大或包含敏感内容，默认不会提交到 Git。新增数据时：

1. 将数据放在远端由 `DATA_DIR` 指向的目录中。
2. 在 `dataset_info.json` 注册文件名、格式和字段映射。
3. 在 `configs/sft.yaml` 中更新 `dataset`。
4. 保留 `val_size: 0.1`，由 LLaMA-Factory 使用固定 `seed` 切出 10% 验证集。

`configs/sft-smoke.yaml` 使用固定 LLaMA-Factory 镜像内的 `/app/data/alpaca_zh_demo.json`。该数据集包含 1000 条中文 Alpaca 示例；smoke 配置通过 `max_samples: 100` 只取 100 条，约 90 条训练、10 条验证。镜像内文件的 SHA256 是 `d5a4be46ae70d23a461ffc16048069324c0865ee9aa0c8730e21ac4b65ea0f08`。示例数据的上游许可应在正式分发或商用前单独核对，不应直接套用 LLaMA-Factory 仓库的 Apache-2.0 许可。
