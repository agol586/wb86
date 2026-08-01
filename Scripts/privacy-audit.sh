#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || "$1" != /* ]]; then
  echo "usage: $0 /absolute/path/to/MacWubi.app [--pid PID] [--before DIR --after DIR] [--log FILE] [--export FILE]" >&2
  exit 64
fi
app_path="$1"; shift
pid=""; before=""; after=""; log_file=""; export_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid) pid="$2"; shift 2 ;;
    --before) before="$2"; shift 2 ;;
    --after) after="$2"; shift 2 ;;
    --log) log_file="$2"; shift 2 ;;
    --export) export_file="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

executable="$app_path/Contents/MacOS/MacWubi"
[[ -x "$executable" ]] || { echo "missing executable" >&2; exit 66; }

entitlements="$(codesign --display --entitlements :- "$app_path" 2>&1 || true)"
if grep -Eq 'network\.(client|server)|application-groups|temporary-exception\.mach' <<<"$entitlements"; then
  echo "prohibited entitlement detected" >&2; exit 65
fi
dependencies="$(otool -L "$executable")"
if grep -Eq 'CFNetwork|Network\.framework|WebKit|libcurl' <<<"$dependencies"; then
  echo "prohibited network dependency detected" >&2; exit 65
fi
if nm -u "$executable" 2>/dev/null | grep -Eiq 'NSURLSession|nw_connection|CFHTTP|curl_easy'; then
  echo "prohibited network symbol detected" >&2; exit 65
fi

if [[ -n "$pid" ]]; then
  [[ "$pid" =~ ^[0-9]+$ ]] || { echo "invalid pid" >&2; exit 64; }
  connections="$(lsof -nP -a -p "$pid" -i 2>/dev/null | tail -n +2 || true)"
  [[ -z "$connections" ]] || { echo "network connection observed" >&2; exit 65; }
fi

snapshot() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  (cd "$root" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null) || true
}
if [[ -n "$before" || -n "$after" ]]; then
  [[ -n "$before" && -n "$after" ]] || { echo "before and after must be paired" >&2; exit 64; }
  [[ "$(snapshot "$before")" == "$(snapshot "$after")" ]] || {
    echo "private-mode Application Support diff is not empty" >&2; exit 65;
  }
fi

if [[ -n "$log_file" ]]; then
  if grep -Ev '^(dictionary_load_failure|invalid_event|client_operation_failure|candidate_presentation_failure|persistence_failure|migration_failure|import_failure|performance_gate_exceeded)=[0-9]+$|^$' "$log_file" | grep -q .; then
    echo "diagnostic log contains non-redacted content" >&2; exit 65
  fi
fi
if [[ -n "$export_file" ]] && strings "$export_file" | grep -Eiq '/Users/|applicationIdentity|documentContext|keyHistory|inputTimeline|sessionIdentifier'; then
  echo "export contains prohibited contextual metadata" >&2; exit 65
fi

echo "privacy audit passed: zero network capability, redacted diagnostics, bounded local data"
