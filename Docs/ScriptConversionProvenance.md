# Simplified/Traditional Conversion Provenance

Mac Wubi compiles its read-only Simplified-to-Traditional conversion resource from OpenCC data. It
does not link or ship the OpenCC runtime.

- Upstream: `BYVoid/OpenCC`
- Release tag: `ver.1.3.1`
- Peeled source commit: `2f569603954f1cddfdef7b648e71e1aa0d1f47a3`
- License: Apache-2.0, preserved as `OpenCC-LICENSE`
- Inputs: `STCharacters.txt` and `STPhrases.txt`, preserved with an `OpenCC-` filename prefix
- Character source SHA-256: `9cedfb8bf13a220087103d9a96d9f56050c341c24a809cbce5c85c9045456557`
- Phrase source SHA-256: `477023b0bfecb7b722a057ca7804d4516eac9627847d0112882aa958a68ae8ea`
- License SHA-256: `b534e465949558eec2597b04f5092b5e161236a68dfbfd04d547592ac3964308`

The compiler normalizes keys and selected values to NFC, deterministically chooses the first listed
target, lets phrase mappings override character mappings, and sorts records by source UTF-8 bytes.
The generated `MWSC` v1 image is bounded to 100,000 records, a 16 MiB string region, and a maximum
64-character source phrase. Runtime loading validates its complete layout, UTF-8, ordering, and FNV-1a
payload checksum before publishing any mapping.

Regenerate the checked-in image and sorted-key manifest from the repository root with:

```bash
Scripts/compile-script-conversion.sh
```
