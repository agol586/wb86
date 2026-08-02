#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: Scripts/measure-memory.sh /absolute/path/to/MacWubi.app|MacWubi-pid" >&2
  exit 64
fi

target="$1"
app_path=""
started_pid=""
if [[ "$target" =~ ^[0-9]+$ ]]; then
  pid="$target"
else
  [[ "$target" == /* && "$target" == *.app && -d "$target" ]] || {
    echo "usage: Scripts/measure-memory.sh /absolute/path/to/MacWubi.app|MacWubi-pid" >&2
    exit 64
  }
  app_path="$target"
  executable="$app_path/Contents/MacOS/MacWubi"
  [[ -x "$executable" ]] || { echo "missing executable" >&2; exit 66; }
  pid="$(pgrep -f "$executable --memory-probe" | head -1 || true)"
  if [[ -z "$pid" ]]; then
    "$executable" --memory-probe >/dev/null 2>&1 &
    pid="$!"
    started_pid="$pid"
    for _ in {1..50}; do
      kill -0 "$pid" 2>/dev/null || break
      /usr/bin/vmmap "$pid" 2>/dev/null | grep -F -q 'pinyin-simp.bin' && break
      sleep 0.1
    done
  fi
fi
[[ -n "$pid" ]] || { echo "MacWubi process is not running" >&2; exit 69; }
cleanup() {
  [[ -z "$started_pid" ]] || kill "$started_pid" 2>/dev/null || true
}
trap cleanup EXIT
report="$(/usr/bin/footprint -f bytes --noCategories "$pid")"
bytes="$(printf '%s\n' "$report" | /usr/bin/awk '/^[[:space:]]*phys_footprint:/ { print $2; exit }')"
[[ "$bytes" =~ ^[0-9]+$ ]] || { echo "unable to parse physical footprint" >&2; exit 65; }

budget=15728640
printf 'pid=%s\nphysicalFootprintBytes=%s\nbudgetBytes=%s\n' "$pid" "$bytes" "$budget"
(( bytes < budget )) || { echo "memory gate failed" >&2; exit 1; }

if [[ -n "$app_path" ]]; then
  pinyin_path="$app_path/Contents/Resources/pinyin-simp.bin"
  [[ -f "$pinyin_path" ]] || { echo "missing MWPY resource" >&2; exit 66; }
  pinyin_bytes="$(stat -f '%z' "$pinyin_path")"
  pinyin_sha256="$(shasum -a 256 "$pinyin_path" | awk '{print $1}')"
  mapping_count="$(/usr/bin/vmmap "$pid" 2>/dev/null | grep -F -c 'pinyin-simp.bin' || true)"
  printf 'pinyinResourceBytes=%s\npinyinResourceSHA256=%s\npinyinMappedRegionCount=%s\n' \
    "$pinyin_bytes" "$pinyin_sha256" "$mapping_count"
  (( pinyin_bytes > 0 && pinyin_bytes <= 4194304 )) || {
    echo "MWPY resource size gate failed" >&2; exit 1
  }
  (( mapping_count == 1 )) || {
    echo "MWPY shared mapping gate failed" >&2; exit 1
  }
fi
echo "memory gate passed"
