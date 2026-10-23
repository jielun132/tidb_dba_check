#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_dir/tidb_dba_check.sh"

bash -n "$script"
bash -n "$repo_dir/tests/smoke.sh"

for option in -h --help; do
    output=$(bash "$script" "$option")
    case "$output" in
        *"Usage: tidb_dba_check.sh {cluster-name}"*) ;;
        *) printf 'FAIL: missing usage for %s\n' "$option" >&2; exit 1 ;;
    esac
done

if output=$(bash "$script" 2>&1); then
    printf 'FAIL: missing cluster name must return a non-zero status\n' >&2
    exit 1
else
    status=$?
    if [[ "$status" -ne 1 || "$output" != *"Missing cluster name"* ]]; then
        printf 'FAIL: unexpected missing-argument response (status %s)\n' "$status" >&2
        exit 1
    fi
fi

printf 'PASS: Bash syntax, both help flags, and missing-cluster behavior\n'
