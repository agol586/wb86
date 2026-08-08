# Data Model: 隐私优先的原生五笔 86 输入法

## InputSession

代表一个系统文本客户端对应的短期输入生命周期。

| Field | Type | Rules |
|-------|------|-------|
| `sessionID` | 进程内不透明标识 | 仅关联生命周期，不写日志或磁盘 |
| `state` | `CompositionState` | 每次事件后必须处于合法状态 |
| `mode` | `InputMode` | 会话激活时读取设置默认值，可临时切换 |
| `directInput` | Optional raw composition | 中文空闲态首个大写字母开启；保留大小写和符号、显示单一候选，不改变 `mode` |
| `secureInput` | Boolean | 为 true 时禁止任何学习和用户数据写入 |
| `clientAvailable` | Boolean | 客户端失效时立即复位并停止提交 |

一个会话只拥有自己的组合状态；会话之间可以读取同一只读词库和已提交的用户数据快照，
但不得共享未提交组合、输入焦点或临时安全状态。

## CompositionState

```text
idle
composing(code, candidates, pageIndex, selectionIndex)
```

| Field | Type | Rules |
|-------|------|-------|
| `code` | `InputCode` | 仅在 composing 存在，长度 1...4 |
| `candidates` | `CandidatePage` | 必须由当前 code、mode 和数据快照产生 |
| `pageIndex` | Non-negative integer | 不得超过最后一页 |
| `selectionIndex` | Integer | 必须指向当前页项目；空页时不存在 |

### State transitions

| Current | Event | Next | Side effect |
|---------|-------|------|-------------|
| idle | 有效字母 | composing | 查询并显示第一页，设置 marked text |
| composing, 长度 < 4 | 有效字母 | composing | 追加编码、回到第一页、刷新候选 |
| composing, 长度 = 4 且满足自动上屏 | 有效字母 | composing | 提交选定候选，再以新字母开始组合 |
| composing, 长度 = 4 且不自动上屏 | 有效字母 | composing | 保持当前组合并按设置处理新事件 |
| composing | 退格且长度 > 1 | composing | 删除末位、回到第一页、刷新候选 |
| composing | 退格且长度 = 1 | idle | 清除 marked text 和候选 |
| composing | 取消、失焦或输入源切换 | idle | 清除 marked text 和候选，不提交、不学习 |
| composing | 有效选择 | idle | 提交所选文本；非安全场景可生成一个学习增量 |
| composing | 有效翻页或移动选择 | composing | 仅更新页码或选择，不改变编码 |
| composing | 中英文切换 | idle | 原样提交当前编码一次、隐藏候选、不学习，再切换语言 |
| any | 其他模式变化 | idle 或 composing | 依据设置取消一次，禁止残留状态 |
| idle | 首个大写 ASCII 字母 | direct input composing | 设置原文 marked text 并显示单一原文候选，不查询、不学习、不改变语言模式 |
| direct input composing | 字母、数字或普通符号 | direct input composing | 追加原文并同步 marked text 与候选 |
| direct input composing | 空格、回车或选择首项 | idle | 原子提交整段原文，隐藏候选，不学习；回车由输入法消费，不向应用插入换行 |
| direct input composing | 退格或 Escape | composing 或 idle | 退格修正原文；Escape 清空且不提交 |
| any | 数据、客户端或内部错误 | idle | 清除组合与候选，不提交、不学习 |

## InputMode

| Field | Values | Rules |
|-------|--------|-------|
| `language` | Chinese / DirectEnglish | 英文状态不查询词库或学习 |
| `punctuation` | Chinese / English | 只转换规格声明的标点 |
| `width` | Half / Full | 只影响可转换 ASCII 字符 |
| `script` | Simplified / Traditional | 不改变五笔编码，仅转换最终候选 |

模式变化必须由用户可见状态表达。临时模式不得无意覆盖持久化默认值。

## InputCode

| Field | Type | Rules |
|-------|------|-------|
| `letters` | 1...4 个 ASCII 字母 | 只接受 `a...y`，统一转小写 |
| `packedValue` | Unsigned integer | 由字母与长度唯一确定，无随机哈希 |

创建失败属于非法输入，必须走安全复位，不得保留部分值。

## Candidate

| Field | Type | Rules |
|-------|------|-------|
| `text` | 非空 Unicode 字符串 | 必须是合法解码结果 |
| `code` | `InputCode` | 必须等于当前完整查询码 |
| `source` | Base / User | 来源可影响冲突合并，但不对外泄露历史 |
| `baseRank` | Non-negative integer | 同码内稳定的基础顺序 |
| `learnedScore` | Bounded integer | 仅来自聚合学习记录，不含上下文 |
| `ordinal` | 1...9 | 当前页显示和选择序号 |

