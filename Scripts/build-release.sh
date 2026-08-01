#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$repo_root/.build/xcode"
macwubi_sign_identity="${MACWUBI_CODE_SIGN_IDENTITY:--}"

exec xcodebuild build \
  -project "$repo_root/MacWubi.xcodeproj" \
  -scheme MacWubi \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$macwubi_sign_identity" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_STYLE=Manual
