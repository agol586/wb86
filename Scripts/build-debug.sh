#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$repo_root/.build/xcode"

exec xcodebuild build \
  -project "$repo_root/MacWubi.xcodeproj" \
  -scheme MacWubi \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  ARCHS=arm64 \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual
