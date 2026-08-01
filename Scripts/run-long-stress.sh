#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
duration_seconds="${1:-28800}"
[[ "$duration_seconds" =~ ^[1-9][0-9]*$ ]] || {
  echo "usage: Scripts/run-long-stress.sh [positive-duration-seconds]" >&2
  exit 64
}

mkdir -p "$repo_root/.build"
duration_file="$repo_root/.build/long-run-duration"
cleanup() { rm -f "$duration_file"; }
trap cleanup EXIT
printf '%s\n' "$duration_seconds" > "$duration_file"

xcodebuild test \
  -project "$repo_root/MacWubi.xcodeproj" \
  -scheme MacWubi \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$repo_root/.build/long-run" \
  -only-testing:MacWubiTests/LongRunStressTests \
  ENABLE_TESTABILITY=YES \
  CODE_SIGNING_ALLOWED=NO
