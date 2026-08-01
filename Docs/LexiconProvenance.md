# Wubi 86 Lexicon Provenance and Redistribution Policy

## Approved upstream

MacWubi uses only `wubi86.dict.yaml` from the public
[`rime/rime-wubi`](https://github.com/rime/rime-wubi) repository, pinned to commit
[`152a0d3f3efe40cae216d1e3b338242446848d07`](https://github.com/rime/rime-wubi/commit/152a0d3f3efe40cae216d1e3b338242446848d07).
The pinned UTF-8 source file has SHA-256
`f833d86b72341fe82e069a425b6625f29ef85f1bc0f34f6fb7975fe514888b5a`.
No Rime engine code, schema implementation, `rime-essay` vocabulary, or other runtime dependency is
used.

The upstream [`AUTHORS`](https://github.com/rime/rime-wubi/blob/152a0d3f3efe40cae216d1e3b338242446848d07/AUTHORS)
states that the dictionary is derived from Yu Yuwei's LGPL ibus-table work, based on Wang Yongmin's
public-domain original work, and that Gong Chen's `wubi86.dict.yaml` contribution is LGPL. The repository
ships the [GNU Lesser General Public License version 3](https://github.com/rime/rime-wubi/blob/152a0d3f3efe40cae216d1e3b338242446848d07/LICENSE),
so the dictionary is treated as `LGPL-3.0-only`.

## Redistribution obligations

Every distributed MacWubi bundle containing a dictionary derived from this source must also contain:

- the exact upstream `LICENSE` and `AUTHORS` files;
- the pinned unmodified `wubi86.dict.yaml`, or an equivalent durable offer for its corresponding source;
- this provenance record and the generated manifest;
- the pure-Swift compiler and documented normalization procedure needed to reproduce `wb86.bin`.

The generated dictionary remains a separately identified LGPL-covered data work. The MacWubi Swift
application is not relicensed by this policy. A release is blocked if these notices, corresponding source,
the source SHA-256, or deterministic reproduction checks are missing. Updating the upstream commit requires
a new license review, fixture review, manifest, and checksum; a moving branch is never an accepted source.

## Deterministic normalization

The upstream data section declares columns `text`, `code`, `weight`, and optional `stem`. The normalization
pipeline performs these steps in order:

1. Decode the complete pinned source as strict UTF-8 and read only records after the YAML `...` marker.
2. Ignore blank lines, comments, `stem`, and codes outside one to four ASCII letters `a...y`.
3. Normalize code letters to lowercase and candidate text to Unicode NFC; reject empty text, surrounding
   whitespace, and control characters.
4. Merge duplicate `(code, text)` pairs, retaining the greatest unsigned upstream weight.
5. For each code, sort by weight descending and then UTF-8 bytes ascending, assigning ranks `0...n-1`.
6. Sort normalized records by packed code, rank, and UTF-8 bytes and emit `code<TAB>text<TAB>rank` with LF
   endings.
7. Compile with dictionary schema v1. Derive the build identifier from the FNV-1a-64 checksum of the complete
   normalized TSV; never include time, username, host, or source path.

The manifest records the pinned revision, license identifier, source checksum, build identifier, record
count, format version, and compiled-image checksum. Identical normalized input and compiler source must
produce byte-identical dictionary and manifest files.

## Acceptance corpus policy

`Tests/Fixtures/Lexicon/wb86-acceptance.tsv` is a small LGPL-covered derivative of the pinned source. It must
cover one-, two-, three-, and four-letter codes; abbreviations and full codes; phrases; collisions and stable
rank order; BMP and supplementary-plane valid UTF-8; and empty-prefix ranges. It must contain no fabricated
entries presented as upstream data.

Fixture changes require locating every row in the pinned source, applying the normalization rules above,
updating `known-vectors.json`, and passing dictionary round-trip, corruption, ordering, lookup, and
deterministic double-build tests. The acceptance corpus proves behavior only; product coverage is assessed
against the complete pinned lexicon.

## Finalized release inventory

The pinned source contains 136,233 normalized records. The generated `wb86.bin` is 3,974,577 bytes with
SHA-256 `45e8132d0d0cdd9f2662a6821dd4b886cb6f7272f7e41000175abb8c6a099ab0`; its manifest records image
FNV-1a-64 `c589b2e295b24f10`, source/build FNV-1a-64 `affd6ad3e043bec9`, schema 1, the pinned revision,
upstream SHA-256 and `LGPL-3.0-only` license identifier.

On 2026-08-01 the pinned YAML was normalized once and compiled twice with the Release Swift compiler.
Both images and manifests were byte-identical to each other and to `Sources/Resources/wb86.bin` and
`wb86.manifest.json`. The application resource copy also contains the exact upstream `LICENSE`, `AUTHORS`
and `wubi86.dict.yaml`. T106 is invalidated by any resource or compiler change until this check is repeated.
