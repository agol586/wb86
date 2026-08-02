# Normal Input Memory Evidence

Status: **PASS on development candidates; amended monthly-volume gate passes, final OS matrix pending**

Measured 2026-08-01 after approximately 55 minutes of installed input-method process uptime on `Mac15,12`,
Apple M3, arm64, macOS 26.5.2. Candidate: Apple Development-signed, Hardened Runtime, exact arm64 bundle at
`/Library/Input Methods/MacWubi.app`; `Scripts/verify-release.sh` passed.

```text
physicalFootprintBytes=11617096
budgetBytes=15728640
memory gate passed
```

Command: `Scripts/measure-memory.sh 52418`. macOS `footprint -f bytes --noCategories` is the release metric:
physical footprint measures the process-owned resident cost and apportions shared/reclaimable pages. For
diagnostic transparency, `ps` reported roughly 50 MiB RSS because it counts resident shared Apple framework
pages; `vmmap` showed a physical footprint of about 11.1 MiB and hundreds of MiB of shared-cache resident
pages. The product budget is assessed using `phys_footprint`, not the misleading un-apportioned RSS total.

The earlier long-running sample suggested the mapped 3,974,577-byte image could remain under budget, but it
did not expose fresh-start allocator retention. Final release must measure both fresh and steady normal input
on every declared hardware/OS target.

On 2026-08-01 a fresh restart of the pre-remediation build reproducibly measured about 22.9 MiB, including
roughly 9 MiB of `MALLOC_LARGE` retained after validation materialized all 136,233 records. T105 was reopened.
The first streaming candidate reduced fresh/loaded footprint to 2,802,168/13,796,120 bytes, but a synthetic
client flow later reached 15,827,784 bytes and correctly failed the strict gate. Runtime validation was then
changed again to validate UTF-8 and ordering directly over mapped bytes without constructing 136,233
temporary strings. Final remediation candidate SHA-256 is
`8237827cdf536400d9f41c673e299e12aceb42d8c4c6414715ea511e568ca048`; all 115 automated tests, release
verification and privacy audit pass.

Final installed verification on process 67230 used the exact candidate hash above. Physical-footprint
samples were 9,831,024 bytes fresh, 13,779,760 bytes after dictionary initialization, 13,681,456 bytes
immediately after the privacy-safe client smoke flow, and 14,074,696 bytes five seconds later. All four are
strictly below 15,728,640 bytes. `footprint` showed no `MALLOC_LARGE` category. T105 therefore passes on this
Apple M3/macOS 26.5.2 development matrix row. The active feature's amended 30-logical-day,
1,000,000-committed-character gate later peaked at 8,487,584 bytes and passed sustained-growth checks; see
`specs/002-settings-experience/evidence/monthly-volume-stress.md`. The final OS matrix remains open.
