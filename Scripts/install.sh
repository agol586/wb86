#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != /* || ! -d "$1" ]]; then
  echo "usage: $0 /absolute/path/to/MacWubi.app" >&2
  exit 64
fi

source_app="${1%/}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
install_root="${MACWUBI_TEST_INSTALL_ROOT:-/Library/Input Methods}"
verify_tool="${MACWUBI_VERIFY_RELEASE_TOOL:-$script_dir/verify-release.sh}"
destination="$install_root/MacWubi.app"
staging="$install_root/.MacWubi.app.staging.$PPID"
backup="$install_root/.MacWubi.app.previous.$PPID"

if [[ -n "${MACWUBI_TEST_INSTALL_ROOT:-}" && "$install_root" != /tmp/* && "$install_root" != /var/folders/* ]]; then
  echo "test install root must be a temporary directory" >&2
  exit 65
fi
if [[ -n "${MACWUBI_VERIFY_RELEASE_TOOL:-}" && -z "${MACWUBI_TEST_INSTALL_ROOT:-}" ]]; then
  echo "verification override is test-root only" >&2
  exit 65
fi

"$verify_tool" "$source_app"

run_privileged() {
  if [[ "$install_root" == "/Library/Input Methods" ]]; then
    /usr/bin/sudo "$@"
  else
    "$@"
  fi
}

rollback() {
  run_privileged /bin/rm -rf "$staging"
  if [[ -d "$backup" && ! -e "$destination" ]]; then
    run_privileged /bin/mv "$backup" "$destination"
  fi
}
trap rollback ERR INT TERM

run_privileged /bin/mkdir -p "$install_root"
run_privileged /bin/rm -rf "$staging" "$backup"
run_privileged /usr/bin/ditto "$source_app" "$staging"
"$verify_tool" "$staging"
if [[ -e "$destination" ]]; then
  run_privileged /bin/mv "$destination" "$backup"
fi
run_privileged /bin/mv "$staging" "$destination"
"$verify_tool" "$destination"
run_privileged /bin/rm -rf "$backup"
trap - ERR INT TERM

echo "installed verified arm64 input method at $destination"
