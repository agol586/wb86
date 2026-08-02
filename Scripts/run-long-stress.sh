#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || "$1" != /* ]]; then
  echo "usage: Scripts/run-long-stress.sh /absolute/path/to/MacWubi.app [target-committed-characters]" >&2
  exit 64
fi
app_path="$1"
target_characters="${2:-1000000}"
[[ "$target_characters" =~ ^[1-9][0-9]*$ ]] || {
  echo "usage: Scripts/run-long-stress.sh /absolute/path/to/MacWubi.app [target-committed-characters]" >&2
  exit 64
}
(( target_characters <= 10000000 )) || { echo "target exceeds 10000000-character safety bound" >&2; exit 64; }
executable="$app_path/Contents/MacOS/MacWubi"
[[ -x "$executable" ]] || { echo "missing executable" >&2; exit 66; }

report_file="$(mktemp -t macwubi-monthly-volume-report)"
cleanup() { rm -f "$report_file"; }
trap cleanup EXIT
"$executable" --monthly-volume-probe "$target_characters" | tee "$report_file"

probe_line="$(grep '^MACWUBI_MONTHLY_VOLUME_REPORT ' "$report_file" | tail -1)"
[[ -n "$probe_line" ]] || { echo "monthly volume report missing" >&2; exit 65; }
field() {
  printf '%s\n' "$probe_line" | awk -v key="$1" '{for(i=1;i<=NF;i++) if($i ~ ("^" key "=")){split($i,a,"="); print a[2]}}'
}
committed_characters="$(field committedCharacters)"
logical_days="$(field logicalDays)"
learning_deltas="$(field learningDeltas)"
first_latency="$(printf '%s\n' "$probe_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^firstAverageLatencyNs=/){split($i,a,"="); print a[2]}}')"
last_latency="$(printf '%s\n' "$probe_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^lastAverageLatencyNs=/){split($i,a,"="); print a[2]}}')"
maximum_latency="$(printf '%s\n' "$probe_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^maximumLatencyNs=/){split($i,a,"="); print a[2]}}')"
first_average="$(field firstSteadyBytes)"
last_average="$(field lastSteadyBytes)"
maximum_bytes="$(field maximumBytes)"
for value in "$committed_characters" "$logical_days" "$learning_deltas" "$first_latency" \
             "$last_latency" "$maximum_latency" "$first_average" "$last_average" "$maximum_bytes"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { echo "monthly volume report invalid" >&2; exit 65; }
done
(( committed_characters >= target_characters )) || {
  echo "committed-character target not reached" >&2; exit 1
}
(( logical_days == 30 )) || { echo "logical-day coverage failed" >&2; exit 1; }
(( learning_deltas > 0 )) || { echo "learning workload was not exercised" >&2; exit 1; }
(( first_latency > 0 && last_latency > 0 )) || { echo "latency windows were not exercised" >&2; exit 1; }
budget_bytes=15728640
allowed_drift_bytes=1048576
printf 'MACWUBI_MONTHLY_VOLUME_GATE targetCharacters=%s logicalDays=%s firstAverageBytes=%s lastAverageBytes=%s maximumBytes=%s budgetBytes=%s allowedDriftBytes=%s\n' \
  "$target_characters" "$logical_days" "$first_average" "$last_average" "$maximum_bytes" "$budget_bytes" "$allowed_drift_bytes"
(( maximum_bytes < budget_bytes )) || { echo "stress memory budget failed" >&2; exit 1; }
(( last_average <= first_average + allowed_drift_bytes )) || {
  echo "stress sustained memory growth detected" >&2; exit 1
}
(( last_latency <= first_latency + 200000 )) || {
  echo "stress sustained latency growth detected" >&2; exit 1
}
