# Privacy

Mac Wubi processes input entirely on the Mac. The input method and settings code do not create
network connections, use telemetry, require accounts, show advertising, perform cloud sync, or check
for online updates. The signed product has no network client/server entitlement and links no network
client framework. It processes only events supplied to the active InputMethodKit session and installs
no global key monitor.

## Local data

Mutable data is restricted to `~/Library/Application Support/org.macwubi.inputmethod/` with a private
`0700` root and `0600` files:

- `Settings/current`: input behavior, key and candidate appearance settings.
- `UserLexicon/current`: terms the user explicitly adds or imports.
- `Learning/current`: bounded local candidate-ranking scores.

Each domain is independently versioned and may retain one validated `previous` snapshot. The privacy
view reports purpose, logical location, schema and byte count without displaying entry contents,
input history, application identity, document context, paths, timestamps or session history. The base
Wubi dictionary and conversion tables are signed, read-only bundle resources.

External lexicon files are accessed only after an explicit system open/save panel choice. Access ends
with that operation; no security-scoped bookmark or source path is retained.

## Controls and deletion

Private mode is always visible. While enabled, no learning write is produced and existing learning
scores do not affect ranking. Disabling learning provides the same learning-write guarantee.

Settings, UserLexicon and Learning can be deleted separately. “Delete all personalization” attempts
all three domains, reports each failure truthfully, and never deletes the signed base dictionary.
Uninstall preserves data unless `--delete-data` is explicitly selected.

Production diagnostics contain only fixed error-category counters. They never include raw keys,
marked or committed text, candidates, application/document identity, file paths or reconstructable
timelines. `Scripts/privacy-audit.sh` verifies entitlements, linked frameworks/symbols, live process
connections, optional private-mode filesystem diffs, diagnostic output and exports.

macOS does not provide InputMethodKit with a reliable per-client secure-field callback. Mac Wubi does
not claim automatic password-field detection and does not treat a global secure-event flag as proof.
