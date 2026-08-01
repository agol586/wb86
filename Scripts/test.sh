#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$repo_root/.build/tests"
fixture_dir="$repo_root/Tests/Fixtures/Lexicon"
fixture_source="$fixture_dir/wb86-acceptance.tsv"
known_vectors="$fixture_dir/known-vectors.json"

xcodebuild test \
  -project "$repo_root/MacWubi.xcodeproj" \
  -scheme MacWubi \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data"

xcodebuild build \
  -project "$repo_root/MacWubi.xcodeproj" \
  -target MacWubiDictionaryCompiler \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$derived_data/Build/Products" \
  OBJROOT="$derived_data/Build/Intermediates.noindex" \
  ARCHS=arm64 \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual

plutil -convert xml1 -o /dev/null "$known_vectors"
if LC_ALL=C grep -q $'\r' "$fixture_source"; then
  echo "fixture must use LF line endings" >&2
  exit 65
fi

fixture_count="$(awk -F '\t' '
  NF != 3 || $1 !~ /^[a-y]{1,4}$/ || $2 == "" || $3 !~ /^[0-9]+$/ { exit 65 }
  { count += 1 }
  END { if (count == 0) exit 65; print count }
' "$fixture_source")"
expected_count="$(plutil -extract recordCount raw -o - "$known_vectors")"
[[ "$fixture_count" == "$expected_count" ]] || {
  echo "fixture record count does not match known vectors" >&2
  exit 65
}

fixture_output="$(mktemp -d -t macwubi-fixture-check)"
trap 'rm -rf "$fixture_output"' EXIT
compiler="$derived_data/Build/Products/Release/macwubi-dictionary-compiler"
"$compiler" \
  --input "$fixture_source" \
  --output "$fixture_output/wb86.bin" \
  --manifest "$fixture_output/wb86.manifest.json" \
  --license-id LGPL-3.0-only \
  --source-revision 152a0d3f3efe40cae216d1e3b338242446848d07

plutil -convert xml1 -o /dev/null "$fixture_output/wb86.manifest.json"
[[ "$(plutil -extract recordCount raw -o - "$fixture_output/wb86.manifest.json")" == \
  "$expected_count" ]]
[[ "$(xxd -p -l 4 "$fixture_output/wb86.bin")" == "57423836" ]] || {
  echo "compiled fixture has an invalid dictionary magic" >&2
  exit 65
}

echo "test verification passed: XCTest suites and deterministic lexicon fixtures"
