# Contract: MWPY 本地拼音资源

## Provenance

- 输入固定为 `rime/rime-pinyin-simp` commit `0c6861ef7420ee780270ca6d993d18d4101049d0` 的
  `pinyin_simp.dict.yaml`，源 SHA-256 为
  `e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b`。
- 仓库必须保存 Apache-2.0 LICENSE、AUTHORS、来源 URL/commit、规范化规则和可复现构建命令。
- 源 YAML 只用于构建期；产品运行时不得包含解析器或第三方代码运行时。

## Deterministic compile

- NFC 正文；拼音小写并移除音节空格，只允许 1...32 个 ASCII `a...z`；权重必须有限且可界定。
- 转成产品规范简体后，以 `(continuousKey, finalText)` 去重，保留最高权重。
- 排序为 key、weight descending、UTF-8 bytes；每个 key 最多保留 64 项。
- 五笔反向提示确定选择：优先完整四码，再取更长编码、较高基础排名、较小 packed code。
- 清单记录输入/输出 checksum、格式版本、条目数、WB86 build ID 和许可。

## Binary envelope and loader

- `MWPY` header 包含版本、所有区段 offsets/counts、checksum 和匹配的 WB86 build ID。
- 数据区包含首/次字母范围、每 32 键重启的前缀压缩键表、候选 ranges、紧凑候选 records 与
  非 WB86 UTF-8 text blob。
- loader 验证文件上限、magic/version、整数溢出、区段边界、checksum、restart/front-code、严格
  key 次序、candidate/text/reference 边界和 UTF-8；任一失败使整个拼音源不可用。
- 资源只读映射，查询只解码目标键和页面，不在启动或按键路径建立完整 `[String: ...]`。

## Gates

- 生成资源目标约 1.25–1.4 MiB，仅作设计预算，不是验收结果。
- Release 构建必须实际证明所有查询样本 `<2 ms`、正常 RSS `<15 MB`，并在 30 个逻辑输入日、
  至少 1,000,000 个实际提交中文字符的确定性负载中无持续增长；失败时先减少每键上限或改进压缩，
  不得放宽门禁。
