#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* ]]; then
  echo "usage: $0 /absolute/path/to/MacWubi.app" >&2
  exit 64
fi

app_path="$1"
executable="$app_path/Contents/MacOS/MacWubi"
info_plist="$app_path/Contents/Info.plist"

[[ -d "$app_path" ]] || { echo "bundle not found" >&2; exit 66; }
[[ -x "$executable" ]] || { echo "main executable not found" >&2; exit 66; }

architectures="$(lipo -archs "$executable")"
[[ "$architectures" == "arm64" ]] || {
  echo "expected exactly arm64, got: $architectures" >&2
  exit 65
}

plutil -lint "$info_plist"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
[[ "$bundle_identifier" == "org.macwubi.inputmethod.MacWubi" ]]
[[ "$bundle_identifier" == *'.inputmethod.'* ]] || {
  echo "bundle identifier must contain the InputMethodKit-required .inputmethod. segment" >&2
  exit 65
}
[[ "$(plutil -extract InputMethodConnectionName raw -o - "$info_plist")" == \
  "org.macwubi.inputmethod.MacWubi_Connection" ]]
[[ -n "$(plutil -extract InputMethodServerControllerClass raw -o - "$info_plist")" ]]
[[ "$(plutil -extract LSBackgroundOnly raw -o - "$info_plist")" == "true" ]]

codesign --verify --deep --strict --verbose=2 "$app_path"
codesign_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
if ! grep -Eq 'flags=.*runtime' <<<"$codesign_details"; then
  echo "Hardened Runtime is not enabled" >&2
  exit 65
fi

if [[ "${MACWUBI_REQUIRE_DISTRIBUTION:-0}" == "1" ]]; then
  grep -q '^Authority=Developer ID Application:' <<<"$codesign_details" || {
    echo "distribution verification requires Developer ID Application" >&2
    exit 65
  }
  grep -q '^Timestamp=' <<<"$codesign_details" || {
    echo "distribution signature requires a secure timestamp" >&2
    exit 65
  }
  xcrun stapler validate "$app_path"
  spctl --assess --type install --verbose=4 "$app_path"
fi
entitlements_file="$(mktemp -t macwubi-entitlements)"
trap 'rm -f "$entitlements_file"' EXIT
entitlements_output="$(codesign --display --entitlements :- "$app_path" 2>&1)"
if grep -q '<?xml' <<<"$entitlements_output"; then
  printf '%s\n' "$entitlements_output" | sed -n '/<?xml/,$p' > "$entitlements_file"
  plutil -lint "$entitlements_file"
  if grep -q '<key>' "$entitlements_file"; then
    echo "production entitlements must be empty" >&2
    plutil -p "$entitlements_file" >&2
    exit 65
  fi
fi

if otool -L "$executable" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)'; then
  echo "non-system dynamic dependency present" >&2
  exit 65
fi

echo "release verification passed: arm64, signed, hardened, non-sandboxed, offline"
