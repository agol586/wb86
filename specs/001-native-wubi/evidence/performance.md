# Release Lookup Performance Evidence

Status: **PASS for automated release corpus; eight-hour gate tracked separately**

Measured 2026-08-01 on `Mac15,12`, Apple M3, arm64, 24 GiB physical memory, macOS 26.5.2
(25F84), Xcode 26.6 (17F113), Release configuration. Clock: `DispatchTime.uptimeNanoseconds`.
Corpus: `wb86-acceptance.tsv`, 23 records, 18 unique codes. Warm-up: 20 complete corpus passes.
Samples: 100 per code, 1,800 total.

| Metric | Absolute result |
|---|---:|
| p50 | 666 ns |
| p95 | 1,666 ns |
| p99 | 1,750 ns |
| maximum | 5,584 ns |
| hard budget | 2,000,000 ns |

Command:

```bash
xcodebuild test -project MacWubi.xcodeproj -scheme MacWubi -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/release-performance \
  -only-testing:MacWubiTests/ReleasePerformanceTests ENABLE_TESTABILITY=YES \
  CODE_SIGNING_ALLOWED=NO
```

Every recorded sample passed. Because no repeatable failing measurement existed, the constitution's
measurement-first rule prohibited speculative changes to `DictionaryIndex`; T104 therefore required no
production-code optimization. The report is deterministic in method but machine-dependent in values and
must be regenerated for the final candidate.

The long-run harness was smoke-tested in Release for 2 seconds: 1,917,650 seven-class session cycles,
9 footprint samples, first and last steady averages both 12,501,688 bytes. This proves harness execution,
not the required eight-hour verdict. Final command: `Scripts/run-long-stress.sh 28800`.
