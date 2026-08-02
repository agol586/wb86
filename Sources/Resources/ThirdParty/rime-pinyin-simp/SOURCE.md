# rime-pinyin-simp source record

MacWubi uses only `pinyin_simp.dict.yaml` from the public
[`rime/rime-pinyin-simp`](https://github.com/rime/rime-pinyin-simp) repository, pinned to commit
[`0c6861ef7420ee780270ca6d993d18d4101049d0`](https://github.com/rime/rime-pinyin-simp/commit/0c6861ef7420ee780270ca6d993d18d4101049d0).

Upstream files and SHA-256 values:

| File | SHA-256 |
|---|---|
| `pinyin_simp.dict.yaml` | `e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b` |
| `LICENSE` | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |
| `AUTHORS` | `f4cff0fcbca4668ac449c24a53be547e162bc60cce63fdc5d5906801a452edc4` |

The upstream `AUTHORS` identifies the dictionary as derived from Android Pinyin IME under the
Apache License 2.0. The exact upstream `LICENSE` and `AUTHORS` are preserved beside the source.

The YAML is immutable build input only. MacWubi's pure-Swift build-time dictionary compiler normalizes
and compiles it into the versioned `MWPY` resource. Product runtime code reads only that generated binary;
it does not parse YAML, execute Rime code, link librime, or create a network connection. Updating the
pinned commit requires a new license review, source checksum, deterministic build, fixture review, and
generated manifest.
