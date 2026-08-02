# Contract: schema v2 迁移与中断恢复

## Settings v1 → v2

- 使用与 v1 完全匹配的私有 DTO 严格解码；未知/缺失必需旧字段、非法枚举或越界值均使迁移失败。
- 构造 v2 后运行完整 v2 验证，写入 stage，重新读回验证，再以原子 rename 替换 current。
- 每一步失败或进程终止均保留可恢复的 v1 current/previous；迁移可重复且不会重复增加语义变化。

## Learning v1 → v2

- 既有五笔学习键包装为 `kind=wubi`，计数、衰减次序和候选身份保持不变。
- 新拼音学习键为独立 `kind=pinyin`；关闭调频或私密/禁止学习时不读取也不写入其分数。
- 设置迁移与学习迁移是独立事务；一个域失败不得覆盖另一域。

## Recovery order

1. 已支持且完整的 current。
2. current 损坏时，已支持且完整的 previous。
3. 无可恢复快照时，安全内存默认；保留损坏证据但日志不含路径或输入数据。

schema 大于当前版本不进入上述损坏恢复顺序：future current 原样保留，应用进入 Settings 只读兼容状态。
