# Contract: 设置读取、编辑、保存与应用

## Load and migration

1. 先读取快照 envelope 的 schema，不把未知未来版本当作损坏。
2. v1 由严格 DTO 完整解码并验证，再映射为 v2；迁移成功前不替换 current。
3. v1 已有值保留语义：既有默认模式、外观、单一翻页组、学习和四码开关原样映射；新增字段
   使用兼容默认（五码、混输、提示、分号/单引号关闭；布局跟随系统）。
4. v1 `autoCommitAtFour=true` 映射为“仅四码唯一提交”，不保留旧实现错误的多候选提交行为。
5. future schema 保留原字节并只读运行安全内存默认；不得以 previous 覆盖 future current。

## Edit and validation

- 打开窗口时建立 `saved` 与 `draft` 两份值；Cancel 丢弃 draft 且零写入。
- Save 对完整 draft 做枚举、数值、布局可用性、重复、范围重叠和系统保留组合验证。
- 错误必须关联具体控件；任一错误使整次 Save 零写入，最后有效代次继续生效。
- 成功 Save 先原子持久化，再发布新的不可变代次；失败不得先改变运行时。

## Runtime application

- 每个会话独立持有 active/pending 代次。
- 空闲和新会话采纳最新代次；组合会话完成当前客户端动作并转为空闲后采纳自己的最新 pending。
- 一个组合内的查询、排序、分页、自动提交、快捷键和学习策略必须来自同一代次。
- 保存不得重置会话临时模式；持久化初始模式仅在新建或重新激活时使用。

## Restore Defaults

- 用户确认后，以一次正常原子 Save 写入 `newInstallDefault`；取消零写入。
- 仅 Settings generation 改变；用户词库和学习快照的字节及 generation 必须保持一致。
- future-schema 只读状态、验证错误或 I/O 失败时拒绝恢复并保持所有域不变。
