# 数据集目录

`dataset_info.json` 是项目自己的 LLaMA-Factory 数据集注册表。`my_sft.jsonl` 是两条 ShareGPT SFT 样例；`my_dpo.jsonl` 是两条 ShareGPT ranking 偏好对样例。两者均为每行一个完整 JSON 对象，只用于验证字段结构，不能作为正式训练数据。

正式数据通常较大或包含敏感内容，默认不会提交到 Git。新增数据时：

1. 将数据放在远端由 `DATA_DIR` 指向的目录中。
2. 在 `dataset_info.json` 注册文件名、格式和字段映射。
3. 在 `configs/sft.yaml` 中更新 `dataset`。
4. 保留 `val_size: 0.1`，由 LLaMA-Factory 使用固定 `seed` 切出 10% 验证集。

SFT 样本使用完整的多轮 `conversations` 作为监督答案。DPO 样本的 `conversations` 只包含共同上下文，`chosen` 和 `rejected` 分别保存同一 prompt 下的偏好回答与非偏好回答；对应注册项必须设置 `ranking: true`。