最终排序键依次为：有效用户固定排序、归一化学习分数、基础 rank、文本字节。相同数据快照
必须得到完全相同的顺序。

## CandidatePage

| Field | Type | Rules |
|-------|------|-------|
| `items` | 0...9 个 `Candidate` | 数量不得超过当前 `candidatePageSize` |
| `pageIndex` | Non-negative integer | 第一页为 0 |
| `hasPrevious` | Boolean | 等价于 pageIndex > 0 |
| `hasNext` | Boolean | 后方至少还有一个候选 |

空候选页是合法结果，不是数据错误。

## BaseDictionaryImage

bundle 内只读、内存映射的基础词库视图。

| Field | Type | Rules |
|-------|------|-------|
| `magic` | 4 bytes | 必须为 `WB86` |
| `schemaVersion` | Unsigned integer | 仅接受实现明确支持的版本 |
| `recordCount` | Unsigned integer | 必须与区域边界和构建清单一致 |
| `prefixRanges` | 1...2 位前缀范围 | 有序、连续且不越界 |
| `records` | 排序记录视图 | code、rank、字符串范围全部有效 |
| `stringBytes` | UTF-8 字节区 | 每个引用必须在边界内且可解码 |
| `checksum` | 固定校验值 | 使用前验证全部载荷 |

构造必须全有或全无；任一错误不得暴露部分词库。

## UserLexiconEntry

| Field | Type | Rules |
|-------|------|-------|
| `id` | Stable local identifier | 仅本地数据关系使用，不含设备或账户身份 |
| `code` | `InputCode` | 必须合法 |
| `text` | 非空 Unicode string | 有明确长度上限，不得含控制字符 |
| `fixedRank` | Optional bounded integer | 用户明确调整时设置 |
| `createdBy` | Manual / Import | 仅表示来源类别，不记录文件路径或时间线 |

相同 `(code, text)` 只保留一条；导入重复项按较高用户优先级合并。

## LearningRecord

| Field | Type | Rules |
|-------|------|-------|
| `code` | `InputCode` | 只保存聚合查询码 |
| `candidateKey` | 本地稳定候选键 | 不关联应用、文档或会话 |
| `score` | Bounded integer | 每次选择增量，有封顶值 |
| `decayEpoch` | Monotonic bucket | 只支持稳定衰减，不构成输入时间线 |

记录上限为 50,000。超过上限时先衰减，再删除最低分记录；安全输入、英文直输、取消和失败
均不得生成记录。

## InputSettings

| Field | Values / Rules |
|-------|----------------|
| `schemaVersion` | 必须是支持版本 |
| `candidatePageSize` | 5...9 |
| `candidateLayout` | Horizontal / Vertical |
| `candidateFontScale` | 受限可访问范围 |
| `pageKeySet` | `-`/`=`、`,`/`.` 或 `[`/`]` |
| `modeSwitchKey` | 文档化选项或 Disabled，不得覆盖系统保留快捷键 |
| `autoCommitAtFour` | Boolean |
| `defaultMode` | `InputMode` |
| `learningEnabled` | Boolean |

恢复默认只替换此实体，不删除用户词条或学习记录。

## DataSnapshot

| Field | Type | Rules |
|-------|------|-------|
| `domain` | Settings / UserLexicon / Learning | 三个域独立提交与恢复 |
| `schemaVersion` | Positive integer | 未知未来版本只读保留，不降级覆盖 |
| `generation` | Monotonic integer | 仅用于原子替换与恢复，不表示输入时间 |
| `payload` | Validated bytes | 提交前完成全部校验 |
| `checksum` | Fixed checksum | 必须与 payload 匹配 |

每个域最多保留当前完整快照和一个回退快照。写入流程为：构建临时快照、同步并验证、原子
替换当前文件、最后清理旧临时文件。单域失败不得改动其他域。

## ImportReport

| Field | Type | Rules |
|-------|------|-------|
| `acceptedCount` | Non-negative integer | 新增的合法记录数 |
| `mergedCount` | Non-negative integer | 与已有项合并数 |
| `skippedCount` | Non-negative integer | 可识别但不采用数 |
| `failedCount` | Non-negative integer | 非法或无法读取数 |
| `errorCategories` | 固定类别与计数 | 不包含词条正文、路径或行内容 |

报告只在当前设置会话展示，不形成永久导入历史。

## PrivacyStatus

运行时派生视图，列出 Settings、UserLexicon 和 Learning 三个数据域是否启用、当前字节数、
格式版本及删除入口。不得包含词条列表、候选文本、按键、应用、时间或会话标识。
