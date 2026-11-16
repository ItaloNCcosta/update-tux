#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/update-tux.sh"

CALLS=()
LOCK_BUSY=0
has_command() { [[ "$1" == fuser ]]; }
run_privileged() {
  CALLS+=("$1")
  if [[ "$1" == fuser ]]; then
    (( LOCK_BUSY > 0 )) && { LOCK_BUSY=$((LOCK_BUSY - 1)); return 0; }
    return 1
  fi
}
sleep() { CALLS+=(sleep); }

LOCK_BUSY=2
run_apt nala update > /dev/null
[[ "${CALLS[*]}" == 'fuser sleep fuser sleep fuser nala' ]]
printf 'OK: waits for busy lock before running apt command\n'

CALLS=()
LOCK_BUSY=1000
run_apt nala update > /dev/null
[[ "${CALLS[-1]}" == nala && $(grep -o sleep <<< "${CALLS[*]}" | wc -l) == 60 ]]
printf 'OK: gives up waiting after 5 minutes and tries anyway\n'

CALLS=()
LOCK_BUSY=0
run_deb_upgrade > /dev/null
[[ "${CALLS[*]}" == 'fuser nala fuser nala fuser nala fuser nala' ]]
printf 'OK: every deb step checks the lock\n'
