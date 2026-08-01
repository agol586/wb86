# Contract: WB86 Dictionary Format v1

## Purpose

定义构建期词库编译器与运行时查询器之间的稳定、可验证、只读契约。所有多字节整数采用
little-endian；所有偏移从文件起始计算。

## Logical layout

```text
Header
PrefixRangeTable
EntryRecordTable
UTF8StringBlob
Checksum
```

## Header

必须包含以下固定字段：

- magic：ASCII `WB86`
- schema version：`1`
- header、范围表、记录表、字符串区的偏移与长度
- entry count，必须等于构建清单并在文件边界内；格式使用有界整数，不人为限制产品词库规模
- 构建标识；不得包含用户、机器路径或时间等不可复现内容

## Prefix range table

- 覆盖所有一位和两位 `a...y` 前缀。
- 每项给出记录表的半开区间 `[start, end)`。
- 空前缀范围合法；所有非空范围不得重叠且必须在 entry count 内。

## Entry records

每条逻辑记录包含：

- 一至四位 `a...y` 编码及编码长度；
- 非负稳定 rank；
- UTF-8 字符串区的偏移和长度。

记录按 packed code、rank、UTF-8 字节升序排列。重复 `(code, text)` 必须在编译时去重。
空文本、非法编码、无效 UTF-8、越界偏移或非稳定顺序使整个词库无效。

## Checksum

文件末尾包含覆盖 Header 后载荷的固定算法校验值。算法及字节数在 schema version 1 中固定，
实现任务必须用已知向量锁定；变更算法需要提升 schema version。

## Loader behavior

加载器在提供查询前必须依次验证文件最小长度、magic、版本、区域边界、记录数、范围表、
记录排序、字符串引用和 checksum。任一步失败都返回单一 `invalidDictionary` 结果，不返回
部分候选、不尝试修复，也不把损坏字节写入日志。

未知版本必须被拒绝。未来版本需要显式迁移或独立读取器，不得猜测布局。基础词库保持
只读；用户词条与学习数据不得写入本文件。
