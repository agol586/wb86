#!/bin/bash
set -euo pipefail

delete_data=false
if [[ $# -gt 1 ]]; then
  echo "usage: $0 [--delete-data]" >&2
  exit 64
fi
if [[ $# -eq 1 ]]; then
  [[ "$1" == "--delete-data" ]] || { echo "unknown option" >&2; exit 64; }
  delete_data=true
fi

install_root="${MACWUBI_TEST_INSTALL_ROOT:-/Library/Input Methods}"
destination="$install_root/MacWubi.app"
if [[ -n "${MACWUBI_TEST_INSTALL_ROOT:-}" && "$install_root" != /tmp/* && "$install_root" != /var/folders/* ]]; then
  echo "test install root must be a temporary directory" >&2
  exit 65
fi

if [[ "$install_root" == "/Library/Input Methods" ]]; then
  /usr/bin/sudo /bin/rm -rf "$destination"
else
  /bin/rm -rf "$destination"
fi

if $delete_data; then
  if [[ -n "${MACWUBI_TEST_DATA_ROOT:-}" ]]; then
    data_root="${MACWUBI_TEST_DATA_ROOT%/}"
    [[ "$data_root" == /tmp/* || "$data_root" == /var/folders/* ]] || {
      echo "test data root must be temporary" >&2; exit 65;
    }
  else
    current_user="$(/usr/bin/id -un)"
    user_home="$(/usr/bin/dscl . -read "/Users/$current_user" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
    [[ -n "$user_home" && "$user_home" == /Users/* ]] || { echo "cannot resolve user home" >&2; exit 65; }
    data_root="$user_home/Library/Application Support/org.macwubi.inputmethod"
  fi
  /bin/rm -rf "$data_root"
  echo "removed input method and personalization data"
else
  echo "removed input method; personalization data preserved"
fi
