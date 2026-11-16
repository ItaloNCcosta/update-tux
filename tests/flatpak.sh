#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/update-tux.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

has_command() {
  case "$1" in
    flatpak) return 0 ;;
    systemd-run|systemctl) [[ "${USE_SYSTEMD:-0}" == 1 ]] ;;
    *) return 1 ;;
  esac
}

systemctl() {
  if [[ "$*" == '--user stop update-tux-flatpak-'* ]]; then
    printf 'stop\n' >> "$TEST_DIR/calls"
    return 0
  fi
  [[ "$*" == '--user is-active --quiet default.target' ]]
}

systemd-run() {
  [[ "${*:1:6}" == '--user --quiet --pipe --wait --collect --property=RestrictAddressFamilies=AF_UNIX AF_INET AF_NETLINK' ]] || exit 95
  [[ "$7" == --unit=update-tux-flatpak-* ]] || exit 94
  printf 'ipv4\n' >> "$TEST_DIR/calls"
  shift 7
  "$@"
}

flatpak() {
  [[ "$*" == 'update -y --noninteractive' ]] || exit 99
  printf 'flatpak\n' >> "$TEST_DIR/calls"
  if (( ${#RESULTS[@]} == 0 )); then
    exit 98
  fi
  local result="${RESULTS[0]}"
  RESULTS=("${RESULTS[@]:1}")
  return "$result"
}

sleep() {
  [[ "$*" == 5 ]] || exit 97
  printf 'sleep\n' >> "$TEST_DIR/calls"
}

check_case() {
  local name="$1" expected_status="$2" expected_calls="$3"
  shift 3
  : > "$TEST_DIR/calls"
  local actual_status=0
  (
    RESULTS=("$@")
    EXECUTED_STEPS=()
    update_flatpak_packages
    [[ "${EXECUTED_STEPS[*]}" == flatpak ]] || exit 96
    printf 'success\n' >> "$TEST_DIR/calls"
  ) > "$TEST_DIR/output" 2>&1 || actual_status=$?
  if [[ "$actual_status" != "$expected_status" || "$(< "$TEST_DIR/calls")" != "$expected_calls" ]]; then
    printf 'FAIL: %s (exit %s, expected %s)\n' "$name" "$actual_status" "$expected_status" >&2
    cat "$TEST_DIR/output" "$TEST_DIR/calls" >&2
    exit 1
  fi
  printf 'OK: %s\n' "$name"
}

check_case 'success without retry' 0 $'flatpak\nsuccess' 0
check_case 'failure followed by success' 0 $'flatpak\nsleep\nflatpak\nsuccess' 1 0
check_case 'persistent failure stops the script' 1 $'flatpak\nsleep\nflatpak' 1 1
check_case 'interruption is not retried' 130 flatpak 130
check_case 'termination is not retried' 143 flatpak 143
check_case 'interruption during retry' 130 $'flatpak\nsleep\nflatpak' 1 130
USE_SYSTEMD=1 check_case 'retry uses IPv4 with systemd' 0 $'flatpak\nsleep\nipv4\nflatpak\nsuccess' 1 0
USE_SYSTEMD=1 check_case 'IPv4 failure still stops the script' 1 $'flatpak\nsleep\nipv4\nflatpak' 1 1
USE_SYSTEMD=1 check_case 'interruption stops the IPv4 service' 130 $'flatpak\nsleep\nipv4\nflatpak\nstop' 1 130
has_command() { return 1; }
EXECUTED_STEPS=()
update_flatpak_packages
[[ ${#EXECUTED_STEPS[@]} == 0 ]]
printf 'OK: missing flatpak is skipped\n'

status=0
bash -c 'source "$1"; print_banner() { :; }; prepare_environment() { kill -INT "$BASHPID"; exit 99; }; main' \
  _ "$SCRIPT_DIR/update-tux.sh" || status=$?
[[ "$status" == 130 ]]
printf 'OK: main preserves SIGINT even when a child handles the signal\n'
