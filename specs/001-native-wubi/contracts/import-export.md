# Contract: User Lexicon Import and Export

## Authorization

导入和导出只能由用户在设置窗口中明确触发，并通过系统打开或保存面板选择文件。取消面板
不得留下授权、临时文件或历史记录。运行时不得扫描其他输入法目录或猜测词库位置。

## Supported formats

### Mac Wubi archive

版本化产品格式，包含 UserLexicon 和可选 Learning 两个独立载荷、各自 checksum、格式版本
和导出选项。不得包含设置以外的设备信息、按键历史、应用、文档、会话或时间线。

### UTF-8 text

```text
# mac-wubi-user-lexicon v1
code<TAB>text<TAB>optional-fixed-rank
```

- `code`：一至四位 `a...y`，导入时统一为小写。
- `text`：非空有效 Unicode，不得包含 tab、换行或控制字符，并有文档化长度上限。
- `optional-fixed-rank`：省略或为有界非负整数。
- 空行和以 `#` 开头的注释行可忽略。

每行和整个文件都有明确字节上限；超过 100,000 条可接受记录时停止并报告，不得无界占用
内存。解析必须流式或分块完成。

## Merge rules

1. 非法记录计入 failed，不进入候选数据。
2. 同一文件中的重复 `(code, text)` 合并为一条，保留最高用户优先级。
3. 与现有用户词条重复时更新该条，不创建重复项。
4. 与基础词库重复时保留用户覆盖信息，但不复制或修改基础记录。
5. 所有合法项先形成候选快照；只有整个快照验证成功后才原子替换 UserLexicon。

## Reporting

结果只包含 accepted、merged、skipped、failed 数量和固定错误类别。界面可在导入确认前
展示有限预览，但生产日志和持久报告不得保存词条正文、文件路径或行内容。

## Export behavior

用户明确选择是否包含 Learning；默认只导出 UserLexicon。导出先写临时文件、校验后原子
替换用户选择的目标。导出失败不得删除或截断已有目标文件。导出结束后不得保留额外副本。
