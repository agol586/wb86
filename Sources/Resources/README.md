# Generated resources

Signed dictionary resources are generated reproducibly by the build-time compiler. Runtime code
must treat this directory as read-only.

## Pinned Pinyin build input

`ThirdParty/rime-pinyin-simp/pinyin_simp.dict.yaml` is pinned to
`rime/rime-pinyin-simp` commit `0c6861ef7420ee780270ca6d993d18d4101049d0` and has SHA-256
`e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b`.
Its exact upstream `LICENSE` and `AUTHORS` are preserved in the same directory; the dictionary is
redistributed under Apache-2.0. See `ThirdParty/rime-pinyin-simp/SOURCE.md` for URLs and individual
file checksums.

This YAML is accepted only by the pure-Swift build-time compiler. The shipping input path must use the
generated, read-only `MWPY` binary and must not contain a YAML parser, Rime runtime, third-party dynamic
library, network lookup, or update check.
