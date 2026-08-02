# T056 Monthly-Volume Stability Evidence

Status: **PASS**

Execution date: 2026-08-02 (Asia/Shanghai)

## Scope and counting contract

The workload models one month of continuous input intensity as 30 sequential logical input days and
at least 1,000,000 Chinese characters delivered by `commitText` client actions. Each day destroys and
recreates eight independent input sessions. Marked text, cancelled compositions, ASCII characters,
candidate display and failed operations do not contribute to the total. The deterministic mix covers
Wubi, continuous pinyin, simplified/traditional conversion, settings churn, automatic frequency,
candidate paging, selection and cancellation. Reports retain counts and aggregate metrics only; no
input, code, candidate or committed text is recorded.

## Environment and artifact

- Hardware: MacBook Air, Apple M3, 8 cores, 24 GB RAM.
- Architecture: native `arm64` only.
- macOS: 26.5.2 (25F84).
- Xcode: 26.6 (17F113).
- Build: Release, macOS 13.0 deployment target, Hardened Runtime, local ad-hoc signature.
- Executable SHA-256:
  `1c4d07988c6672b8d194e26ae0f180918855db4eaa210f44a0dee9afa92203cd`.
- Pinyin manifest SHA-256:
  `08a15c97565d6f020fea0a64dab33ecad7c9f3e09c1d745d58022580aab80b7e`.
- WB86 manifest SHA-256:
  `9b6a6c4cb186fb3f24b9d7409866ca12ef5e8a762fe5e82ec01c8b8afe9ced62`.

No hardware identifier or user content is retained in this evidence.

## Automated harness

```bash
xcodebuild test -project MacWubi.xcodeproj -scheme MacWubi \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacWubiTests/LongRunStressTests
```

Result: **PASS**. The bounded test executed all 30 logical-day boundaries with 3,008 committed Chinese
characters, 31 physical-footprint samples and 1,504 learning deltas. First/last steady footprint was
12,468,920/12,485,304 bytes; first/last average event latency was 1,087/1,030 ns.

## Release million-character gate

```bash
Scripts/build-release.sh
Scripts/run-long-stress.sh \
  /Users/agol/repos/wb86/.worktrees/002-settings-experience/.build/xcode/Build/Products/Release/MacWubi.app \
  1000000
```

Result: **PASS**.

```text
targetCommittedCharacters=1000000 committedCharacters=1000000 logicalDays=30
sessionsPerDay=8 iterations=600000 learningDeltas=600000 durationSeconds=474.1248975
firstAverageLatencyNs=105905 lastAverageLatencyNs=107081 maximumLatencyNs=47579292
firstSteadyBytes=8372896 lastSteadyBytes=6455968 maximumBytes=8487584
```

- Target coverage: exactly 1,000,000 actual committed Chinese characters across all 30 logical days.
- Normal memory gate: maximum 8,487,584 bytes, below 15 MiB.
- Sustained memory gate: last steady average is 1,916,928 bytes below the first steady average.
- Sustained latency gate: last average is 1,176 ns above first average, below the allowed 200,000 ns
  drift.
- The maximum event latency is retained as an informational scheduler outlier. The controlled T054
  release corpus separately enforces the `<2 ms` requirement on every recognized lookup sample; T056
  enforces sustained first-to-last drift over the high-volume workload.
- Wall-clock duration is informational and is not a pass condition.

## Regression and release contracts

```bash
Scripts/test.sh
Scripts/verify-release.sh \
  /Users/agol/repos/wb86/.worktrees/002-settings-experience/.build/xcode/Build/Products/Release/MacWubi.app
Scripts/privacy-audit.sh \
  /Users/agol/repos/wb86/.worktrees/002-settings-experience/.build/xcode/Build/Products/Release/MacWubi.app
```

Results: **PASS**. XCTest executed 217 tests with zero failures or skips; deterministic dictionary
fixtures reproduced. The tested artifact is a signed, Hardened Runtime, thin arm64 application with no
network capability, global input monitor, third-party runtime or sensitive diagnostics.

## Constitution impact

- Architecture/dependencies: unchanged, native arm64 and pure Swift with Apple frameworks only.
- InputMethodKit/signing: probe runs inside the signed product executable without adding entitlements;
  Developer ID/notarization remains the separately deferred final-release gate.
- Recovery/privacy: logical-day session recreation reaches idle after each workload iteration and emits
  aggregate metrics only; no production data file or user content is used.
- Performance: `<15 MiB` and sustained memory/latency gates pass at the amended one-month-equivalent
  input volume. The controlled per-query `<2 ms` gate remains covered by T054.
