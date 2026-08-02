# Test target map

`MacWubiTests` contains core, adapter, dictionary, persistence, migration, import/export, failure,
privacy, performance, integration, and unsupported-assistive-technology boundary XCTest sources.
`MacWubiReleaseTests` isolates
release-contract checks that inspect built artifacts and shell entry points.

Tests must be deterministic, must not access the network, and must not print raw keys, marked text,
candidate text, committed text, application identity, document context, or external file paths.
