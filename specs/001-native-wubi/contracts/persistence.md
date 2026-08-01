# Contract: Local Persistence and Migration

## Data boundary

运行时只允许读写 `~/Library/Application Support/org.macwubi.inputmethod/` 中的三个独立域；
根目录权限必须为 `0700`，快照、临时文件和 previous 文件权限必须为 `0600`：

```text
Settings/current
UserLexicon/current
Learning/current
```

每个域还可包含一个 `previous` 回退快照和一个写入中的临时文件。不得创建按键、提交文本、
应用、文档、会话或时间线日志。基础词库只从签名 bundle 读取。

## Snapshot envelope

每个快照必须包含：

- 固定 magic 与数据域；
- schema version；
- 单调 generation；
- payload 长度与 checksum；
- 不包含设备、账户、绝对路径或墙钟时间的可复现载荷。

未知未来 schema 必须只读保留并拒绝覆盖。已知旧 schema 只能通过显式、测试覆盖的逐版本
迁移路径升级，不得跳过中间语义。

## Atomic write

一次提交必须遵循：

1. 在同一 Application Support 数据根目录和数据域内创建临时快照；
2. 完整写入并重新读取验证 envelope、payload 和 checksum；
3. 将当前完整快照保留为 `previous`；
4. 原子替换 `current`；
5. 再次加载 `current` 成功后清理多余临时文件。

任一步失败都不得修改调用者可见 generation。进程重启时必须删除无法验证的临时文件，
优先加载有效 current，否则加载有效 previous，否则只对该域使用安全默认值。

## Concurrency

- 所有写入必须经单一串行协调器；不得由多个输入会话直接写文件。
- 查询捕获一个不可变数据快照并在单次事件内使用，不能混合两个 generation。
- 学习增量可在内存中合并，但必须有数量和刷新周期上限；异常退出只允许丢失尚未提交的
  有界增量，不得损坏已提交快照。

## Domain-specific rules

- Settings：恢复默认只替换 Settings，不触碰其他域。
- UserLexicon：手工编辑和导入使用同一验证、去重与原子提交路径。
- Learning：全局关闭或私密模式时不得接收增量；清除后不得从 previous 自动恢复。
- Delete All：三个域分别原子删除或置空；任一失败必须显示域级结果，不得声称全部成功。

## Migration gate

每个 schema 版本必须有：升级成功、每一步中断、checksum 错误、未知未来版本、回退快照和
重复执行测试。迁移代码不得读取或生成输入正文之外的上下文数据，也不得联网。
