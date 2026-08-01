# US3 Personalization Evidence

## Verdict

PASS for the User Story 3 development checkpoint on the current Apple Silicon development system. This
is not a final release verdict; settings UI integration and the deferred release gates remain separate.

## Environment

- Date: 2026-08-01
- Hardware architecture: Apple Silicon arm64
- macOS: 26.5.2
- Build: Release, Apple Development signed, Hardened Runtime, non-sandboxed
- Installed bundle: `/Library/Input Methods/MacWubi.app`
- Installed executable SHA-256: `c45f847ef21aac53bc5561c3e8b44b1518f0f31c677f9cb3dcaa2ac918735b2b`
- Product data root: `~/Library/Application Support/org.macwubi.inputmethod/`

## Independent acceptance flow

The personalization integration suite created a user entry, persisted it through a new store instance,
captured an immutable older generation while publishing a newer generation, and proved that corrupting
Learning did not alter UserLexicon. It then selected a non-first candidate three times, verified promotion,
cleared learning, and verified restoration of base order.

With private mode enabled, the suite performed 10,000 candidate submissions. Every result had no learning
delta, the engine ended idle, and a content-checksum fingerprint of every file under the isolated product
data root was byte-identical before and after the run.

The AppKit command contract verified a visible privacy indicator plus checked `私密模式` and `本地学习`
menu commands. The controller updated every registered active session in one operation. Adapter coverage
also verified that a learning delta reaches persistence only after the client commit succeeds.

## Persistence and ranking checks

- MWSN v1 envelopes validate domain, schema, generation, length, and payload FNV-1a checksum.
- Root/domain permissions are `0700`; current, previous, and staging snapshots are `0600`.
- Replacement retains one validated previous snapshot; injected interruption does not publish a generation.
- User entries validate and deduplicate `(code, text)` while preserving manual origin priority.
- Learning is capped at 50,000 records and score 1,000,000, decays by monotonic epoch, and prunes
  deterministically.
- Candidate merge order is fixed user rank, learned score, base rank, then text UTF-8 bytes.

## Validation commands

```bash
Scripts/test.sh
MACWUBI_CODE_SIGN_IDENTITY='Apple Development: luoagol@gmail.com (6XRC4PBH7N)' Scripts/build-release.sh
Scripts/verify-release.sh /Users/agol/repos/wb86/.build/xcode/Build/Products/Release/MacWubi.app
xcrun swift Scripts/select-input-source.swift
```

`Scripts/test.sh` passed 74 tests with zero failures and rebuilt the deterministic arm64 dictionary
compiler. Release verification passed exact arm64, strict signature, Hardened Runtime, empty offline
entitlements, metadata, and Apple-system-only dependency checks. TIS enumerated exactly one selected Mac
Wubi source after installation.

## Remaining release gaps

- User-facing entry editing is exposed by the service and will be surfaced in the settings window in US4.
- macOS 13 physical runtime validation remains deferred to T081/T083/T110.
- Developer ID timestamp, notarization, stapling, and Gatekeeper assessment remain deferred to T108/T111.
