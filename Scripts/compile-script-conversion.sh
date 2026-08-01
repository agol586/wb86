#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
derived_data="$repo_root/.build/script-conversion-compiler"

xcodebuild \
  -project "$repo_root/MacWubi.xcodeproj" \
  -scheme MacWubiDictionaryCompiler \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  build \
  CODE_SIGNING_ALLOWED=NO

"$derived_data/Build/Products/Release/macwubi-dictionary-compiler" script-conversion \
  --characters "$repo_root/Sources/Resources/ThirdParty/opencc/OpenCC-STCharacters.txt" \
  --phrases "$repo_root/Sources/Resources/ThirdParty/opencc/OpenCC-STPhrases.txt" \
  --output "$repo_root/Sources/Resources/script-conversion.bin" \
  --manifest "$repo_root/Sources/Resources/script-conversion.manifest.json" \
  --license-id Apache-2.0 \
  --source-revision 2f569603954f1cddfdef7b648e71e1aa0d1f47a3
