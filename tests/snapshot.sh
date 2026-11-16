#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/update-tux.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

DELETED=()
run_privileged() {
  [[ "$1 $2 $3" == 'btrfs subvolume delete' ]] || exit 99
  DELETED+=("${4##*/}")
  [[ "$4" != *FAIL* ]]
}

prune_old_snapshots "$TEST_DIR" > /dev/null
[[ ${#DELETED[@]} == 0 ]]
printf 'OK: empty snapshot dir is a no-op\n'

mkdir "$TEST_DIR"/root-{20260101000000,20260301000000,20260201000000}
prune_old_snapshots "$TEST_DIR" > /dev/null
[[ ${#DELETED[@]} == 0 ]]
printf 'OK: keeps up to 3 snapshots\n'

mkdir "$TEST_DIR"/root-20251201000000 "$TEST_DIR"/root-20260401000000 "$TEST_DIR"/other
prune_old_snapshots "$TEST_DIR" > /dev/null
[[ "${DELETED[*]}" == 'root-20251201000000 root-20260101000000' ]]
printf 'OK: deletes only the oldest root-* snapshots\n'

DELETED=()
mkdir "$TEST_DIR"/root-2025FAIL
output="$(prune_old_snapshots "$TEST_DIR")"
[[ "$output" == *'Nao foi possivel remover'* ]]
printf 'OK: delete failure only warns\n'
