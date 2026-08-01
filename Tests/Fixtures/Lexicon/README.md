# Lexicon Fixtures

The files in this directory are test-only derivatives of Rime's Wubi 86 dictionary at commit
`152a0d3f3efe40cae216d1e3b338242446848d07`, licensed under `LGPL-3.0-only`. See
`Docs/LexiconProvenance.md` for authorship, upstream links, normalization, redistribution requirements, and
the pinned source SHA-256.

- `wb86-acceptance.tsv` is normalized `code<TAB>text<TAB>rank` UTF-8 with LF endings.
- `known-vectors.json` contains non-secret, deterministic format and lookup expectations.

Fixtures must never contain imported user terms, application context, paths, timestamps, or production
learning data. Changes require provenance review and deterministic regeneration.
