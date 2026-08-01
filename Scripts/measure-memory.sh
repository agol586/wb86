#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 || ( -n "${1:-}" && ! "${1:-}" =~ ^[0-9]+$ ) ]]; then
  echo "usage: Scripts/measure-memory.sh [MacWubi-pid]" >&2
  exit 64
fi

pid="${1:-$(pgrep -x MacWubi | head -1)}"
[[ -n "$pid" ]] || { echo "MacWubi process is not running" >&2; exit 69; }
report="$(/usr/bin/footprint -f bytes --noCategories "$pid")"
bytes="$(printf '%s\n' "$report" | /usr/bin/awk '/^[[:space:]]*phys_footprint:/ { print $2; exit }')"
[[ "$bytes" =~ ^[0-9]+$ ]] || { echo "unable to parse physical footprint" >&2; exit 65; }

budget=15728640
printf 'pid=%s\nphysicalFootprintBytes=%s\nbudgetBytes=%s\n' "$pid" "$bytes" "$budget"
(( bytes < budget )) || { echo "memory gate failed" >&2; exit 1; }
echo "memory gate passed"
